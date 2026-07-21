package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/middleware"
)

func init() {
	gin.SetMode(gin.TestMode)
}

// ==================== License Verify — Key Extraction ====================

func TestLicenseVerify_NoAuth_Returns401(t *testing.T) {
	h := NewPremiumHandler(nil, false)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("GET", "/api/v1/premium/licenses/verify?key=test", nil)
	// Deliberately NOT setting middleware.DeviceIDKey

	h.LicenseVerify(c)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	errObj, ok := resp["error"].(map[string]interface{})
	if !ok {
		t.Fatal("expected error object")
	}
	if errObj["code"] != "UNAUTHORIZED" {
		t.Errorf("expected UNAUTHORIZED, got %v", errObj["code"])
	}
}

func TestLicenseVerify_NoKey_Returns400(t *testing.T) {
	h := NewPremiumHandler(nil, false)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("GET", "/api/v1/premium/licenses/verify", nil)
	// No key in header, body, or query param
	c.Set(middleware.DeviceIDKey, uuid.New())

	h.LicenseVerify(c)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	errObj, ok := resp["error"].(map[string]interface{})
	if !ok {
		t.Fatal("expected error object")
	}
	if errObj["code"] != "MISSING_LICENSE_KEY" {
		t.Errorf("expected MISSING_LICENSE_KEY, got %v", errObj["code"])
	}
}

func TestLicenseVerify_KeyFromHeader_Accepted(t *testing.T) {
	// When X-License-Key header is set, it should be used (will hit nil service → panic/500,
	// but the point is it doesn't return 400 MISSING_LICENSE_KEY).
	h := NewPremiumHandler(nil, false)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("GET", "/api/v1/premium/licenses/verify", nil)
	c.Request.Header.Set("X-License-Key", "SVID-test-key-1234")
	c.Set(middleware.DeviceIDKey, uuid.New())

	// This will panic because service is nil — recover and check it didn't return 400
	func() {
		defer func() { recover() }()
		h.LicenseVerify(c)
	}()

	if w.Code == http.StatusBadRequest {
		t.Error("expected key from header to be accepted, got 400 MISSING_LICENSE_KEY")
	}
}

func TestLicenseVerify_KeyFromBody_Accepted(t *testing.T) {
	h := NewPremiumHandler(nil, false)
	body, _ := json.Marshal(map[string]string{"key": "VIDCOMBO-aaaa-bbbb-cccc-dddd-eeee-ffff-0000-1111"})
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/api/v1/premium/licenses/verify", bytes.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")
	c.Set(middleware.DeviceIDKey, uuid.New())

	func() {
		defer func() { recover() }()
		h.LicenseVerify(c)
	}()

	if w.Code == http.StatusBadRequest {
		t.Error("expected key from JSON body to be accepted, got 400 MISSING_LICENSE_KEY")
	}
}

func TestLicenseVerify_KeyFromQuery_LegacyFallback(t *testing.T) {
	h := NewPremiumHandler(nil, false)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("GET", "/api/v1/premium/licenses/verify?key=VIDCOMBO-1234-5678-9abc-def0-1234-5678-9abc-def0", nil)
	c.Set(middleware.DeviceIDKey, uuid.New())

	func() {
		defer func() { recover() }()
		h.LicenseVerify(c)
	}()

	if w.Code == http.StatusBadRequest {
		t.Error("expected key from query param to be accepted as legacy fallback, got 400")
	}
}

func TestLicenseVerify_HeaderTakesPrecedence(t *testing.T) {
	// If both header and query are provided, header should win.
	// We can't directly verify which key was used with nil service,
	// but we verify the handler doesn't return 400.
	h := NewPremiumHandler(nil, false)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("GET", "/api/v1/premium/licenses/verify?key=query-key", nil)
	c.Request.Header.Set("X-License-Key", "SVID-header-key")
	c.Set(middleware.DeviceIDKey, uuid.New())

	func() {
		defer func() { recover() }()
		h.LicenseVerify(c)
	}()

	if w.Code == http.StatusBadRequest {
		t.Error("expected key from header to take precedence, got 400")
	}
}

func TestLicenseVerify_EmptyHeaderFallsToBody(t *testing.T) {
	// Empty X-License-Key header should fall through to body.
	h := NewPremiumHandler(nil, false)
	body, _ := json.Marshal(map[string]string{"key": "SVID-fallback-body"})
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/api/v1/premium/licenses/verify", bytes.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")
	c.Request.Header.Set("X-License-Key", "") // empty
	c.Set(middleware.DeviceIDKey, uuid.New())

	func() {
		defer func() { recover() }()
		h.LicenseVerify(c)
	}()

	if w.Code == http.StatusBadRequest {
		t.Error("expected empty header to fall through to body key, got 400")
	}
}

func TestLicenseVerify_POST_EmptyBody_NoQuery_Returns400(t *testing.T) {
	h := NewPremiumHandler(nil, false)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/api/v1/premium/licenses/verify", bytes.NewReader([]byte(`{}`)))
	c.Request.Header.Set("Content-Type", "application/json")
	c.Set(middleware.DeviceIDKey, uuid.New())

	h.LicenseVerify(c)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 when no key in empty body, got %d", w.Code)
	}
}
