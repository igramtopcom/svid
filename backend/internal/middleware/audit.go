package middleware

import (
	"bytes"
	"encoding/json"
	"io"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/identity/model"
	"github.com/snakeloader/backend/internal/identity/repository"
	"github.com/snakeloader/backend/internal/pkg/logger"
)

// AuditLog logs and persists admin-initiated state changes (POST, PUT, PATCH, DELETE).
// Should only be applied to admin route groups.
func AuditLog(auditRepo *repository.AuditLogRepository) gin.HandlerFunc {
	return func(c *gin.Context) {
		method := c.Request.Method

		// Only audit state-changing methods
		if method == "GET" || method == "HEAD" || method == "OPTIONS" {
			c.Next()
			return
		}

		// Read and restore the request body
		var bodyStr string
		if c.Request.Body != nil {
			bodyBytes, err := io.ReadAll(c.Request.Body)
			if err == nil {
				bodyStr = sanitizeBody(string(bodyBytes))
				c.Request.Body = io.NopCloser(bytes.NewReader(bodyBytes))
			}
		}

		// Get admin info from JWT context (set by AdminAuthMiddleware)
		adminID, _ := c.Get("admin_id")
		var adminEmail string
		if admin, exists := c.Get("admin"); exists {
			if a, ok := admin.(*model.Admin); ok {
				adminEmail = a.Email
			}
		}

		c.Next()

		// Extract resource type and ID from path
		resourceType, resourceID := extractResource(c.Request.URL.Path)

		statusCode := c.Writer.Status()

		// Log to structured logger
		logger.Log.Info().
			Str("audit", "admin_action").
			Str("method", method).
			Str("path", c.Request.URL.Path).
			Interface("admin_id", adminID).
			Str("admin_email", adminEmail).
			Int("status", statusCode).
			Str("resource", resourceType).
			Str("ip", c.ClientIP()).
			Msg("admin audit")

		// Persist to database
		if auditRepo != nil {
			var uid uuid.UUID
			if id, ok := adminID.(uuid.UUID); ok {
				uid = id
			}

			entry := &model.AuditLog{
				AdminID:      uid,
				AdminEmail:   adminEmail,
				Action:       method,
				ResourceType: resourceType,
				ResourceID:   resourceID,
				Path:         c.Request.URL.Path,
				RequestBody:  bodyStr,
				StatusCode:   statusCode,
				IPAddress:    c.ClientIP(),
			}
			if err := auditRepo.Create(entry); err != nil {
				logger.Log.Warn().Err(err).Msg("Failed to persist audit log")
			}
		}
	}
}

// extractResource parses the URL path to extract resource type and ID.
// e.g. "/admin/v1/devices/abc-123" → ("devices", "abc-123")
func extractResource(path string) (string, string) {
	// Remove /admin/v1/ prefix
	path = strings.TrimPrefix(path, "/admin/v1/")
	parts := strings.SplitN(path, "/", 3)
	if len(parts) == 0 {
		return "", ""
	}
	resourceType := parts[0]
	var resourceID string
	if len(parts) >= 2 {
		resourceID = parts[1]
	}
	return resourceType, resourceID
}

// sanitizeBody redacts sensitive fields from JSON request bodies.
func sanitizeBody(body string) string {
	if body == "" {
		return ""
	}

	var data map[string]interface{}
	if err := json.Unmarshal([]byte(body), &data); err != nil {
		// Not JSON — return truncated raw body
		if len(body) > 500 {
			return body[:500] + "...[truncated]"
		}
		return body
	}

	redactSensitiveFields(data)

	sanitized, err := json.Marshal(data)
	if err != nil {
		return "[redaction error]"
	}
	return string(sanitized)
}

var sensitiveKeys = []string{
	// Auth credentials
	"password", "secret", "token", "api_key", "apikey",
	"credential", "authorization", "access_token", "refresh_token",
	// License + PII — broad ultra-review 2026-05-21. Without these,
	// POST /admin/v1/licenses/import-legacy with 4,240 PHP migration rows
	// would persist 4,240 plaintext license keys + emails + Stripe IDs
	// into the audit_logs table.
	"license_key", "licensekey", "license",
	"email", "contact_email", "customer_email",
	"stripe_customer_id", "stripe_subscription_id", "stripe_payment_intent_id",
	"device_id",
}

func redactSensitiveFields(data map[string]interface{}) {
	for key, val := range data {
		lower := strings.ToLower(key)
		for _, sensitive := range sensitiveKeys {
			if strings.Contains(lower, sensitive) {
				data[key] = "[REDACTED]"
				break
			}
		}
		// Recurse into nested objects
		if nested, ok := val.(map[string]interface{}); ok {
			redactSensitiveFields(nested)
		}
	}
}
