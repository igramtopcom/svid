package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

// Tests for security hardening features on the register endpoint.

func TestRegister_WithLegacyHardwareID_PassesValidation(t *testing.T) {
	// A valid request that includes legacy_hardware_id should pass validation.
	// The nil service will panic after validation — we recover and verify no 422.
	h := NewDeviceHandler(nil)
	body, _ := json.Marshal(map[string]string{
		"hardware_id":        "sha256-new-fingerprint-abcdef1234567890",
		"legacy_hardware_id": "old-hostname-macos-fingerprint",
		"os":                 "macos",
		"app_version":        "1.3.0",
		"device_name":        "MacBook Pro",
	})
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/api/v1/devices/register", bytes.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")

	func() {
		defer func() { recover() }()
		h.Register(c)
	}()

	if w.Code == http.StatusUnprocessableEntity {
		t.Errorf("expected validation to pass with legacy_hardware_id, got 422")
	}
}

func TestRegister_LegacyHardwareIDTooLong_Rejected(t *testing.T) {
	h := NewDeviceHandler(nil)
	longID := strings.Repeat("x", 256) // exceeds max=255
	body, _ := json.Marshal(map[string]string{
		"hardware_id":        "sha256-valid-fingerprint-12345678",
		"legacy_hardware_id": longID,
		"os":                 "macos",
		"app_version":        "1.3.0",
	})
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/api/v1/devices/register", bytes.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")

	h.Register(c)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422 for legacy_hardware_id > 255 chars, got %d", w.Code)
	}
}

func TestRegister_WithoutLegacyHardwareID_StillWorks(t *testing.T) {
	// Backward compatibility: old clients that don't send legacy_hardware_id
	// should still pass validation (field is optional).
	h := NewDeviceHandler(nil)
	body, _ := json.Marshal(map[string]string{
		"hardware_id": "old-client-fingerprint-12345678",
		"os":          "windows",
		"app_version": "1.2.0",
	})
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/api/v1/devices/register", bytes.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")

	func() {
		defer func() { recover() }()
		h.Register(c)
	}()

	if w.Code == http.StatusUnprocessableEntity {
		t.Errorf("expected validation to pass without legacy_hardware_id, got 422")
	}
}

func TestRegister_AllThreeOSValues_Valid(t *testing.T) {
	// Ensure all three OS enum values still pass validation after DTO change.
	for _, osName := range []string{"macos", "windows", "linux"} {
		t.Run(osName, func(t *testing.T) {
			h := NewDeviceHandler(nil)
			body, _ := json.Marshal(map[string]string{
				"hardware_id": "valid-fingerprint-1234567890",
				"os":          osName,
				"app_version": "1.3.0",
			})
			w := httptest.NewRecorder()
			c, _ := gin.CreateTestContext(w)
			c.Request, _ = http.NewRequest("POST", "/api/v1/devices/register", bytes.NewReader(body))
			c.Request.Header.Set("Content-Type", "application/json")

			func() {
				defer func() { recover() }()
				h.Register(c)
			}()

			if w.Code == http.StatusUnprocessableEntity {
				t.Errorf("expected %s to be valid OS, got 422", osName)
			}
		})
	}
}

func TestRegister_ResponseContainsErrorCode_OnValidation(t *testing.T) {
	h := NewDeviceHandler(nil)
	body, _ := json.Marshal(map[string]string{
		"hardware_id": "short", // too short (min=8)
		"os":          "macos",
		"app_version": "1.0.0",
	})
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/api/v1/devices/register", bytes.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")

	h.Register(c)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	if resp["success"] != false {
		t.Error("expected success=false")
	}
	errObj, ok := resp["error"].(map[string]interface{})
	if !ok {
		t.Fatal("expected error object in response")
	}
	if errObj["code"] != "VALIDATION_ERROR" {
		t.Errorf("expected VALIDATION_ERROR, got %v", errObj["code"])
	}
}
