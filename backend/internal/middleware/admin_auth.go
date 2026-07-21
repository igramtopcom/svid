package middleware

import (
	"net/http"
	"net/url"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/identity/model"
	"github.com/snakeloader/backend/internal/identity/repository"
	jwtpkg "github.com/snakeloader/backend/internal/pkg/jwt"
	"github.com/snakeloader/backend/internal/response"
)

// setBrandQuery injects or replaces the "brand" query parameter in a raw query string.
func setBrandQuery(rawQuery, brand string) string {
	q, _ := url.ParseQuery(rawQuery)
	q.Set("brand", brand)
	return q.Encode()
}

const (
	AdminKey        = "admin"
	AdminIDKey      = "admin_id"
	AdminBrandScope = "admin_brand_scope"
)

type AdminAuthMiddleware struct {
	jwtManager *jwtpkg.Manager
	adminRepo  adminLookup
}

type adminLookup interface {
	FindByID(id uuid.UUID) (*model.Admin, error)
}

func NewAdminAuthMiddleware(jwtManager *jwtpkg.Manager, adminRepo *repository.AdminRepository) *AdminAuthMiddleware {
	return &AdminAuthMiddleware{
		jwtManager: jwtManager,
		adminRepo:  adminRepo,
	}
}

func (m *AdminAuthMiddleware) RequireJWT() gin.HandlerFunc {
	return func(c *gin.Context) {
		var token string

		// Try Authorization header first
		header := c.GetHeader("Authorization")
		if header != "" {
			parts := strings.SplitN(header, " ", 2)
			if len(parts) == 2 && strings.ToLower(parts[0]) == "bearer" {
				token = parts[1]
			}
		}

		// Fallback: ?token= query param (for EventSource/SSE which can't set headers)
		if token == "" {
			token = c.Query("token")
		}

		if token == "" {
			response.Error(c, http.StatusUnauthorized, "MISSING_TOKEN", "Authorization is required")
			c.Abort()
			return
		}

		result, err := m.jwtManager.Validate(token)
		if err != nil {
			response.Error(c, http.StatusUnauthorized, "INVALID_TOKEN", "Invalid or expired token")
			c.Abort()
			return
		}

		admin, err := m.adminRepo.FindByID(result.AdminID)
		if err != nil {
			response.Error(c, http.StatusUnauthorized, "INVALID_TOKEN", "Admin not found")
			c.Abort()
			return
		}

		c.Set(AdminKey, admin)
		c.Set(AdminIDKey, result.AdminID)
		c.Set(AdminBrandScope, result.BrandScope)

		// Auto-inject brand filter: if admin is scoped to a brand,
		// override the "brand" query param so ALL downstream handlers
		// are automatically filtered. Super admin (empty scope) uses
		// the dropdown-provided ?brand= param as-is.
		if result.BrandScope != "" {
			c.Request.URL.RawQuery = setBrandQuery(c.Request.URL.RawQuery, result.BrandScope)
		}

		c.Next()
	}
}
