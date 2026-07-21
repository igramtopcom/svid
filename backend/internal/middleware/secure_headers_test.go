package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func init() {
	gin.SetMode(gin.TestMode)
}

func TestSecureHeaders(t *testing.T) {
	router := gin.New()
	router.Use(SecureHeaders())
	router.GET("/test", func(c *gin.Context) {
		c.String(http.StatusOK, "ok")
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	expected := map[string]string{
		"X-Frame-Options":           "DENY",
		"X-Content-Type-Options":    "nosniff",
		"X-Xss-Protection":         "1; mode=block",
		"Referrer-Policy":           "strict-origin-when-cross-origin",
		"Permissions-Policy":        "geolocation=(), microphone=(), camera=()",
		"Strict-Transport-Security": "max-age=31536000; includeSubDomains",
		"Content-Security-Policy":   "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:",
		"Cache-Control":             "no-store",
	}

	for header, want := range expected {
		got := w.Header().Get(header)
		if got != want {
			t.Errorf("header %s: want %q, got %q", header, want, got)
		}
	}
}

func TestSecureHeaders_PassesThrough(t *testing.T) {
	router := gin.New()
	router.Use(SecureHeaders())
	router.POST("/data", func(c *gin.Context) {
		c.JSON(http.StatusCreated, gin.H{"id": 1})
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/data", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d", w.Code)
	}

	// Headers should still be present on non-GET requests
	if w.Header().Get("X-Frame-Options") != "DENY" {
		t.Error("X-Frame-Options missing on POST")
	}
}
