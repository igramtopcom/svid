package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

func TestRateLimiter_NilRedis_AllowsAll(t *testing.T) {
	rl := NewRateLimiter(nil, 5, 60)
	router := gin.New()
	router.Use(rl.Middleware())
	router.GET("/test", func(c *gin.Context) {
		c.String(http.StatusOK, "ok")
	})

	// Send 10 requests — all should pass since Redis is nil
	for i := 0; i < 10; i++ {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/test", nil)
		router.ServeHTTP(w, req)

		if w.Code != http.StatusOK {
			t.Errorf("request %d: expected 200, got %d", i, w.Code)
		}
	}
}

func TestRateLimiter_NilRedis_NoHeaders(t *testing.T) {
	rl := NewRateLimiter(nil, 5, 60)
	router := gin.New()
	router.Use(rl.Middleware())
	router.GET("/test", func(c *gin.Context) {
		c.String(http.StatusOK, "ok")
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	router.ServeHTTP(w, req)

	if w.Header().Get("X-RateLimit-Limit") != "" {
		t.Error("expected no X-RateLimit-Limit header when Redis is nil")
	}
}

func TestRateLimiter_HandlerCalled(t *testing.T) {
	rl := NewRateLimiter(nil, 100, 60)
	called := false
	router := gin.New()
	router.Use(rl.Middleware())
	router.POST("/action", func(c *gin.Context) {
		called = true
		c.String(http.StatusCreated, "created")
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/action", nil)
	router.ServeHTTP(w, req)

	if !called {
		t.Error("handler was not called")
	}
	if w.Code != http.StatusCreated {
		t.Errorf("expected 201, got %d", w.Code)
	}
}

func TestRateLimiter_ConfigStored(t *testing.T) {
	rl := NewRateLimiter(nil, 42, 120)
	if rl.maxRequests != 42 {
		t.Errorf("expected maxRequests=42, got %d", rl.maxRequests)
	}
	if rl.windowSeconds != 120 {
		t.Errorf("expected windowSeconds=120, got %d", rl.windowSeconds)
	}
}

func TestShouldSkipGlobalRateLimit(t *testing.T) {
	tests := []struct {
		path string
		want bool
	}{
		{path: "/health", want: true},
		{path: "/health/live", want: true},
		{path: "/dashboard-ui/assets/index.js", want: true},
		{path: "/admin/v1/devices", want: true},
		{path: "/admin/v1/dashboard/comprehensive", want: true},
		{path: "/admin/v1/auth/login", want: false},
		{path: "/api/v1/analytics/events", want: false},
	}

	for _, tc := range tests {
		if got := shouldSkipGlobalRateLimit(tc.path); got != tc.want {
			t.Fatalf("path %s: expected %v, got %v", tc.path, tc.want, got)
		}
	}
}

func TestRateLimiter_GlobalMiddleware_SkipsProtectedAdminRoutes(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() {
		_ = rdb.Close()
		mr.Close()
	})

	rl := NewRateLimiter(rdb, 1, 60)
	router := gin.New()
	router.Use(rl.Middleware())
	router.GET("/admin/v1/devices", func(c *gin.Context) {
		c.String(http.StatusOK, "ok")
	})

	for i := 0; i < 3; i++ {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/admin/v1/devices", nil)
		router.ServeHTTP(w, req)
		if w.Code != http.StatusOK {
			t.Fatalf("request %d: expected 200, got %d", i, w.Code)
		}
	}
}

func TestRateLimiter_GlobalMiddleware_StillLimitsPublicRoutes(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() {
		_ = rdb.Close()
		mr.Close()
	})

	rl := NewRateLimiter(rdb, 1, 60)
	router := gin.New()
	router.Use(rl.Middleware())
	router.GET("/api/v1/public", func(c *gin.Context) {
		c.String(http.StatusOK, "ok")
	})

	first := httptest.NewRecorder()
	firstReq, _ := http.NewRequest("GET", "/api/v1/public", nil)
	router.ServeHTTP(first, firstReq)
	if first.Code != http.StatusOK {
		t.Fatalf("expected first request to pass, got %d", first.Code)
	}

	second := httptest.NewRecorder()
	secondReq, _ := http.NewRequest("GET", "/api/v1/public", nil)
	router.ServeHTTP(second, secondReq)
	if second.Code != http.StatusTooManyRequests {
		t.Fatalf("expected second request to be rate-limited, got %d", second.Code)
	}
}

func TestRateLimiter_GlobalMiddleware_DoesNotSkipAdminLogin(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() {
		_ = rdb.Close()
		mr.Close()
	})

	rl := NewRateLimiter(rdb, 1, 60)
	router := gin.New()
	router.Use(rl.Middleware())
	router.POST("/admin/v1/auth/login", func(c *gin.Context) {
		c.String(http.StatusOK, "ok")
	})

	first := httptest.NewRecorder()
	firstReq, _ := http.NewRequest("POST", "/admin/v1/auth/login", nil)
	router.ServeHTTP(first, firstReq)
	if first.Code != http.StatusOK {
		t.Fatalf("expected first login request to pass, got %d", first.Code)
	}

	second := httptest.NewRecorder()
	secondReq, _ := http.NewRequest("POST", "/admin/v1/auth/login", nil)
	router.ServeHTTP(second, secondReq)
	if second.Code != http.StatusTooManyRequests {
		t.Fatalf("expected second login request to be rate-limited, got %d", second.Code)
	}
}
