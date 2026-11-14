package config

import (
	"errors"
	"net/url"
	"os"
	"strings"
)

// Config contains process-level configuration shared by API and worker entry points.
type Config struct {
	HTTPAddr    string
	DatabaseURL string
}

// APIConfig contains browser security settings used only by the HTTP API.
type APIConfig struct {
	WebOrigin           string
	SessionCookieSecure bool
}

// Load reads configuration shared by API and worker processes.
func Load() (Config, error) {
	httpAddr := strings.TrimSpace(os.Getenv("HTTP_ADDR"))
	if httpAddr == "" {
		httpAddr = ":5050"
	}

	databaseURL := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if databaseURL == "" {
		return Config{}, errors.New("DATABASE_URL is required")
	}

	return Config{
		HTTPAddr:    httpAddr,
		DatabaseURL: databaseURL,
	}, nil
}

// LoadAPI reads and validates API-specific browser security configuration.
// Production defaults fail closed: HTTPS cookies are mandatory and an explicit
// web origin must be configured. HTTP cookies are permitted only in development.
func LoadAPI() (APIConfig, error) {
	environment := strings.ToLower(strings.TrimSpace(os.Getenv("APP_ENV")))
	if environment == "" {
		environment = "production"
	}
	if environment != "production" && environment != "development" {
		return APIConfig{}, errors.New("APP_ENV must be production or development")
	}

	webOrigin := strings.TrimSpace(os.Getenv("FLOWLESSHUB_WEB_ORIGIN"))
	if webOrigin == "" {
		if environment == "development" {
			webOrigin = "http://localhost:3000"
		} else {
			webOrigin = "https://app.flowlesshub.com"
		}
	}
	parsed, err := url.Parse(webOrigin)
	if err != nil || parsed == nil || parsed.Host == "" || parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" || (parsed.Path != "" && parsed.Path != "/") {
		return APIConfig{}, errors.New("FLOWLESSHUB_WEB_ORIGIN must be an absolute HTTP(S) origin without path, query, or credentials")
	}
	if parsed.Scheme != "https" && parsed.Scheme != "http" {
		return APIConfig{}, errors.New("FLOWLESSHUB_WEB_ORIGIN must use HTTP or HTTPS")
	}
	webOrigin = strings.ToLower(parsed.Scheme) + "://" + strings.ToLower(parsed.Host)
	if environment == "production" && parsed.Scheme != "https" {
		return APIConfig{}, errors.New("production FLOWLESSHUB_WEB_ORIGIN must use HTTPS")
	}

	secureCookie := environment == "production"
	if raw := strings.TrimSpace(os.Getenv("FLOWLESSHUB_SESSION_COOKIE_SECURE")); raw != "" {
		switch strings.ToLower(raw) {
		case "1", "true", "yes":
			secureCookie = true
		case "0", "false", "no":
			secureCookie = false
		default:
			return APIConfig{}, errors.New("FLOWLESSHUB_SESSION_COOKIE_SECURE must be true or false")
		}
	}
	if environment == "production" && !secureCookie {
		return APIConfig{}, errors.New("secure session cookies cannot be disabled outside development")
	}

	return APIConfig{WebOrigin: webOrigin, SessionCookieSecure: secureCookie}, nil
}
