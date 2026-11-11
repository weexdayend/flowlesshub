package cryptokit

import (
	"errors"
	"strings"
)

const (
	// AlgorithmAES256GCM identifies the first supported envelope data-encryption algorithm.
	AlgorithmAES256GCM   = "AES-256-GCM"
	CurrentHeaderVersion = 1
)

// Header is the versioned metadata stored alongside an encrypted payload.
// This type deliberately does not perform cryptographic operations.
type Header struct {
	Algorithm string `json:"alg"`
	KeyID     string `json:"kid"`
	Version   int    `json:"version"`
}

// Validate rejects incomplete or unsupported envelope metadata.
func (h Header) Validate() error {
	if h.Version != CurrentHeaderVersion {
		return errors.New("unsupported cryptokit header version")
	}
	if h.Algorithm != AlgorithmAES256GCM {
		return errors.New("unsupported cryptokit algorithm")
	}
	if strings.TrimSpace(h.KeyID) == "" {
		return errors.New("cryptokit key id is required")
	}
	return nil
}
