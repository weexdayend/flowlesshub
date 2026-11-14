package identity

import "testing"

func TestSessionTokenIsOpaqueAndDigestOnly(t *testing.T) {
	token, digest, err := newSessionToken()
	if err != nil {
		t.Fatalf("newSessionToken() error = %v", err)
	}
	if len(token) != 43 {
		t.Fatalf("token length = %d; want 43", len(token))
	}
	if len(digest) != 32 {
		t.Fatalf("digest length = %d; want 32", len(digest))
	}
	resolved, err := digestSessionToken(token)
	if err != nil {
		t.Fatalf("digestSessionToken() error = %v", err)
	}
	if string(resolved) != string(digest) {
		t.Fatal("token digest was not stable")
	}
	if _, err := digestSessionToken("not-a-token"); err == nil {
		t.Fatal("digestSessionToken accepted malformed input")
	}
}
