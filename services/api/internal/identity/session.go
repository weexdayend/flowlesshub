package identity

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"time"
)

const (
	sessionTokenBytes = 32
	sessionLifetime   = 12 * time.Hour
)

func newSessionToken() (string, []byte, error) {
	randomBytes := make([]byte, sessionTokenBytes)
	if _, err := rand.Read(randomBytes); err != nil {
		return "", nil, err
	}
	token := base64.RawURLEncoding.EncodeToString(randomBytes)
	zeroBytes(randomBytes)
	digest := sha256.Sum256([]byte(token))
	return token, digest[:], nil
}

func digestSessionToken(token string) ([]byte, error) {
	if len(token) != base64.RawURLEncoding.EncodedLen(sessionTokenBytes) {
		return nil, errors.New("invalid session token")
	}
	decoded, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil || len(decoded) != sessionTokenBytes || base64.RawURLEncoding.EncodeToString(decoded) != token {
		zeroBytes(decoded)
		return nil, errors.New("invalid session token")
	}
	zeroBytes(decoded)
	digest := sha256.Sum256([]byte(token))
	return digest[:], nil
}
