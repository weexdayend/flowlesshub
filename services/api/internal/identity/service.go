package identity

import (
	"context"
	"crypto/rand"
	"errors"
	"log/slog"
	"time"
)

// Service coordinates credential verification, session lifecycle, and owner bootstrap.
type Service struct {
	store     Store
	hasher    *PasswordHasher
	dummyHash string
	logger    *slog.Logger
}

func NewService(store Store, hasher *PasswordHasher, logger *slog.Logger) (*Service, error) {
	if store == nil || hasher == nil {
		return nil, ErrInvalidInput
	}
	if logger == nil {
		logger = slog.Default()
	}
	dummyRandom := make([]byte, maximumPasswordBytes)
	if _, err := rand.Read(dummyRandom); err != nil {
		return nil, err
	}
	dummyPassword := make([]byte, maximumPasswordBytes)
	for index, value := range dummyRandom {
		dummyPassword[index] = 'a' + value%26
	}
	zeroBytes(dummyRandom)
	dummyHash, err := hasher.Hash(context.Background(), dummyPassword)
	zeroBytes(dummyPassword)
	if err != nil {
		return nil, err
	}
	return &Service{store: store, hasher: hasher, dummyHash: dummyHash, logger: logger}, nil
}

func (s *Service) Login(ctx context.Context, email string, password []byte) (string, Principal, error) {
	normalizedEmail, normalizeErr := NormalizeEmail(email)
	user, findErr := UserRecord{}, ErrNotFound
	if normalizeErr == nil {
		user, findErr = s.store.FindUserByEmail(ctx, normalizedEmail)
	}

	if findErr != nil && !errors.Is(findErr, ErrNotFound) {
		s.logger.Error("identity lookup failed", "error", findErr)
		return "", Principal{}, findErr
	}
	passwordHash := s.dummyHash
	if findErr == nil {
		passwordHash = user.PasswordHash
	}
	passwordMatches, verifyErr := s.hasher.Verify(ctx, passwordHash, password)
	if normalizeErr != nil || errors.Is(findErr, ErrNotFound) || verifyErr != nil || !passwordMatches || user.Status != "active" {
		var userID *string
		if findErr == nil {
			userID = &user.ID
		}
		if err := s.store.RecordAuthEvent(ctx, "login_failed", userID, nil); err != nil {
			s.logger.Error("identity failed-login audit event failed", "error", err)
		}
		return "", Principal{}, ErrInvalidCredentials
	}

	token, digest, err := newSessionToken()
	if err != nil {
		return "", Principal{}, err
	}
	expiresAt := time.Now().UTC().Add(sessionLifetime)
	defer zeroBytes(digest)
	sessionID, err := s.store.CreateSession(ctx, user.ID, digest, expiresAt)
	if err != nil {
		return "", Principal{}, err
	}
	if err := s.store.RecordAuthEvent(ctx, "login_succeeded", &user.ID, nil); err != nil {
		_, _ = s.store.RevokeSession(ctx, digest, time.Now().UTC())
		s.logger.Error("identity login audit event failed", "error", err)
		return "", Principal{}, err
	}
	return token, Principal{
		User:      user.User,
		SessionID: sessionID,
		ExpiresAt: expiresAt,
	}, nil
}

func (s *Service) Authenticate(ctx context.Context, token string) (Principal, error) {
	digest, err := digestSessionToken(token)
	if err != nil {
		return Principal{}, ErrUnauthenticated
	}
	defer zeroBytes(digest)
	return s.store.ResolveSession(ctx, digest, time.Now().UTC())
}

func (s *Service) Logout(ctx context.Context, token string) error {
	digest, err := digestSessionToken(token)
	if err != nil {
		return nil
	}
	defer zeroBytes(digest)
	userID, err := s.store.RevokeSession(ctx, digest, time.Now().UTC())
	if err != nil {
		return err
	}
	if userID != "" {
		if err := s.store.RecordAuthEvent(ctx, "logout", &userID, nil); err != nil {
			s.logger.Error("identity logout audit event failed", "error", err)
		}
	}
	return nil
}

func (s *Service) Organizations(ctx context.Context, userID string) ([]Organization, error) {
	return s.store.ListOrganizations(ctx, userID)
}

func (s *Service) BootstrapOwner(ctx context.Context, input BootstrapInput) (BootstrapResult, error) {
	email, err := NormalizeEmail(input.Email)
	if err != nil {
		return BootstrapResult{}, err
	}
	displayName, err := normalizeDisplayName(input.DisplayName)
	if err != nil {
		return BootstrapResult{}, err
	}
	organizationName, err := normalizeOrganizationName(input.OrganizationName)
	if err != nil {
		return BootstrapResult{}, err
	}
	slug, err := NormalizeOrganizationSlug(input.OrganizationSlug)
	if err != nil {
		return BootstrapResult{}, err
	}
	passwordHash, err := s.hasher.Hash(ctx, input.Password)
	if err != nil {
		return BootstrapResult{}, err
	}
	return s.store.BootstrapOwner(ctx, BootstrapRecord{
		EmailNormalized:  email,
		DisplayName:      displayName,
		PasswordHash:     passwordHash,
		OrganizationName: organizationName,
		OrganizationSlug: slug,
	})
}
