package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/snakeloader/backend/internal/middleware"
)

func TestRegister_MalformedJSON(t *testing.T) {
	h := NewDeviceHandler(nil)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/api/v1/devices/register", bytes.NewReader([]byte(`{bad`)))
	c.Request.Header.Set("Content-Type", "application/json")

	h.Register(c)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d", w.Code)
	}
}

func TestRegister_MissingHardwareID(t *testing.T) {
	h := NewDeviceHandler(nil)
	body, _ := json.Marshal(map[string]string{
		"os":          "macos",
		"app_version": "1.0.0",
	})
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/api/v1/devices/register", bytes.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")

	h.Register(c)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d", w.Code)
	}
}

func TestRegister_MissingOS(t *testing.T) {
	h := NewDeviceHandler(nil)
	body, _ := json.Marshal(map[string]string{
		"hardware_id": "abcdef1234567890",
		"app_version": "1.0.0",
	})
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/api/v1/devices/register", bytes.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")

	h.Register(c)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d", w.Code)
	}
}

func TestRegister_InvalidOS(t *testing.T) {
	h := NewDeviceHandler(nil)
	body, _ := json.Marshal(map[string]string{
		"hardware_id": "abcdef1234567890",
		"os":          "android",
		"app_version": "1.0.0",
	})
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/api/v1/devices/register", bytes.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")

	h.Register(c)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d", w.Code)
	}
}

func TestRegister_HardwareIDTooShort(t *testing.T) {
	h := NewDeviceHandler(nil)
	body, _ := json.Marshal(map[string]string{
		"hardware_id": "short",
		"os":          "macos",
		"app_version": "1.0.0",
	})
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/api/v1/devices/register", bytes.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")

	h.Register(c)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d", w.Code)
	}
}

func TestRegister_EmptyBody(t *testing.T) {
	h := NewDeviceHandler(nil)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/api/v1/devices/register", bytes.NewReader([]byte(`{}`)))
	c.Request.Header.Set("Content-Type", "application/json")

	h.Register(c)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d", w.Code)
	}
}

func TestHeartbeat_NoAuth(t *testing.T) {
	h := NewDeviceHandler(nil)
	body, _ := json.Marshal(map[string]string{"app_version": "1.0.0"})
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/api/v1/devices/heartbeat", bytes.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")
	// Deliberately NOT setting middleware.DeviceIDKey

	h.Heartbeat(c)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

func TestHeartbeat_MalformedJSON(t *testing.T) {
	h := NewDeviceHandler(nil)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/api/v1/devices/heartbeat", bytes.NewReader([]byte(`{bad`)))
	c.Request.Header.Set("Content-Type", "application/json")
	c.Set(middleware.DeviceIDKey, "00000000-0000-0000-0000-000000000001")

	h.Heartbeat(c)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d", w.Code)
	}
}
