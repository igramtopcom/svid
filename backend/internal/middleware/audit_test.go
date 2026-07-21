package middleware

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestAuditLog_SkipsGET(t *testing.T) {
	router := gin.New()
	router.Use(AuditLog(nil))
	called := false
	router.GET("/admin/v1/devices", func(c *gin.Context) {
		called = true
		c.String(http.StatusOK, "ok")
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/admin/v1/devices", nil)
	router.ServeHTTP(w, req)

	if !called {
		t.Error("handler not called")
	}
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

func TestAuditLog_LogsPOST(t *testing.T) {
	router := gin.New()
	router.Use(AuditLog(nil))
	router.POST("/admin/v1/flags", func(c *gin.Context) {
		c.String(http.StatusCreated, "created")
	})

	body, _ := json.Marshal(map[string]string{"name": "test_flag", "value": "true"})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/admin/v1/flags", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Errorf("expected 201, got %d", w.Code)
	}
}

func TestAuditLog_LogsPATCH(t *testing.T) {
	router := gin.New()
	router.Use(AuditLog(nil))
	router.PATCH("/admin/v1/devices/:id", func(c *gin.Context) {
		c.String(http.StatusOK, "updated")
	})

	body, _ := json.Marshal(map[string]string{"tier": "pro"})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/admin/v1/devices/123", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

func TestAuditLog_LogsDELETE(t *testing.T) {
	router := gin.New()
	router.Use(AuditLog(nil))
	router.DELETE("/admin/v1/flags/:id", func(c *gin.Context) {
		c.String(http.StatusOK, "deleted")
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/admin/v1/flags/abc", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

func TestSanitizeBody_RedactsPassword(t *testing.T) {
	// Email is also PII and gets redacted (broad ultra-review 2026-05-21).
	// Use a non-sensitive marker field to verify non-PII data is preserved.
	input := `{"email":"admin@test.com","password":"supersecret123","display_name":"Admin"}`
	result := sanitizeBody(input)

	var data map[string]interface{}
	json.Unmarshal([]byte(result), &data)

	if data["password"] != "[REDACTED]" {
		t.Errorf("expected password to be redacted, got %v", data["password"])
	}
	// Email is now treated as PII and redacted alongside auth credentials.
	// Per broad ultra-review: POST /admin/v1/licenses/import-legacy carrying
	// ~4,240 emails MUST NOT persist them plaintext in audit_logs.
	if data["email"] != "[REDACTED]" {
		t.Errorf("expected email redacted as PII, got %v", data["email"])
	}
	// Non-PII fields stay intact.
	if data["display_name"] != "Admin" {
		t.Errorf("expected non-PII field preserved, got %v", data["display_name"])
	}
}

func TestSanitizeBody_RedactsNestedSecrets(t *testing.T) {
	input := `{"config":{"api_key":"sk_live_abc","name":"test"}}`
	result := sanitizeBody(input)

	var data map[string]interface{}
	json.Unmarshal([]byte(result), &data)

	config := data["config"].(map[string]interface{})
	if config["api_key"] != "[REDACTED]" {
		t.Errorf("expected api_key to be redacted, got %v", config["api_key"])
	}
	if config["name"] != "test" {
		t.Errorf("expected name preserved, got %v", config["name"])
	}
}

func TestSanitizeBody_NonJSON(t *testing.T) {
	input := "plain text body"
	result := sanitizeBody(input)
	if result != input {
		t.Errorf("expected non-JSON passthrough, got %q", result)
	}
}

func TestSanitizeBody_Empty(t *testing.T) {
	result := sanitizeBody("")
	if result != "" {
		t.Errorf("expected empty, got %q", result)
	}
}

func TestAuditLog_BodyPassedToHandler(t *testing.T) {
	router := gin.New()
	router.Use(AuditLog(nil))

	var receivedName string
	router.POST("/test", func(c *gin.Context) {
		var body map[string]string
		c.ShouldBindJSON(&body)
		receivedName = body["name"]
		c.String(http.StatusOK, "ok")
	})

	body, _ := json.Marshal(map[string]string{"name": "hello"})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/test", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, req)

	if receivedName != "hello" {
		t.Errorf("handler didn't receive body, got name=%q", receivedName)
	}
}
