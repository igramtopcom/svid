package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

type productHandlerEnvelope struct {
	Success bool `json:"success"`
	Error   *struct {
		Code string `json:"code"`
	} `json:"error,omitempty"`
}

func TestProductHandlers_RejectInvalidIDs(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name     string
		method   string
		path     string
		register func(router *gin.Engine, handler *AdminProductHandler)
	}{
		{
			name:   "get flag",
			method: http.MethodGet,
			path:   "/admin/v1/flags/not-a-uuid",
			register: func(router *gin.Engine, handler *AdminProductHandler) {
				router.GET("/admin/v1/flags/:id", handler.GetFlag)
			},
		},
		{
			name:   "get config",
			method: http.MethodGet,
			path:   "/admin/v1/config/not-a-uuid",
			register: func(router *gin.Engine, handler *AdminProductHandler) {
				router.GET("/admin/v1/config/:id", handler.GetConfig)
			},
		},
		{
			name:   "get release",
			method: http.MethodGet,
			path:   "/admin/v1/releases/not-a-uuid",
			register: func(router *gin.Engine, handler *AdminProductHandler) {
				router.GET("/admin/v1/releases/:id", handler.GetRelease)
			},
		},
		{
			name:   "get announcement",
			method: http.MethodGet,
			path:   "/admin/v1/announcements/not-a-uuid",
			register: func(router *gin.Engine, handler *AdminProductHandler) {
				router.GET("/admin/v1/announcements/:id", handler.GetAnnouncement)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			handler := NewAdminProductHandler(nil)
			router := gin.New()
			tt.register(router, handler)

			req := httptest.NewRequest(tt.method, tt.path, nil)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
			}

			var envelope productHandlerEnvelope
			if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
				t.Fatalf("unmarshal response: %v", err)
			}
			if envelope.Error == nil || envelope.Error.Code != "INVALID_ID" {
				t.Fatalf("expected INVALID_ID, got body: %s", rec.Body.String())
			}
		})
	}
}
