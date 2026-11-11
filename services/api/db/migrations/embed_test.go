package migrations

import "testing"

func TestEmbeddedMigrationFiles(t *testing.T) {
	entries, err := FS.ReadDir(".")
	if err != nil {
		t.Fatalf("read embedded migrations: %v", err)
	}

	foundPlatformMigration := false
	for _, entry := range entries {
		if entry.Name() == "00001_platform_schema.sql" && !entry.IsDir() {
			foundPlatformMigration = true
			break
		}
	}
	if !foundPlatformMigration {
		t.Fatal("embedded migrations do not contain 00001_platform_schema.sql")
	}
}
