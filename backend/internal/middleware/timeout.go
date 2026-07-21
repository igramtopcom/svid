package middleware

import (
	"context"
	"time"

	"github.com/gin-gonic/gin"
)

// RequestTimeout sets a context deadline on the request.
// Downstream code (database drivers, HTTP clients) that respects context will
// cancel when the deadline is exceeded. The http.Server's WriteTimeout acts as
// the hard kill for handlers that don't check context.
//
// Note: Do NOT apply this to SSE/streaming endpoints — they are long-lived by design.
func RequestTimeout(timeout time.Duration) gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), timeout)
		defer cancel()
		c.Request = c.Request.WithContext(ctx)
		c.Next()
	}
}
