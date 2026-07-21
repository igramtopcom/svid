package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func init() {
	gin.SetMode(gin.TestMode)
}

func TestLogin_MalformedJSON(t *testing.T) {
	h := NewAdminAuthHandler(nil, nil)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/admin/v1/auth/login", bytes.NewReader([]byte(`{invalid`)))
	c.Request.Header.Set("Content-Type", "application/json")

	h.Login(c)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d", w.Code)
	}
}

func TestLogin_MissingEmail(t *testing.T) {
	h := NewAdminAuthHandler(nil, nil)
	body, _ := json.Marshal(map[string]string{"password": "longpassword123"})
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/admin/v1/auth/login", bytes.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")

	h.Login(c)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d", w.Code)
	}
}

func TestLogin_MissingPassword(t *testing.T) {
	h := NewAdminAuthHandler(nil, nil)
	body, _ := json.Marshal(map[string]string{"email": "admin@test.com"})
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/admin/v1/auth/login", bytes.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")

	h.Login(c)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d", w.Code)
	}
}

func TestLogin_InvalidEmailFormat(t *testing.T) {
	h := NewAdminAuthHandler(nil, nil)
	body, _ := json.Marshal(map[string]string{"email": "not-an-email", "password": "longpassword123"})
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/admin/v1/auth/login", bytes.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")

	h.Login(c)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d", w.Code)
	}
}

func TestLogin_PasswordTooShort(t *testing.T) {
	h := NewAdminAuthHandler(nil, nil)
	body, _ := json.Marshal(map[string]string{"email": "admin@test.com", "password": "short"})
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/admin/v1/auth/login", bytes.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")

	h.Login(c)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d", w.Code)
	}
}

func TestLogin_EmptyBody(t *testing.T) {
	h := NewAdminAuthHandler(nil, nil)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/admin/v1/auth/login", bytes.NewReader([]byte(`{}`)))
	c.Request.Header.Set("Content-Type", "application/json")

	h.Login(c)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d", w.Code)
	}
}

func TestLogin_ResponseContainsErrorCode(t *testing.T) {
	h := NewAdminAuthHandler(nil, nil)
	body, _ := json.Marshal(map[string]string{"email": "bad", "password": "short"})
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("POST", "/admin/v1/auth/login", bytes.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")

	h.Login(c)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	if resp["success"] != false {
		t.Error("expected success=false")
	}
	errObj, ok := resp["error"].(map[string]interface{})
	if !ok {
		t.Fatal("expected error object")
	}
	if errObj["code"] != "VALIDATION_ERROR" {
		t.Errorf("expected VALIDATION_ERROR, got %s", errObj["code"])
	}
}
