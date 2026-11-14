package config

import "testing"

func TestLoadAPIDefaultsToSecureProductionOrigin(t *testing.T) {
	t.Setenv("APP_ENV", "")
	t.Setenv("FLOWLESSHUB_WEB_ORIGIN", "")
	t.Setenv("FLOWLESSHUB_SESSION_COOKIE_SECURE", "")

	config, err := LoadAPI()
	if err != nil {
		t.Fatalf("LoadAPI() error = %v", err)
	}
	if config.WebOrigin != "https://app.flowlesshub.com" || !config.SessionCookieSecure {
		t.Fatalf("unexpected production defaults: %#v", config)
	}
}

func TestLoadAPIAllowsHTTPOnlyInDevelopment(t *testing.T) {
	t.Setenv("APP_ENV", "development")
	t.Setenv("FLOWLESSHUB_WEB_ORIGIN", "http://localhost:3000/")
	t.Setenv("FLOWLESSHUB_SESSION_COOKIE_SECURE", "false")

	config, err := LoadAPI()
	if err != nil {
		t.Fatalf("LoadAPI() error = %v", err)
	}
	if config.WebOrigin != "http://localhost:3000" || config.SessionCookieSecure {
		t.Fatalf("unexpected development configuration: %#v", config)
	}
}

func TestLoadAPIRejectsInsecureProductionCookieAndOrigin(t *testing.T) {
	t.Setenv("APP_ENV", "production")
	t.Setenv("FLOWLESSHUB_WEB_ORIGIN", "http://app.example.com")
	t.Setenv("FLOWLESSHUB_SESSION_COOKIE_SECURE", "false")
	if _, err := LoadAPI(); err == nil {
		t.Fatal("LoadAPI() accepted insecure production configuration")
	}
}

func TestLoadAPIRejectsOriginWithPathOrQuery(t *testing.T) {
	t.Setenv("APP_ENV", "development")
	t.Setenv("FLOWLESSHUB_SESSION_COOKIE_SECURE", "false")
	for _, origin := range []string{"http://localhost:3000/path", "http://localhost:3000?next=/", "https://user:pass@example.com"} {
		t.Setenv("FLOWLESSHUB_WEB_ORIGIN", origin)
		if _, err := LoadAPI(); err == nil {
			t.Errorf("LoadAPI() accepted invalid origin %q", origin)
		}
	}
}
