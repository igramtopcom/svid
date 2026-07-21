package middleware

import (
	"os"
	"strings"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/snakeloader/backend/internal/pkg/logger"
)

func CORS() gin.HandlerFunc {
	origins := []string{
		"https://svid.app",
		"https://www.svid.app",
		"https://api.svid.app",
		"https://vidcombo.com",
		"https://www.vidcombo.com",
		"https://vidcombo.net",
		"https://www.vidcombo.net",
	}

	// In dev mode, also allow localhost origins
	if os.Getenv("GIN_MODE") != "release" {
		logger.Log.Warn().Msg("CORS: running in dev mode — localhost origins allowed. Set GIN_MODE=release for production")
		origins = append(origins,
			"http://localhost:3000",
			"http://localhost:8080",
			"http://127.0.0.1:3000",
			"http://127.0.0.1:8080",
		)
	}

	// Allow extra origins from env (comma-separated)
	if extra := os.Getenv("CORS_ORIGINS"); extra != "" {
		origins = append(origins, strings.Split(extra, ",")...)
	}

	return cors.New(cors.Config{
		AllowOrigins:     origins,
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization", "X-API-Key", "X-Request-ID"},
		ExposeHeaders:    []string{"X-Request-ID"},
		AllowCredentials: false,
		MaxAge:           12 * time.Hour,
	})
}
