package identity

import "testing"

func TestNormalizeEmail(t *testing.T) {
	got, err := NormalizeEmail("  Owner@Example.COM ")
	if err != nil {
		t.Fatalf("NormalizeEmail() error = %v", err)
	}
	if got != "owner@example.com" {
		t.Fatalf("NormalizeEmail() = %q", got)
	}
	if _, err := NormalizeEmail("Owner <owner@example.com>"); err == nil {
		t.Fatal("NormalizeEmail accepted a display name")
	}
}

func TestNormalizeOrganizationSlug(t *testing.T) {
	got, err := NormalizeOrganizationSlug("  My-Org-01 ")
	if err != nil {
		t.Fatalf("NormalizeOrganizationSlug() error = %v", err)
	}
	if got != "my-org-01" {
		t.Fatalf("NormalizeOrganizationSlug() = %q", got)
	}
	for _, value := range []string{"-bad", "bad-", "bad--slug", "spaces are bad", ".."} {
		if _, err := NormalizeOrganizationSlug(value); err == nil {
			t.Errorf("NormalizeOrganizationSlug(%q) succeeded", value)
		}
	}
}
