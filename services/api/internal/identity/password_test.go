package identity

import (
	"context"
	"strings"
	"testing"
)

func testPasswordHasher() *PasswordHasher {
	return NewPasswordHasher(Argon2Parameters{MemoryKiB: 8 * 1024, Iterations: 1, Parallelism: 1})
}

func TestPasswordHashAndVerify(t *testing.T) {
	hasher := testPasswordHasher()
	password := []byte("correct horse battery staple")
	encoded, err := hasher.Hash(context.Background(), password)
	if err != nil {
		t.Fatalf("Hash() error = %v", err)
	}
	if !strings.HasPrefix(encoded, passwordHashPrefix) {
		t.Fatalf("Hash() format = %q", encoded)
	}

	valid, err := hasher.Verify(context.Background(), encoded, password)
	if err != nil || !valid {
		t.Fatalf("Verify(correct) = %v, %v; want true, nil", valid, err)
	}
	valid, err = hasher.Verify(context.Background(), encoded, []byte("incorrect horse battery staple"))
	if err != nil || valid {
		t.Fatalf("Verify(incorrect) = %v, %v; want false, nil", valid, err)
	}
}

func TestPasswordPolicyAndMalformedHash(t *testing.T) {
	hasher := testPasswordHasher()
	if _, err := hasher.Hash(context.Background(), []byte("short")); err != ErrPasswordPolicy {
		t.Fatalf("Hash(short) error = %v; want ErrPasswordPolicy", err)
	}
	if _, err := hasher.Verify(context.Background(), "not-a-hash", []byte("correct horse battery staple")); err == nil {
		t.Fatal("Verify(malformed) succeeded")
	}
}

func TestPasswordHashParserRejectsDuplicateAndOversizedParameters(t *testing.T) {
	for _, encoded := range []string{
		"fh1$argon2id$v=19$m=8192,m=8192,t=1,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
		"fh1$argon2id$v=19$m=65536,t=3,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
		"fh1$argon2id$v=19$m=32768,t=3,p=2$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
	} {
		if _, _, _, err := parsePasswordHash(encoded); err == nil {
			t.Errorf("parsePasswordHash(%q) succeeded; want safe rejection", encoded)
		}
	}
}

func TestPasswordHasherCapsConcurrentArgonWorkAtOne(t *testing.T) {
	hasher := NewPasswordHasher(Argon2Parameters{MemoryKiB: 8 * 1024, Iterations: 1, Parallelism: 1})
	if cap(hasher.semaphore) != 1 {
		t.Fatalf("Argon2 concurrency cap = %d; want 1", cap(hasher.semaphore))
	}
}

func TestPasswordHasherHonorsCanceledContextWhenBusy(t *testing.T) {
	hasher := NewPasswordHasher(Argon2Parameters{MemoryKiB: 8 * 1024, Iterations: 1, Parallelism: 1})
	hasher.semaphore <- struct{}{}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := hasher.Hash(ctx, []byte("correct horse battery staple")); err == nil {
		t.Fatal("Hash() succeeded with canceled context while semaphore was full")
	}
}
