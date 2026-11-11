package transportsecurity

import (
	"crypto/tls"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestTLS13NegotiatesX25519MLKEM768(t *testing.T) {
	const handshakePath = "/handshake"

	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	server.EnableHTTP2 = false
	server.TLS = &tls.Config{
		MinVersion:       tls.VersionTLS13,
		MaxVersion:       tls.VersionTLS13,
		CurvePreferences: []tls.CurveID{tls.X25519MLKEM768},
	}
	server.StartTLS()
	t.Cleanup(server.Close)

	client := server.Client()
	client.Timeout = 5 * time.Second

	transport, ok := client.Transport.(*http.Transport)
	if !ok {
		t.Fatalf("httptest client transport has type %T, want *http.Transport", client.Transport)
	}
	clientTLSConfig := transport.TLSClientConfig
	if clientTLSConfig == nil {
		clientTLSConfig = &tls.Config{}
	} else {
		clientTLSConfig = clientTLSConfig.Clone()
	}
	clientTLSConfig.MinVersion = tls.VersionTLS13
	clientTLSConfig.MaxVersion = tls.VersionTLS13
	clientTLSConfig.CurvePreferences = []tls.CurveID{tls.X25519MLKEM768}
	transport.TLSClientConfig = clientTLSConfig
	t.Cleanup(transport.CloseIdleConnections)

	response, err := client.Get(server.URL + handshakePath)
	if err != nil {
		t.Fatalf("perform TLS handshake: %v", err)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusNoContent {
		t.Fatalf("HTTP status = %d, want %d", response.StatusCode, http.StatusNoContent)
	}
	if response.TLS == nil {
		t.Fatal("response has no TLS connection state")
	}
	if response.TLS.Version != tls.VersionTLS13 {
		t.Fatalf("negotiated TLS version = 0x%04x, want TLS 1.3", response.TLS.Version)
	}
	if response.TLS.CurveID != tls.X25519MLKEM768 {
		t.Fatalf(
			"negotiated key exchange = %v (%d), want X25519MLKEM768 (%d)",
			response.TLS.CurveID,
			uint16(response.TLS.CurveID),
			uint16(tls.X25519MLKEM768),
		)
	}
}
