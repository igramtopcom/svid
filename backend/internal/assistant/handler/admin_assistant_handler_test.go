package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

type assistantHandlerEnvelope struct {
	Success bool `json:"success"`
	Error   *struct {
		Code string `json:"code"`
	} `json:"error,omitempty"`
}

func TestAssistantHandlers_RejectInvalidIDs(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name     string
		method   string
		path     string
		register func(router *gin.Engine, handler *AdminAssistantHandler)
	}{
		{
			name:   "get session",
			method: http.MethodGet,
			path:   "/admin/v1/assistant/sessions/not-a-uuid",
			register: func(router *gin.Engine, handler *AdminAssistantHandler) {
				router.GET("/admin/v1/assistant/sessions/:id", handler.GetSession)
			},
		},
		{
			name:   "get knowledge",
			method: http.MethodGet,
			path:   "/admin/v1/assistant/knowledge/not-a-uuid",
			register: func(router *gin.Engine, handler *AdminAssistantHandler) {
				router.GET("/admin/v1/assistant/knowledge/:id", handler.GetKnowledge)
			},
		},
		{
			name:   "delete knowledge",
			method: http.MethodDelete,
			path:   "/admin/v1/assistant/knowledge/not-a-uuid",
			register: func(router *gin.Engine, handler *AdminAssistantHandler) {
				router.DELETE("/admin/v1/assistant/knowledge/:id", handler.DeleteKnowledge)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			handler := NewAdminAssistantHandler(nil)
			router := gin.New()
			tt.register(router, handler)

			req := httptest.NewRequest(tt.method, tt.path, nil)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
			}

			var envelope assistantHandlerEnvelope
			if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
				t.Fatalf("unmarshal response: %v", err)
			}
			if envelope.Error == nil || envelope.Error.Code != "INVALID_ID" {
				t.Fatalf("expected INVALID_ID, got body: %s", rec.Body.String())
			}
		})
	}
}
