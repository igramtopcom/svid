package middleware

import (
	"fmt"
	"net/http"
	"runtime/debug"

	"github.com/gin-gonic/gin"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/response"
)

func Recovery() gin.HandlerFunc {
	return func(c *gin.Context) {
		defer func() {
			if err := recover(); err != nil {
				// Capture stack trace for server-side debugging.
				stack := debug.Stack()

				logger.Log.Error().
					Str("panic", fmt.Sprintf("%v", err)).
					Str("path", c.Request.URL.Path).
					Str("method", c.Request.Method).
					Str("stack", string(stack)).
					Msg("Panic recovered")

				// Never expose internal details to client.
				response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "An internal error occurred")
				c.Abort()
			}
		}()
		c.Next()
	}
}
