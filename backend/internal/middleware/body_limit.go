package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/snakeloader/backend/internal/response"
)

// MaxBodySize limits the request body size to prevent large payload attacks.
func MaxBodySize(maxBytes int64) gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.Request.ContentLength > maxBytes {
			response.Error(c, http.StatusRequestEntityTooLarge, "PAYLOAD_TOO_LARGE", "Request body too large")
			c.Abort()
			return
		}
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxBytes)
		c.Next()
	}
}
