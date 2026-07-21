package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestRequestID_GeneratesID(t *testing.T) {
	router := gin.New()
	router.Use(RequestID())
	router.GET("/test", func(c *gin.Context) {
		id, exists := c.Get(RequestIDKey)
		if !exists {
			t.Error("request_id not set in context")
		}
		if id.(string) == "" {
			t.Error("request_id should not be empty")
		}
		c.String(http.StatusOK, "ok")
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	router.ServeHTTP(w, req)

	// Response should have X-Request-ID header
	rid := w.Header().Get("X-Request-ID")
	if rid == "" {
		t.Error("expected X-Request-ID in response headers")
	}
	if len(rid) < 32 {
		t.Errorf("request ID seems too short: %s", rid)
	}
}

func TestRequestID_PropagatesExisting(t *testing.T) {
	router := gin.New()
	router.Use(RequestID())
	router.GET("/test", func(c *gin.Context) {
		id, _ := c.Get(RequestIDKey)
		if id.(string) != "custom-request-id-123" {
			t.Errorf("expected custom ID, got %s", id)
		}
		c.String(http.StatusOK, "ok")
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	req.Header.Set("X-Request-ID", "custom-request-id-123")
	router.ServeHTTP(w, req)

	rid := w.Header().Get("X-Request-ID")
	if rid != "custom-request-id-123" {
		t.Errorf("expected propagated ID, got %s", rid)
	}
}

func TestRequestID_UniquePerRequest(t *testing.T) {
	router := gin.New()
	router.Use(RequestID())
	router.GET("/test", func(c *gin.Context) {
		c.String(http.StatusOK, "ok")
	})

	ids := make(map[string]bool)
	for i := 0; i < 10; i++ {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/test", nil)
		router.ServeHTTP(w, req)

		rid := w.Header().Get("X-Request-ID")
		if ids[rid] {
			t.Fatalf("duplicate request ID: %s", rid)
		}
		ids[rid] = true
	}
}
