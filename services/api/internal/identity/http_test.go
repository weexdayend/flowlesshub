package identity

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type fakeStore struct {
	user       UserRecord
	sessions   map[string]Principal
	orgs       []Organization
	revoked    map[string]bool
	events     []fakeAuthEvent
	resolveErr error
	nextID     int
}

type fakeAuthEvent struct {
	eventType string
	userID    string
}

func newFakeStore(user UserRecord) *fakeStore {
	return &fakeStore{user: user, sessions: make(map[string]Principal), revoked: make(map[string]bool), orgs: []Organization{{ID: "org-1", Slug: "acme", DisplayName: "Acme", Role: "owner"}}}
}

func (s *fakeStore) FindUserByEmail(_ context.Context, email string) (UserRecord, error) {
	if s.user.Email != email {
		return UserRecord{}, ErrNotFound
	}
	return s.user, nil
}

func (s *fakeStore) CreateSession(_ context.Context, userID string, digest []byte, expiresAt time.Time) (string, error) {
	s.nextID++
	id := fmt.Sprintf("session-%d", s.nextID)
	s.sessions[string(digest)] = Principal{User: s.user.User, SessionID: id, ExpiresAt: expiresAt}
	return id, nil
}

func (s *fakeStore) ResolveSession(_ context.Context, digest []byte, _ time.Time) (Principal, error) {
	if s.resolveErr != nil {
		return Principal{}, s.resolveErr
	}
	principal, ok := s.sessions[string(digest)]
	if !ok || s.revoked[string(digest)] {
		return Principal{}, ErrUnauthenticated
	}
	return principal, nil
}

func (s *fakeStore) RevokeSession(_ context.Context, digest []byte, _ time.Time) (string, error) {
	s.revoked[string(digest)] = true
	return s.user.ID, nil
}

func (s *fakeStore) ListOrganizations(_ context.Context, _ string) ([]Organization, error) {
	return s.orgs, nil
}

func (s *fakeStore) RecordAuthEvent(_ context.Context, eventType string, userID, _ *string) error {
	recorded := ""
	if userID != nil {
		recorded = *userID
	}
	s.events = append(s.events, fakeAuthEvent{eventType: eventType, userID: recorded})
	return nil
}

func (s *fakeStore) BootstrapOwner(_ context.Context, _ BootstrapRecord) (BootstrapResult, error) {
	return BootstrapResult{}, nil
}

func testHTTPHandler(t *testing.T) (*fakeStore, http.Handler) {
	t.Helper()
	hasher := testPasswordHasher()
	password := []byte("correct horse battery staple")
	passwordHash, err := hasher.Hash(context.Background(), password)
	if err != nil {
		t.Fatalf("hash test password: %v", err)
	}
	store := newFakeStore(UserRecord{
		User:         User{ID: "user-1", Email: "owner@example.com", DisplayName: "Owner"},
		PasswordHash: passwordHash,
		Status:       "active",
	})
	service, err := NewService(store, hasher, nil)
	if err != nil {
		t.Fatalf("NewService() error = %v", err)
	}
	return store, NewHTTPHandler(service, "http://localhost:3000", false)
}

func TestLoginSetsHostOnlyHttpOnlyLaxCookieAndMeReturnsSafeProfile(t *testing.T) {
	_, handler := testHTTPHandler(t)
	body := `{"email":"owner@example.com","password":"correct horse battery staple"}`
	request := httptest.NewRequest(http.MethodPost, "/v1/auth/login", strings.NewReader(body))
	request.Header.Set("Origin", "http://localhost:3000")
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("login status = %d, body = %s", response.Code, response.Body.String())
	}
	cookies := response.Result().Cookies()
	if len(cookies) != 1 {
		t.Fatalf("cookie count = %d; want 1", len(cookies))
	}
	cookie := cookies[0]
	if cookie.Name != sessionCookieName || !cookie.HttpOnly || cookie.Secure || cookie.Path != "/" || cookie.Domain != "" || cookie.SameSite != http.SameSiteLaxMode {
		t.Fatalf("unexpected development cookie attributes: %#v", cookie)
	}
	if strings.Contains(response.Body.String(), cookie.Value) {
		t.Fatal("session token appeared in response body")
	}

	meRequest := httptest.NewRequest(http.MethodGet, "/v1/auth/me", nil)
	meRequest.AddCookie(cookie)
	meRecorder := httptest.NewRecorder()
	handler.ServeHTTP(meRecorder, meRequest)
	if meRecorder.Code != http.StatusOK {
		t.Fatalf("me status = %d, body = %s", meRecorder.Code, meRecorder.Body.String())
	}
	var payload meResponse
	if err := json.Unmarshal(meRecorder.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode me response: %v", err)
	}
	if payload.User.Email != "owner@example.com" || len(payload.Organizations) != 1 || payload.Organizations[0].Role != "owner" {
		t.Fatalf("unexpected me payload: %#v", payload)
	}
}

func TestUnknownUserAndWrongPasswordReturnTheSameGenericResponse(t *testing.T) {
	_, handler := testHTTPHandler(t)
	cases := []string{
		`{"email":"owner@example.com","password":"incorrect horse battery staple"}`,
		`{"email":"unknown@example.com","password":"correct horse battery staple"}`,
	}
	var firstBody string
	for index, body := range cases {
		request := httptest.NewRequest(http.MethodPost, "/v1/auth/login", strings.NewReader(body))
		request.Header.Set("Origin", "http://localhost:3000")
		request.Header.Set("Content-Type", "application/json")
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		if response.Code != http.StatusUnauthorized {
			t.Fatalf("case %d status = %d; want 401; body=%s", index, response.Code, response.Body.String())
		}
		if index == 0 {
			firstBody = response.Body.String()
		} else if response.Body.String() != firstBody {
			t.Fatalf("unknown-user response %q differs from wrong-password response %q", response.Body.String(), firstBody)
		}
	}
}

func TestLoginRejectsUntrustedOrigin(t *testing.T) {
	_, handler := testHTTPHandler(t)
	request := httptest.NewRequest(http.MethodPost, "/v1/auth/login", strings.NewReader(`{"email":"owner@example.com","password":"correct horse battery staple"}`))
	request.Header.Set("Origin", "https://attacker.example")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d; want 403", response.Code)
	}
}

func TestLogoutRevokesSessionAndClearsCookie(t *testing.T) {
	store, handler := testHTTPHandler(t)
	login := httptest.NewRequest(http.MethodPost, "/v1/auth/login", strings.NewReader(`{"email":"owner@example.com","password":"correct horse battery staple"}`))
	login.Header.Set("Origin", "http://localhost:3000")
	login.Header.Set("Content-Type", "application/json")
	loginResponse := httptest.NewRecorder()
	handler.ServeHTTP(loginResponse, login)
	if loginResponse.Code != http.StatusNoContent {
		t.Fatalf("login status = %d, body = %s", loginResponse.Code, loginResponse.Body.String())
	}
	loginCookies := loginResponse.Result().Cookies()
	if len(loginCookies) != 1 {
		t.Fatalf("login cookie count = %d; want 1", len(loginCookies))
	}
	cookie := loginCookies[0]

	logout := httptest.NewRequest(http.MethodPost, "/v1/auth/logout", nil)
	logout.Header.Set("Origin", "http://localhost:3000")
	logout.AddCookie(cookie)
	logoutResponse := httptest.NewRecorder()
	handler.ServeHTTP(logoutResponse, logout)
	if logoutResponse.Code != http.StatusNoContent {
		t.Fatalf("logout status = %d, body = %s", logoutResponse.Code, logoutResponse.Body.String())
	}
	if len(logoutResponse.Result().Cookies()) != 1 || logoutResponse.Result().Cookies()[0].MaxAge != -1 {
		t.Fatal("logout did not expire the session cookie")
	}
	for digest := range store.sessions {
		if !store.revoked[digest] {
			t.Fatal("logout did not revoke the session")
		}
	}
	if len(store.events) < 2 {
		t.Fatalf("auth event count = %d; want login and logout events", len(store.events))
	}
	lastEvent := store.events[len(store.events)-1]
	if lastEvent.eventType != "logout" || lastEvent.userID != "user-1" {
		t.Fatalf("logout event = %#v; want user-scoped logout", lastEvent)
	}
}

func TestLoginRequiresJSONContentType(t *testing.T) {
	_, handler := testHTTPHandler(t)
	request := httptest.NewRequest(http.MethodPost, "/v1/auth/login", strings.NewReader(`{"email":"owner@example.com","password":"correct horse battery staple"}`))
	request.Header.Set("Origin", "http://localhost:3000")
	request.Header.Set("Content-Type", "text/plain")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusUnsupportedMediaType {
		t.Fatalf("status = %d; want 415", response.Code)
	}
}

func TestCORSPreflightValidatesRequestedMethodAndHeaders(t *testing.T) {
	_, handler := testHTTPHandler(t)

	valid := httptest.NewRequest(http.MethodOptions, "/v1/auth/login", nil)
	valid.Header.Set("Origin", "http://localhost:3000")
	valid.Header.Set("Access-Control-Request-Method", "POST")
	valid.Header.Set("Access-Control-Request-Headers", "content-type")
	validResponse := httptest.NewRecorder()
	handler.ServeHTTP(validResponse, valid)
	if validResponse.Code != http.StatusNoContent {
		t.Fatalf("valid preflight status = %d; body = %s", validResponse.Code, validResponse.Body.String())
	}
	if validResponse.Header().Get("Access-Control-Allow-Origin") != "http://localhost:3000" {
		t.Fatal("valid preflight omitted the configured origin")
	}

	badMethod := httptest.NewRequest(http.MethodOptions, "/v1/auth/login", nil)
	badMethod.Header.Set("Origin", "http://localhost:3000")
	badMethod.Header.Set("Access-Control-Request-Method", "DELETE")
	badMethodResponse := httptest.NewRecorder()
	handler.ServeHTTP(badMethodResponse, badMethod)
	if badMethodResponse.Code != http.StatusForbidden {
		t.Fatalf("unsupported method preflight status = %d; want 403", badMethodResponse.Code)
	}

	badHeader := httptest.NewRequest(http.MethodOptions, "/v1/auth/login", nil)
	badHeader.Header.Set("Origin", "http://localhost:3000")
	badHeader.Header.Set("Access-Control-Request-Method", "POST")
	badHeader.Header.Set("Access-Control-Request-Headers", "content-type, x-unknown")
	badHeaderResponse := httptest.NewRecorder()
	handler.ServeHTTP(badHeaderResponse, badHeader)
	if badHeaderResponse.Code != http.StatusForbidden {
		t.Fatalf("unsupported header preflight status = %d; want 403", badHeaderResponse.Code)
	}
}

func TestAuthenticatedDatabaseFailureIsNotReportedAsUnauthorized(t *testing.T) {
	store, handler := testHTTPHandler(t)
	login := httptest.NewRequest(http.MethodPost, "/v1/auth/login", strings.NewReader(`{"email":"owner@example.com","password":"correct horse battery staple"}`))
	login.Header.Set("Origin", "http://localhost:3000")
	login.Header.Set("Content-Type", "application/json")
	loginResponse := httptest.NewRecorder()
	handler.ServeHTTP(loginResponse, login)
	if loginResponse.Code != http.StatusNoContent {
		t.Fatalf("login status = %d; body = %s", loginResponse.Code, loginResponse.Body.String())
	}
	cookie := loginResponse.Result().Cookies()[0]

	store.resolveErr = fmt.Errorf("database unavailable")
	request := httptest.NewRequest(http.MethodGet, "/v1/auth/me", nil)
	request.AddCookie(cookie)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d; want 500", response.Code)
	}
}

func TestLoginRejectsAnUntrustedOriginEvenWithAValidJSONBody(t *testing.T) {
	_, handler := testHTTPHandler(t)
	request := httptest.NewRequest(http.MethodPost, "/v1/auth/login", strings.NewReader(`{"email":"owner@example.com","password":"correct horse battery staple"}`))
	request.Header.Set("Origin", "https://attacker.example")
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d; want 403", response.Code)
	}
}

func TestSecureCookieUsesHostPrefixAndSecureAttribute(t *testing.T) {
	hasher := testPasswordHasher()
	passwordHash, err := hasher.Hash(context.Background(), []byte("correct horse battery staple"))
	if err != nil {
		t.Fatalf("hash test password: %v", err)
	}
	store := newFakeStore(UserRecord{
		User:         User{ID: "user-1", Email: "owner@example.com", DisplayName: "Owner"},
		PasswordHash: passwordHash,
		Status:       "active",
	})
	service, err := NewService(store, hasher, nil)
	if err != nil {
		t.Fatalf("NewService() error = %v", err)
	}
	handler := NewHTTPHandler(service, "https://app.example.com", true)
	request := httptest.NewRequest(http.MethodPost, "/v1/auth/login", strings.NewReader(`{"email":"owner@example.com","password":"correct horse battery staple"}`))
	request.Header.Set("Origin", "https://app.example.com")
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusNoContent {
		t.Fatalf("login status = %d; body = %s", response.Code, response.Body.String())
	}
	cookies := response.Result().Cookies()
	if len(cookies) != 1 {
		t.Fatalf("cookie count = %d; want 1", len(cookies))
	}
	cookie := cookies[0]
	if cookie.Name != secureSessionCookieName || !cookie.Secure || !cookie.HttpOnly || cookie.Path != "/" || cookie.Domain != "" {
		t.Fatalf("unexpected production cookie attributes: %#v", cookie)
	}
}

func TestNormalizeOriginCanonicalizesDefaultPorts(t *testing.T) {
	for input, expected := range map[string]string{
		"https://APP.EXAMPLE.COM:443": "https://app.example.com",
		"http://localhost:80":         "http://localhost",
		"http://localhost:3000/":      "http://localhost:3000",
	} {
		actual, err := normalizeOrigin(input)
		if err != nil {
			t.Fatalf("normalizeOrigin(%q) error = %v", input, err)
		}
		if actual != expected {
			t.Errorf("normalizeOrigin(%q) = %q; want %q", input, actual, expected)
		}
	}
}

func TestLoginRateLimiterIsBounded(t *testing.T) {
	limiter := NewLoginRateLimiter(2, time.Minute, 1)
	now := time.Now()
	if !limiter.Allow("127.0.0.1", now) || !limiter.Allow("127.0.0.1", now) {
		t.Fatal("first two attempts should be allowed")
	}
	if limiter.Allow("127.0.0.1", now) {
		t.Fatal("third attempt should be rejected")
	}
	if limiter.Allow("192.0.2.1", now) {
		t.Fatal("new key should fail closed when the bounded map is full")
	}
}
