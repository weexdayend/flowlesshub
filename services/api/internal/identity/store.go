package identity

import (
	"context"
	"crypto/rand"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// PostgresStore is the persistence adapter for identity and tenant records.
// Queries are parameterized pgx statements so transaction boundaries for
// session issuance and owner bootstrap remain explicit in this package.
type PostgresStore struct {
	pool *pgxpool.Pool
}

func NewPostgresStore(pool *pgxpool.Pool) *PostgresStore {
	return &PostgresStore{pool: pool}
}

func (s *PostgresStore) FindUserByEmail(ctx context.Context, normalizedEmail string) (UserRecord, error) {
	var user UserRecord
	err := s.pool.QueryRow(ctx, `
		SELECT id::text, email_normalized, display_name, password_hash, status
		FROM identity.users
		WHERE email_normalized = $1
	`, normalizedEmail).Scan(&user.ID, &user.Email, &user.DisplayName, &user.PasswordHash, &user.Status)
	if err == pgx.ErrNoRows {
		return UserRecord{}, ErrNotFound
	}
	if err != nil {
		return UserRecord{}, fmt.Errorf("find identity user: %w", err)
	}
	return user, nil
}

func (s *PostgresStore) CreateSession(ctx context.Context, userID string, digest []byte, expiresAt time.Time) (string, error) {
	sessionID, err := newUUID()
	if err != nil {
		return "", err
	}
	_, err = s.pool.Exec(ctx, `
		INSERT INTO identity.sessions (id, user_id, token_digest, expires_at)
		VALUES ($1::uuid, $2::uuid, $3, $4)
	`, sessionID, userID, digest, expiresAt.UTC())
	if err != nil {
		return "", fmt.Errorf("create identity session: %w", err)
	}
	return sessionID, nil
}

func (s *PostgresStore) ResolveSession(ctx context.Context, digest []byte, now time.Time) (Principal, error) {
	var principal Principal
	err := s.pool.QueryRow(ctx, `
		UPDATE identity.sessions AS session
		SET last_used_at = $2
		FROM identity.users AS users
		WHERE session.token_digest = $1
		  AND session.user_id = users.id
		  AND session.revoked_at IS NULL
		  AND session.expires_at > $2
		  AND users.status = 'active'
		RETURNING session.id::text, session.expires_at,
		          users.id::text, users.email_normalized, users.display_name
	`, digest, now.UTC()).Scan(
		&principal.SessionID,
		&principal.ExpiresAt,
		&principal.User.ID,
		&principal.User.Email,
		&principal.User.DisplayName,
	)
	if err == pgx.ErrNoRows {
		return Principal{}, ErrUnauthenticated
	}
	if err != nil {
		return Principal{}, fmt.Errorf("resolve identity session: %w", err)
	}
	return principal, nil
}

func (s *PostgresStore) RevokeSession(ctx context.Context, digest []byte, now time.Time) (string, error) {
	var userID string
	err := s.pool.QueryRow(ctx, `
		UPDATE identity.sessions
		SET revoked_at = $2
		WHERE token_digest = $1 AND revoked_at IS NULL
		RETURNING user_id::text
	`, digest, now.UTC()).Scan(&userID)
	if err == pgx.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("revoke identity session: %w", err)
	}
	return userID, nil
}

func (s *PostgresStore) ListOrganizations(ctx context.Context, userID string) ([]Organization, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT organization.id::text, organization.slug_normalized,
		       organization.display_name, membership.role
		FROM tenant.memberships AS membership
		JOIN tenant.organizations AS organization
		  ON organization.id = membership.organization_id
		WHERE membership.user_id = $1::uuid
		  AND membership.status = 'active'
		  AND organization.status = 'active'
		ORDER BY organization.display_name, organization.id
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("list identity organizations: %w", err)
	}
	defer rows.Close()

	organizations := make([]Organization, 0)
	for rows.Next() {
		var organization Organization
		if err := rows.Scan(&organization.ID, &organization.Slug, &organization.DisplayName, &organization.Role); err != nil {
			return nil, fmt.Errorf("scan identity organization: %w", err)
		}
		organizations = append(organizations, organization)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate identity organizations: %w", err)
	}
	return organizations, nil
}

func (s *PostgresStore) RecordAuthEvent(ctx context.Context, eventType string, userID, organizationID *string) error {
	eventID, err := newUUID()
	if err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx, `
		INSERT INTO identity.auth_events (id, user_id, organization_id, event_type)
		VALUES ($1::uuid, $2::uuid, $3::uuid, $4)
	`, eventID, userID, organizationID, eventType)
	if err != nil {
		return fmt.Errorf("record identity auth event: %w", err)
	}
	return nil
}

func (s *PostgresStore) BootstrapOwner(ctx context.Context, input BootstrapRecord) (BootstrapResult, error) {
	var result BootstrapResult
	userID, err := newUUID()
	if err != nil {
		return result, err
	}
	organizationID, err := newUUID()
	if err != nil {
		return result, err
	}
	membershipID, err := newUUID()
	if err != nil {
		return result, err
	}
	eventID, err := newUUID()
	if err != nil {
		return result, err
	}

	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return result, fmt.Errorf("begin owner bootstrap transaction: %w", err)
	}
	defer func() { _ = tx.Rollback(context.Background()) }()

	// Serialize first-owner provisioning across concurrent CLI invocations.
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(5068328311820372273)`); err != nil {
		return result, fmt.Errorf("lock owner bootstrap: %w", err)
	}

	var provisioned bool
	if err := tx.QueryRow(ctx, `
		SELECT EXISTS (SELECT 1 FROM identity.users)
		    OR EXISTS (SELECT 1 FROM tenant.organizations)
		    OR EXISTS (
		        SELECT 1 FROM identity.auth_events
		        WHERE event_type = 'owner_bootstrapped'
		    )
	`).Scan(&provisioned); err != nil {
		return result, fmt.Errorf("check owner bootstrap state: %w", err)
	}
	if provisioned {
		return result, ErrBootstrapCompleted
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO identity.users (id, email_normalized, display_name, password_hash)
		VALUES ($1::uuid, $2, $3, $4)
	`, userID, input.EmailNormalized, input.DisplayName, input.PasswordHash); err != nil {
		return result, fmt.Errorf("insert bootstrap owner: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO tenant.organizations (id, slug_normalized, display_name)
		VALUES ($1::uuid, $2, $3)
	`, organizationID, input.OrganizationSlug, input.OrganizationName); err != nil {
		return result, fmt.Errorf("insert bootstrap organization: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO tenant.memberships (id, organization_id, user_id, role, status)
		VALUES ($1::uuid, $2::uuid, $3::uuid, 'owner', 'active')
	`, membershipID, organizationID, userID); err != nil {
		return result, fmt.Errorf("insert bootstrap owner membership: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO identity.auth_events (id, user_id, organization_id, event_type)
		VALUES ($1::uuid, $2::uuid, $3::uuid, 'owner_bootstrapped')
	`, eventID, userID, organizationID); err != nil {
		return result, fmt.Errorf("record owner bootstrap event: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return result, fmt.Errorf("commit owner bootstrap transaction: %w", err)
	}

	return BootstrapResult{UserID: userID, OrganizationID: organizationID, MembershipID: membershipID}, nil
}

func newUUID() (string, error) {
	var value [16]byte
	if _, err := rand.Read(value[:]); err != nil {
		return "", fmt.Errorf("generate UUID: %w", err)
	}
	value[6] = (value[6] & 0x0f) | 0x40
	value[8] = (value[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		value[0:4], value[4:6], value[6:8], value[8:10], value[10:16]), nil
}
