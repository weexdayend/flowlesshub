package identity

import (
	"context"
	"errors"
	"net/mail"
	"regexp"
	"strings"
	"time"
)

var (
	ErrNotFound           = errors.New("identity record not found")
	ErrInvalidCredentials = errors.New("invalid email or password")
	ErrUnauthenticated    = errors.New("authentication required")
	ErrBootstrapCompleted = errors.New("initial owner has already been provisioned")
	ErrInvalidInput       = errors.New("invalid identity input")
	ErrPasswordPolicy     = errors.New("password does not meet the password policy")
)

var organizationSlugPattern = regexp.MustCompile(`^[a-z0-9]+(?:-[a-z0-9]+)*$`)

type User struct {
	ID          string `json:"id"`
	Email       string `json:"email"`
	DisplayName string `json:"displayName"`
}

type UserRecord struct {
	User
	PasswordHash string
	Status       string
}

type Organization struct {
	ID          string `json:"id"`
	Slug        string `json:"slug"`
	DisplayName string `json:"displayName"`
	Role        string `json:"role"`
}

type Principal struct {
	User      User
	SessionID string
	ExpiresAt time.Time
}

type BootstrapInput struct {
	Email            string
	DisplayName      string
	OrganizationName string
	OrganizationSlug string
	Password         []byte
}

type BootstrapResult struct {
	UserID         string
	OrganizationID string
	MembershipID   string
}

type Store interface {
	FindUserByEmail(ctx context.Context, normalizedEmail string) (UserRecord, error)
	CreateSession(ctx context.Context, userID string, digest []byte, expiresAt time.Time) (string, error)
	ResolveSession(ctx context.Context, digest []byte, now time.Time) (Principal, error)
	RevokeSession(ctx context.Context, digest []byte, now time.Time) (string, error)
	ListOrganizations(ctx context.Context, userID string) ([]Organization, error)
	RecordAuthEvent(ctx context.Context, eventType string, userID, organizationID *string) error
	BootstrapOwner(ctx context.Context, input BootstrapRecord) (BootstrapResult, error)
}

type BootstrapRecord struct {
	EmailNormalized  string
	DisplayName      string
	PasswordHash     string
	OrganizationName string
	OrganizationSlug string
}

func NormalizeEmail(value string) (string, error) {
	normalized := strings.ToLower(strings.TrimSpace(value))
	if len(normalized) == 0 || len(normalized) > 254 {
		return "", ErrInvalidInput
	}
	parsed, err := mail.ParseAddress(normalized)
	if err != nil || parsed.Address != normalized || strings.ContainsAny(normalized, "\r\n\x00") {
		return "", ErrInvalidInput
	}
	return normalized, nil
}

func normalizeDisplayName(value string) (string, error) {
	name := strings.TrimSpace(value)
	if len(name) == 0 || len(name) > 120 || strings.ContainsAny(name, "\r\n\x00") {
		return "", ErrInvalidInput
	}
	return name, nil
}

func NormalizeOrganizationSlug(value string) (string, error) {
	slug := strings.ToLower(strings.TrimSpace(value))
	if len(slug) == 0 || len(slug) > 63 || !organizationSlugPattern.MatchString(slug) {
		return "", ErrInvalidInput
	}
	return slug, nil
}

func normalizeOrganizationName(value string) (string, error) {
	name := strings.TrimSpace(value)
	if len(name) < 2 || len(name) > 120 || strings.ContainsAny(name, "\r\n\x00") {
		return "", ErrInvalidInput
	}
	return name, nil
}
