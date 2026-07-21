package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func TestRequestTimeout_SetsContextDeadline(t *testing.T) {
	router := gin.New()
	timeout := 5 * time.Second
	router.Use(RequestTimeout(timeout))

	var hasDeadline bool
	var deadline time.Time

	router.GET("/test", func(c *gin.Context) {
		dl, ok := c.Request.Context().Deadline()
		hasDeadline = ok
		deadline = dl
		c.String(http.StatusOK, "ok")
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if !hasDeadline {
		t.Fatal("expected context to have a deadline")
	}
	// The deadline should be roughly now + timeout (within a 1-second tolerance).
	expectedDeadline := time.Now().Add(timeout)
	diff := deadline.Sub(expectedDeadline)
	if diff < -1*time.Second || diff > 1*time.Second {
		t.Fatalf("deadline is too far from expected: deadline=%v, expected~%v", deadline, expectedDeadline)
	}
}

func TestRequestTimeout_HandlerCompletesNormally(t *testing.T) {
	router := gin.New()
	router.Use(RequestTimeout(2 * time.Second))
	router.GET("/fast", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/fast", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
}

func TestRequestTimeout_DeadlinePropagates(t *testing.T) {
	router := gin.New()
	router.Use(RequestTimeout(50 * time.Millisecond))

	var ctxErr error

	router.GET("/slow", func(c *gin.Context) {
		// Simulate a slow operation that checks context.
		select {
		case <-time.After(200 * time.Millisecond):
			// Should not reach here.
		case <-c.Request.Context().Done():
			ctxErr = c.Request.Context().Err()
		}
		c.String(http.StatusOK, "done")
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/slow", nil)
	router.ServeHTTP(w, req)

	if ctxErr == nil {
		t.Fatal("expected context to be cancelled due to deadline, but ctxErr is nil")
	}
	if ctxErr.Error() != "context deadline exceeded" {
		t.Fatalf("expected 'context deadline exceeded', got %q", ctxErr.Error())
	}
}
