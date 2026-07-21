package middleware

import (
	"time"

	"github.com/gin-gonic/gin"
	"github.com/snakeloader/backend/internal/pkg/logger"
)

func Logger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path

		c.Next()

		// Skip health check logs
		if path == "/health" {
			return
		}

		latency := time.Since(start)
		status := c.Writer.Status()
		requestID, _ := c.Get(RequestIDKey)

		event := logger.Log.Info()
		if status >= 400 {
			event = logger.Log.Warn()
		}
		if status >= 500 {
			event = logger.Log.Error()
		}

		event.
			Str("method", c.Request.Method).
			Str("path", path).
			Int("status", status).
			Dur("latency", latency).
			Str("ip", c.ClientIP()).
			Interface("request_id", requestID).
			Str("user_agent", c.Request.UserAgent()).
			Int("response_size", c.Writer.Size()).
			Msg("request")
	}
}
