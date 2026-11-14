package identity

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

const (
	sessionCookieName       = "flowlesshub_session"
	secureSessionCookieName = "__Host-flowlesshub_session"
	loginRateLimitAttempts  = 30
	loginRateLimitWindow    = 15 * time.Minute
	loginRateLimitMaxKeys   = 10_000
	maximumLoginBodyBytes   = 8 * 1024
)

type contextKey uint8

const principalContextKey contextKey = 1

type HTTPHandler struct {
	service      *Service
	webOrigin    string
	secureCookie bool
	cookieName   string
	loginLimiter *LoginRateLimiter
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type errorResponse struct {
	Error string `json:"error"`
}

type meResponse struct {
	User          User           `json:"user"`
	Session       sessionSummary `json:"session"`
	Organizations []Organization `json:"organizations"`
}

type sessionSummary struct {
	ExpiresAt time.Time `json:"expiresAt"`
}

func NewHTTPHandler(service *Service, webOrigin string, secureCookie bool) http.Handler {
	normalizedOrigin, err := normalizeOrigin(webOrigin)
	if err != nil {
		panic("invalid configured web origin: " + err.Error())
	}
	cookieName := sessionCookieName
	if secureCookie {
		cookieName = secureSessionCookieName
	}
	handler := &HTTPHandler{
		service:      service,
		webOrigin:    normalizedOrigin,
		secureCookie: secureCookie,
		cookieName:   cookieName,
		loginLimiter: NewLoginRateLimiter(loginRateLimitAttempts, loginRateLimitWindow, loginRateLimitMaxKeys),
	}
	router := chi.NewRouter()
	router.Use(handler.cors)
	router.Options("/*", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) })
	router.Post("/v1/auth/login", handler.login)
	router.Post("/v1/auth/logout", handler.logout)
	router.With(handler.requireSession).Get("/v1/auth/me", handler.me)
	router.With(handler.requireSession).Get("/v1/organizations", handler.organizations)
	return router
}

func (h *HTTPHandler) login(w http.ResponseWriter, r *http.Request) {
	if !h.originAllowed(r) {
		writeError(w, http.StatusForbidden, "origin_not_allowed")
		return
	}
	clientIP := middleware.GetClientIP(r.Context())
	if clientIP == "" {
		clientIP = remoteAddress(r.RemoteAddr)
	}
	if !h.loginLimiter.Allow(clientIP, time.Now()) {
		writeError(w, http.StatusTooManyRequests, "too_many_attempts")
		return
	}

	mediaType, _, mediaTypeErr := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if mediaTypeErr != nil || mediaType != "application/json" {
		writeError(w, http.StatusUnsupportedMediaType, "content_type_must_be_json")
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maximumLoginBodyBytes)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var request loginRequest
	if err := decoder.Decode(&request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request")
		return
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		writeError(w, http.StatusBadRequest, "invalid_request")
		return
	}
	if strings.TrimSpace(request.Email) == "" || request.Password == "" {
		writeError(w, http.StatusBadRequest, "invalid_request")
		return
	}

	password := []byte(request.Password)
	request.Password = ""
	defer zeroBytes(password)
	token, principal, err := h.service.Login(r.Context(), request.Email, password)
	if err != nil {
		if errors.Is(err, ErrInvalidCredentials) || errors.Is(err, ErrPasswordPolicy) {
			writeError(w, http.StatusUnauthorized, "invalid_credentials")
			return
		}
		writeError(w, http.StatusInternalServerError, "authentication_failed")
		return
	}
	h.setSessionCookie(w, token, principal.ExpiresAt)
	w.WriteHeader(http.StatusNoContent)
}

func (h *HTTPHandler) logout(w http.ResponseWriter, r *http.Request) {
	if !h.originAllowed(r) {
		writeError(w, http.StatusForbidden, "origin_not_allowed")
		return
	}
	if cookie, err := r.Cookie(h.cookieName); err == nil {
		if err := h.service.Logout(r.Context(), cookie.Value); err != nil {
			writeError(w, http.StatusInternalServerError, "logout_failed")
			return
		}
	}
	h.clearSessionCookie(w)
	w.WriteHeader(http.StatusNoContent)
}

func (h *HTTPHandler) me(w http.ResponseWriter, r *http.Request) {
	principal, ok := principalFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "authentication_required")
		return
	}
	organizations, err := h.service.Organizations(r.Context(), principal.User.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "request_failed")
		return
	}
	writeJSON(w, http.StatusOK, meResponse{
		User:          principal.User,
		Session:       sessionSummary{ExpiresAt: principal.ExpiresAt},
		Organizations: organizations,
	})
}

func (h *HTTPHandler) organizations(w http.ResponseWriter, r *http.Request) {
	principal, ok := principalFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "authentication_required")
		return
	}
	organizations, err := h.service.Organizations(r.Context(), principal.User.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "request_failed")
		return
	}
	writeJSON(w, http.StatusOK, struct {
		Data []Organization `json:"data"`
	}{Data: organizations})
}

func (h *HTTPHandler) requireSession(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cookie, err := r.Cookie(h.cookieName)
		if err != nil || cookie.Value == "" {
			writeError(w, http.StatusUnauthorized, "authentication_required")
			return
		}
		principal, err := h.service.Authenticate(r.Context(), cookie.Value)
		if errors.Is(err, ErrUnauthenticated) {
			writeError(w, http.StatusUnauthorized, "authentication_required")
			return
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "authentication_unavailable")
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), principalContextKey, principal)))
	})
}

func (h *HTTPHandler) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Add("Vary", "Origin")
		origin := strings.TrimSpace(r.Header.Get("Origin"))
		if r.Method == http.MethodOptions {
			if !h.originAllowed(r) {
				writeError(w, http.StatusForbidden, "origin_not_allowed")
				return
			}
			requestedMethod := strings.ToUpper(strings.TrimSpace(r.Header.Get("Access-Control-Request-Method")))
			if requestedMethod != http.MethodGet && requestedMethod != http.MethodPost {
				writeError(w, http.StatusForbidden, "preflight_method_not_allowed")
				return
			}
			if !allowedPreflightHeaders(r.Header.Get("Access-Control-Request-Headers")) {
				writeError(w, http.StatusForbidden, "preflight_header_not_allowed")
				return
			}
			w.Header().Add("Vary", "Access-Control-Request-Method")
			w.Header().Add("Vary", "Access-Control-Request-Headers")
			w.Header().Set("Access-Control-Allow-Origin", h.webOrigin)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
			w.WriteHeader(http.StatusNoContent)
			return
		}
		if origin != "" {
			if !h.originAllowed(r) {
				writeError(w, http.StatusForbidden, "origin_not_allowed")
				return
			}
			w.Header().Set("Access-Control-Allow-Origin", h.webOrigin)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
		}
		next.ServeHTTP(w, r)
	})
}

func allowedPreflightHeaders(raw string) bool {
	for _, item := range strings.Split(raw, ",") {
		header := strings.TrimSpace(item)
		if header == "" {
			continue
		}
		if !strings.EqualFold(header, "content-type") {
			return false
		}
	}
	return true
}

func (h *HTTPHandler) originAllowed(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		return false
	}
	normalized, err := normalizeOrigin(origin)
	return err == nil && normalized == h.webOrigin
}

func (h *HTTPHandler) setSessionCookie(w http.ResponseWriter, token string, expiresAt time.Time) {
	http.SetCookie(w, &http.Cookie{
		Name:     h.cookieName,
		Value:    token,
		Path:     "/",
		Expires:  expiresAt.UTC(),
		MaxAge:   int(time.Until(expiresAt).Seconds()),
		HttpOnly: true,
		Secure:   h.secureCookie,
		SameSite: http.SameSiteLaxMode,
	})
}

func (h *HTTPHandler) clearSessionCookie(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name:     h.cookieName,
		Value:    "",
		Path:     "/",
		Expires:  time.Unix(1, 0).UTC(),
		MaxAge:   -1,
		HttpOnly: true,
		Secure:   h.secureCookie,
		SameSite: http.SameSiteLaxMode,
	})
}

func principalFromContext(ctx context.Context) (Principal, bool) {
	principal, ok := ctx.Value(principalContextKey).(Principal)
	return principal, ok
}

func normalizeOrigin(raw string) (string, error) {
	parsed, err := url.Parse(raw)
	if err != nil || parsed == nil || parsed.Host == "" || parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" || (parsed.Path != "" && parsed.Path != "/") {
		return "", errors.New("origin must contain only scheme and host")
	}
	if parsed.Scheme != "https" && parsed.Scheme != "http" {
		return "", errors.New("origin scheme must be HTTP or HTTPS")
	}
	scheme := strings.ToLower(parsed.Scheme)
	host := strings.ToLower(parsed.Host)
	if (scheme == "https" && strings.HasSuffix(host, ":443")) || (scheme == "http" && strings.HasSuffix(host, ":80")) {
		host = host[:strings.LastIndex(host, ":")]
	}
	return scheme + "://" + host, nil
}

func remoteAddress(value string) string {
	host, _, err := net.SplitHostPort(value)
	if err == nil && host != "" {
		return host
	}
	return value
}

func writeError(w http.ResponseWriter, status int, code string) {
	writeJSON(w, status, errorResponse{Error: code})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

// LoginRateLimiter is a bounded, process-local fixed-window limiter. It is a
// first-line abuse control, not a distributed rate-limit substitute.
type LoginRateLimiter struct {
	mu         sync.Mutex
	attempts   int
	window     time.Duration
	maximumKey int
	entries    map[string]rateWindow
}

type rateWindow struct {
	startedAt time.Time
	count     int
}

func NewLoginRateLimiter(attempts int, window time.Duration, maximumKeys int) *LoginRateLimiter {
	if attempts < 1 {
		attempts = loginRateLimitAttempts
	}
	if window <= 0 {
		window = loginRateLimitWindow
	}
	if maximumKeys < 1 {
		maximumKeys = loginRateLimitMaxKeys
	}
	return &LoginRateLimiter{
		attempts:   attempts,
		window:     window,
		maximumKey: maximumKeys,
		entries:    make(map[string]rateWindow),
	}
}

func (l *LoginRateLimiter) Allow(key string, now time.Time) bool {
	if key == "" {
		return false
	}
	l.mu.Lock()
	defer l.mu.Unlock()

	entry, exists := l.entries[key]
	if exists && now.Sub(entry.startedAt) < l.window {
		if entry.count >= l.attempts {
			return false
		}
		entry.count++
		l.entries[key] = entry
		return true
	}
	if exists {
		l.entries[key] = rateWindow{startedAt: now, count: 1}
		return true
	}
	if len(l.entries) >= l.maximumKey {
		for candidate, value := range l.entries {
			if now.Sub(value.startedAt) >= l.window {
				delete(l.entries, candidate)
			}
		}
		if len(l.entries) >= l.maximumKey {
			return false
		}
	}
	l.entries[key] = rateWindow{startedAt: now, count: 1}
	return true
}
