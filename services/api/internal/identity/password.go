package identity

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"unicode/utf8"

	"golang.org/x/crypto/argon2"
)

const (
	passwordHashPrefix   = "fh1$argon2id$v=19$"
	minimumPasswordBytes = 12
	maximumPasswordBytes = 128
)

// Argon2Parameters are deliberately small enough for the current 96 MiB API
// container. The single-operation semaphore bounds concurrent memory use.
type Argon2Parameters struct {
	MemoryKiB   uint32
	Iterations  uint32
	Parallelism uint8
}

// PasswordHasher bounds Argon2 memory concurrency for this process.
type PasswordHasher struct {
	parameters Argon2Parameters
	semaphore  chan struct{}
}

func NewDefaultPasswordHasher() *PasswordHasher {
	return NewPasswordHasher(Argon2Parameters{MemoryKiB: 32 * 1024, Iterations: 3, Parallelism: 1})
}

func NewPasswordHasher(parameters Argon2Parameters) *PasswordHasher {
	// The current API container is limited to 96 MiB. Keep Argon2 concurrency
	// at one to reserve headroom for the Go runtime and PostgreSQL client.
	if parameters.MemoryKiB < 8*1024 || parameters.MemoryKiB > 32*1024 {
		parameters.MemoryKiB = 32 * 1024
	}
	if parameters.Iterations < 1 || parameters.Iterations > 3 {
		parameters.Iterations = 3
	}
	if parameters.Parallelism != 1 {
		parameters.Parallelism = 1
	}
	return &PasswordHasher{parameters: parameters, semaphore: make(chan struct{}, 1)}
}

func (h *PasswordHasher) Hash(ctx context.Context, password []byte) (string, error) {
	if err := validatePassword(password); err != nil {
		return "", err
	}
	if err := h.acquire(ctx); err != nil {
		return "", err
	}
	defer h.release()

	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("generate password salt: %w", err)
	}
	key := argon2.IDKey(password, salt, h.parameters.Iterations, h.parameters.MemoryKiB, h.parameters.Parallelism, 32)
	encoded := fmt.Sprintf("%sm=%d,t=%d,p=%d$%s$%s",
		passwordHashPrefix,
		h.parameters.MemoryKiB,
		h.parameters.Iterations,
		h.parameters.Parallelism,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(key),
	)
	zeroBytes(salt)
	zeroBytes(key)
	return encoded, nil
}

func (h *PasswordHasher) Verify(ctx context.Context, encoded string, password []byte) (bool, error) {
	if len(password) < minimumPasswordBytes || len(password) > maximumPasswordBytes || !utf8.Valid(password) {
		return false, ErrPasswordPolicy
	}
	parameters, salt, expected, err := parsePasswordHash(encoded)
	if err != nil {
		return false, err
	}
	defer zeroBytes(salt)
	defer zeroBytes(expected)
	if err := h.acquire(ctx); err != nil {
		return false, err
	}
	defer h.release()
	actual := argon2.IDKey(password, salt, parameters.Iterations, parameters.MemoryKiB, parameters.Parallelism, uint32(len(expected)))
	defer zeroBytes(actual)
	return subtle.ConstantTimeCompare(actual, expected) == 1, nil
}

func validatePassword(password []byte) error {
	if len(password) < minimumPasswordBytes || len(password) > maximumPasswordBytes || !utf8.Valid(password) {
		return ErrPasswordPolicy
	}
	return nil
}

func (h *PasswordHasher) acquire(ctx context.Context) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	select {
	case h.semaphore <- struct{}{}:
		if err := ctx.Err(); err != nil {
			<-h.semaphore
			return err
		}
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (h *PasswordHasher) release() { <-h.semaphore }

func parsePasswordHash(encoded string) (Argon2Parameters, []byte, []byte, error) {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[0] != "fh1" || parts[1] != "argon2id" || parts[2] != "v=19" {
		return Argon2Parameters{}, nil, nil, errors.New("unsupported password hash format")
	}
	var parameters Argon2Parameters
	seen := make(map[string]bool, 3)
	for _, item := range strings.Split(parts[3], ",") {
		keyValue := strings.SplitN(item, "=", 2)
		if len(keyValue) != 2 || seen[keyValue[0]] {
			return Argon2Parameters{}, nil, nil, errors.New("malformed password hash parameters")
		}
		seen[keyValue[0]] = true
		value, err := strconv.ParseUint(keyValue[1], 10, 32)
		if err != nil {
			return Argon2Parameters{}, nil, nil, errors.New("malformed password hash parameters")
		}
		switch keyValue[0] {
		case "m":
			parameters.MemoryKiB = uint32(value)
		case "t":
			parameters.Iterations = uint32(value)
		case "p":
			if value > 255 {
				return Argon2Parameters{}, nil, nil, errors.New("invalid password hash parallelism")
			}
			parameters.Parallelism = uint8(value)
		default:
			return Argon2Parameters{}, nil, nil, errors.New("unknown password hash parameter")
		}
	}
	if len(seen) != 3 || parameters.MemoryKiB < 8*1024 || parameters.MemoryKiB > 32*1024 || parameters.Iterations < 1 || parameters.Iterations > 3 || parameters.Parallelism != 1 {
		return Argon2Parameters{}, nil, nil, errors.New("password hash parameters exceed safe bounds")
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil || len(salt) != 16 {
		zeroBytes(salt)
		return Argon2Parameters{}, nil, nil, errors.New("invalid password hash salt")
	}
	expected, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil || len(expected) != 32 {
		zeroBytes(salt)
		return Argon2Parameters{}, nil, nil, errors.New("invalid password hash digest")
	}
	return parameters, salt, expected, nil
}

func zeroBytes(value []byte) {
	for index := range value {
		value[index] = 0
	}
}
