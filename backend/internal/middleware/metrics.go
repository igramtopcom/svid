package middleware

import (
	"sync"
	"sync/atomic"
	"time"

	"github.com/gin-gonic/gin"
)

type EndpointMetrics struct {
	Requests   int64   `json:"requests"`
	Errors     int64   `json:"errors"`
	AvgLatency float64 `json:"avg_latency_ms"`
	totalNs    int64
}

type MetricsCollector struct {
	mu        sync.RWMutex
	endpoints map[string]*EndpointMetrics
	StartTime time.Time
}

var GlobalMetrics = &MetricsCollector{
	endpoints: make(map[string]*EndpointMetrics),
	StartTime: time.Now(),
}

func (mc *MetricsCollector) Record(path string, status int, latency time.Duration) {
	mc.mu.Lock()
	m, ok := mc.endpoints[path]
	if !ok {
		m = &EndpointMetrics{}
		mc.endpoints[path] = m
	}
	mc.mu.Unlock()

	atomic.AddInt64(&m.Requests, 1)
	atomic.AddInt64(&m.totalNs, int64(latency))
	if status >= 400 {
		atomic.AddInt64(&m.Errors, 1)
	}
}

func (mc *MetricsCollector) Snapshot() map[string]EndpointMetrics {
	mc.mu.RLock()
	defer mc.mu.RUnlock()
	snap := make(map[string]EndpointMetrics, len(mc.endpoints))
	for k, v := range mc.endpoints {
		reqs := atomic.LoadInt64(&v.Requests)
		totalNs := atomic.LoadInt64(&v.totalNs)
		avgMs := float64(0)
		if reqs > 0 {
			avgMs = float64(totalNs) / float64(reqs) / 1e6
		}
		snap[k] = EndpointMetrics{
			Requests:   reqs,
			Errors:     atomic.LoadInt64(&v.Errors),
			AvgLatency: avgMs,
		}
	}
	return snap
}

func MetricsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		// Skip /metrics and /health from being tracked
		path := c.FullPath()
		if path == "" || path == "/metrics" || path == "/health" {
			return
		}
		GlobalMetrics.Record(path, c.Writer.Status(), time.Since(start))
	}
}
