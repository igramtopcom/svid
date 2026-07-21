package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func TestMetricsCollector_Record(t *testing.T) {
	mc := &MetricsCollector{
		endpoints: make(map[string]*EndpointMetrics),
		StartTime: time.Now(),
	}

	mc.Record("/api/v1/test", 200, 10*time.Millisecond)
	mc.Record("/api/v1/test", 200, 20*time.Millisecond)
	mc.Record("/api/v1/test", 500, 5*time.Millisecond)

	snap := mc.Snapshot()
	m, ok := snap["/api/v1/test"]
	if !ok {
		t.Fatal("expected endpoint in snapshot")
	}

	if m.Requests != 3 {
		t.Errorf("expected 3 requests, got %d", m.Requests)
	}
	if m.Errors != 1 {
		t.Errorf("expected 1 error, got %d", m.Errors)
	}
	if m.AvgLatency <= 0 {
		t.Error("expected positive average latency")
	}
}

func TestMetricsCollector_Snapshot_Empty(t *testing.T) {
	mc := &MetricsCollector{
		endpoints: make(map[string]*EndpointMetrics),
		StartTime: time.Now(),
	}

	snap := mc.Snapshot()
	if len(snap) != 0 {
		t.Errorf("expected empty snapshot, got %d entries", len(snap))
	}
}

func TestMetricsCollector_MultipleEndpoints(t *testing.T) {
	mc := &MetricsCollector{
		endpoints: make(map[string]*EndpointMetrics),
		StartTime: time.Now(),
	}

	mc.Record("/api/a", 200, time.Millisecond)
	mc.Record("/api/b", 404, time.Millisecond)
	mc.Record("/api/c", 200, time.Millisecond)

	snap := mc.Snapshot()
	if len(snap) != 3 {
		t.Errorf("expected 3 endpoints, got %d", len(snap))
	}

	if snap["/api/b"].Errors != 1 {
		t.Error("expected 1 error for /api/b (404)")
	}
}

func TestMetricsCollector_ErrorThresholds(t *testing.T) {
	mc := &MetricsCollector{
		endpoints: make(map[string]*EndpointMetrics),
		StartTime: time.Now(),
	}

	// Status < 400 should not be counted as errors
	mc.Record("/test", 200, time.Millisecond)
	mc.Record("/test", 201, time.Millisecond)
	mc.Record("/test", 301, time.Millisecond)
	mc.Record("/test", 399, time.Millisecond)

	// Status >= 400 should be errors
	mc.Record("/test", 400, time.Millisecond)
	mc.Record("/test", 401, time.Millisecond)
	mc.Record("/test", 403, time.Millisecond)
	mc.Record("/test", 404, time.Millisecond)
	mc.Record("/test", 500, time.Millisecond)

	snap := mc.Snapshot()
	if snap["/test"].Requests != 9 {
		t.Errorf("expected 9 requests, got %d", snap["/test"].Requests)
	}
	if snap["/test"].Errors != 5 {
		t.Errorf("expected 5 errors, got %d", snap["/test"].Errors)
	}
}

func TestMetricsMiddleware_SkipsHealthAndMetrics(t *testing.T) {
	// Reset global metrics for test isolation
	original := GlobalMetrics
	GlobalMetrics = &MetricsCollector{
		endpoints: make(map[string]*EndpointMetrics),
		StartTime: time.Now(),
	}
	defer func() { GlobalMetrics = original }()

	router := gin.New()
	router.Use(MetricsMiddleware())
	router.GET("/health", func(c *gin.Context) { c.String(200, "ok") })
	router.GET("/metrics", func(c *gin.Context) { c.String(200, "ok") })
	router.GET("/api/v1/test", func(c *gin.Context) { c.String(200, "ok") })

	// Hit all endpoints
	for _, path := range []string{"/health", "/metrics", "/api/v1/test"} {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, path, nil)
		router.ServeHTTP(w, req)
	}

	snap := GlobalMetrics.Snapshot()

	// /health and /metrics should be skipped
	if _, ok := snap["/health"]; ok {
		t.Error("/health should be excluded from metrics")
	}
	if _, ok := snap["/metrics"]; ok {
		t.Error("/metrics should be excluded from metrics")
	}

	// /api/v1/test should be tracked
	if _, ok := snap["/api/v1/test"]; !ok {
		t.Error("/api/v1/test should be tracked")
	}
}
