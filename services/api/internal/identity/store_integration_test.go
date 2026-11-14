package identity

import (
	"context"
	"crypto/sha256"
	"errors"
	"net"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

const integrationPasswordHash = "fh1$argon2id$v=19$m=8192,t=1,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

// TestPostgresStoreIntegration is opt-in and must target a freshly migrated,
// disposable PostgreSQL database on a loopback host whose name ends in _test. It intentionally
// leaves its fixture rows in place; discard the database after the test.
func TestPostgresStoreIntegration(t *testing.T) {
	databaseURL := strings.TrimSpace(os.Getenv("FLOWLESSHUB_TEST_DATABASE_URL"))
	if databaseURL == "" {
		t.Skip("set FLOWLESSHUB_TEST_DATABASE_URL to a fresh, migrated *_test database to run PostgreSQL integration tests")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	poolConfig, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		t.Fatalf("parse PostgreSQL integration database URL: %v", err)
	}
	host := strings.TrimSpace(poolConfig.ConnConfig.Host)
	hostIP := net.ParseIP(host)
	if !strings.EqualFold(host, "localhost") && (hostIP == nil || !hostIP.IsLoopback()) {
		t.Fatalf("refusing non-local PostgreSQL host %q; integration tests only allow localhost/loopback", host)
	}
	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		t.Fatalf("open PostgreSQL integration database: %v", err)
	}
	t.Cleanup(pool.Close)
	if err := pool.Ping(ctx); err != nil {
		t.Fatalf("ping PostgreSQL integration database: %v", err)
	}

	var databaseName string
	if err := pool.QueryRow(ctx, `SELECT current_database()`).Scan(&databaseName); err != nil {
		t.Fatalf("read PostgreSQL database name: %v", err)
	}
	if !strings.HasSuffix(strings.ToLower(databaseName), "_test") {
		t.Fatalf("refusing integration test database %q: database name must end in _test", databaseName)
	}
	var serverVersion int
	if err := pool.QueryRow(ctx, `SELECT current_setting('server_version_num')::integer`).Scan(&serverVersion); err != nil {
		t.Fatalf("read PostgreSQL server version: %v", err)
	}
	if serverVersion < 170000 || serverVersion >= 180000 {
		t.Fatalf("refusing PostgreSQL server version %d; integration target must be PostgreSQL 17", serverVersion)
	}

	assertIdentityDatabaseEmpty(t, ctx, pool)
	store := NewPostgresStore(pool)

	// A durable bootstrap audit marker remains authoritative even when its
	// optional user/organization foreign keys are NULL (for example after
	// manual deletion of historical identity rows).
	markerID, err := newUUID()
	if err != nil {
		t.Fatalf("generate bootstrap marker ID: %v", err)
	}
	if _, err := pool.Exec(ctx, `
        INSERT INTO identity.auth_events (id, event_type)
        VALUES ($1::uuid, 'owner_bootstrapped')
    `, markerID); err != nil {
		t.Fatalf("insert durable bootstrap marker: %v", err)
	}
	if _, err := store.BootstrapOwner(ctx, integrationBootstrapRecord("blocked@example.test", "blocked-org")); !errors.Is(err, ErrBootstrapCompleted) {
		t.Fatalf("bootstrap with durable audit marker error = %v; want ErrBootstrapCompleted", err)
	}
	if _, err := pool.Exec(ctx, `DELETE FROM identity.auth_events WHERE id = $1::uuid`, markerID); err != nil {
		t.Fatalf("remove test bootstrap marker: %v", err)
	}

	// Force a mid-transaction database constraint failure after the user insert.
	// No user, organization, membership, or audit row may survive the rollback.
	invalidRecord := integrationBootstrapRecord("rollback@example.test", "rollback-org")
	invalidRecord.OrganizationName = ""
	if _, err := store.BootstrapOwner(ctx, invalidRecord); err == nil {
		t.Fatal("bootstrap with invalid organization name unexpectedly succeeded")
	}
	assertIdentityDatabaseEmpty(t, ctx, pool)

	// Concurrent first-owner provisioning must produce exactly one winner.
	start := make(chan struct{})
	type bootstrapAttempt struct {
		result BootstrapResult
		err    error
	}
	attempts := make(chan bootstrapAttempt, 2)
	for _, email := range []string{"owner-a@example.test", "owner-b@example.test"} {
		record := integrationBootstrapRecord(email, "flowlesshub-test-org")
		go func(input BootstrapRecord) {
			<-start
			result, err := store.BootstrapOwner(ctx, input)
			attempts <- bootstrapAttempt{result: result, err: err}
		}(record)
	}
	close(start)

	var winner BootstrapResult
	successes := 0
	rejected := 0
	for range 2 {
		attempt := <-attempts
		switch {
		case attempt.err == nil:
			successes++
			winner = attempt.result
		case errors.Is(attempt.err, ErrBootstrapCompleted):
			rejected++
		default:
			t.Fatalf("concurrent bootstrap returned unexpected error: %v", attempt.err)
		}
	}
	if successes != 1 || rejected != 1 {
		t.Fatalf("concurrent bootstrap outcomes: successes=%d rejected=%d; want 1/1", successes, rejected)
	}

	organizations, err := store.ListOrganizations(ctx, winner.UserID)
	if err != nil {
		t.Fatalf("list owner organizations: %v", err)
	}
	if len(organizations) != 1 || organizations[0].ID != winner.OrganizationID || organizations[0].Role != "owner" {
		t.Fatalf("owner organizations = %#v; want exactly the bootstrap organization as owner", organizations)
	}

	// Verify that membership and organization status are both required for a
	// row to appear, and that unrelated users cannot enumerate organizations.
	suspendedMembershipOrgID, err := newUUID()
	if err != nil {
		t.Fatal(err)
	}
	suspendedOrganizationID, err := newUUID()
	if err != nil {
		t.Fatal(err)
	}
	suspendedMembershipID, err := newUUID()
	if err != nil {
		t.Fatal(err)
	}
	suspendedOrganizationMembershipID, err := newUUID()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
        INSERT INTO tenant.organizations (id, slug_normalized, display_name, status)
        VALUES ($1::uuid, 'suspended-membership-org', 'Suspended Membership Org', 'active'),
               ($2::uuid, 'suspended-organization', 'Suspended Organization', 'suspended')
    `, suspendedMembershipOrgID, suspendedOrganizationID); err != nil {
		t.Fatalf("insert membership filter organizations: %v", err)
	}
	if _, err := pool.Exec(ctx, `
        INSERT INTO tenant.memberships (id, organization_id, user_id, role, status)
        VALUES ($1::uuid, $2::uuid, $3::uuid, 'member', 'suspended'),
               ($4::uuid, $5::uuid, $3::uuid, 'member', 'active')
    `, suspendedMembershipID, suspendedMembershipOrgID, winner.UserID, suspendedOrganizationMembershipID, suspendedOrganizationID); err != nil {
		t.Fatalf("insert inactive membership fixtures: %v", err)
	}
	organizations, err = store.ListOrganizations(ctx, winner.UserID)
	if err != nil {
		t.Fatalf("list organizations after inactive fixtures: %v", err)
	}
	if len(organizations) != 1 || organizations[0].ID != winner.OrganizationID {
		t.Fatalf("inactive membership/organization leaked into organization list: %#v", organizations)
	}
	unrelatedUserID, err := newUUID()
	if err != nil {
		t.Fatal(err)
	}
	unrelatedOrganizations, err := store.ListOrganizations(ctx, unrelatedUserID)
	if err != nil {
		t.Fatalf("list organizations for unrelated user: %v", err)
	}
	if len(unrelatedOrganizations) != 0 {
		t.Fatalf("unrelated user received organizations: %#v", unrelatedOrganizations)
	}

	// Verify database-backed session expiry, revocation idempotency, and the
	// disabled-user check in the actual PostgreSQL query path.
	activeDigest := integrationSessionDigest("active-session")
	activeExpiry := time.Now().UTC().Add(time.Hour)
	if _, err := store.CreateSession(ctx, winner.UserID, activeDigest, activeExpiry); err != nil {
		t.Fatalf("create active session: %v", err)
	}
	principal, err := store.ResolveSession(ctx, activeDigest, time.Now().UTC())
	if err != nil || principal.User.ID != winner.UserID {
		t.Fatalf("resolve active session = %#v, %v", principal, err)
	}

	expiredDigest := integrationSessionDigest("expired-session")
	expiredAt := time.Now().UTC().Add(time.Hour)
	if _, err := store.CreateSession(ctx, winner.UserID, expiredDigest, expiredAt); err != nil {
		t.Fatalf("create session for expiry test: %v", err)
	}
	if _, err := store.ResolveSession(ctx, expiredDigest, expiredAt.Add(time.Second)); !errors.Is(err, ErrUnauthenticated) {
		t.Fatalf("resolve expired session error = %v; want ErrUnauthenticated", err)
	}

	revokedDigest := integrationSessionDigest("revoked-session")
	if _, err := store.CreateSession(ctx, winner.UserID, revokedDigest, time.Now().UTC().Add(time.Hour)); err != nil {
		t.Fatalf("create session for revocation test: %v", err)
	}
	revokedUserID, err := store.RevokeSession(ctx, revokedDigest, time.Now().UTC())
	if err != nil || revokedUserID != winner.UserID {
		t.Fatalf("revoke session = user %q, error %v", revokedUserID, err)
	}
	repeatedUserID, err := store.RevokeSession(ctx, revokedDigest, time.Now().UTC())
	if err != nil || repeatedUserID != "" {
		t.Fatalf("repeat revoke = user %q, error %v; want empty user and nil", repeatedUserID, err)
	}
	if _, err := store.ResolveSession(ctx, revokedDigest, time.Now().UTC()); !errors.Is(err, ErrUnauthenticated) {
		t.Fatalf("resolve revoked session error = %v; want ErrUnauthenticated", err)
	}

	disabledDigest := integrationSessionDigest("disabled-user-session")
	if _, err := store.CreateSession(ctx, winner.UserID, disabledDigest, time.Now().UTC().Add(time.Hour)); err != nil {
		t.Fatalf("create session for disabled-user test: %v", err)
	}
	if _, err := pool.Exec(ctx, `UPDATE identity.users SET status = 'disabled' WHERE id = $1::uuid`, winner.UserID); err != nil {
		t.Fatalf("disable bootstrap owner: %v", err)
	}
	if _, err := store.ResolveSession(ctx, disabledDigest, time.Now().UTC()); !errors.Is(err, ErrUnauthenticated) {
		t.Fatalf("resolve disabled-user session error = %v; want ErrUnauthenticated", err)
	}

	var bootstrapEvents int64
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM identity.auth_events WHERE event_type = 'owner_bootstrapped'`).Scan(&bootstrapEvents); err != nil {
		t.Fatalf("count bootstrap audit events: %v", err)
	}
	if bootstrapEvents != 1 {
		t.Fatalf("bootstrap audit event count = %d; want 1", bootstrapEvents)
	}
}

func integrationBootstrapRecord(email, slug string) BootstrapRecord {
	return BootstrapRecord{
		EmailNormalized:  email,
		DisplayName:      "Integration Owner",
		PasswordHash:     integrationPasswordHash,
		OrganizationName: "FlowlessHub Integration",
		OrganizationSlug: slug,
	}
}

func integrationSessionDigest(value string) []byte {
	digest := sha256.Sum256([]byte(value))
	return digest[:]
}

func assertIdentityDatabaseEmpty(t *testing.T, ctx context.Context, pool *pgxpool.Pool) {
	t.Helper()
	var users, organizations, memberships, sessions, events int64
	err := pool.QueryRow(ctx, `
        SELECT (SELECT count(*) FROM identity.users),
               (SELECT count(*) FROM tenant.organizations),
               (SELECT count(*) FROM tenant.memberships),
               (SELECT count(*) FROM identity.sessions),
               (SELECT count(*) FROM identity.auth_events)
    `).Scan(&users, &organizations, &memberships, &sessions, &events)
	if err != nil {
		t.Fatalf("verify empty identity integration database (apply migration 00002 first): %v", err)
	}
	if users+organizations+memberships+sessions+events != 0 {
		t.Fatalf("refusing non-empty integration database: users=%d organizations=%d memberships=%d sessions=%d events=%d", users, organizations, memberships, sessions, events)
	}
}
