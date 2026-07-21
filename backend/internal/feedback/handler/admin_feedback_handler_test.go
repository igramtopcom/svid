package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

type feedbackHandlerEnvelope struct {
	Success bool `json:"success"`
	Error   *struct {
		Code string `json:"code"`
	} `json:"error,omitempty"`
}

func TestFeedbackHandlers_RejectInvalidIDs(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name     string
		method   string
		path     string
		register func(router *gin.Engine, handler *AdminFeedbackHandler)
	}{
		{
			name:   "get ticket",
			method: http.MethodGet,
			path:   "/admin/v1/tickets/not-a-uuid",
			register: func(router *gin.Engine, handler *AdminFeedbackHandler) {
				router.GET("/admin/v1/tickets/:id", handler.GetTicket)
			},
		},
		{
			name:   "reply ticket",
			method: http.MethodPost,
			path:   "/admin/v1/tickets/not-a-uuid/messages",
			register: func(router *gin.Engine, handler *AdminFeedbackHandler) {
				router.POST("/admin/v1/tickets/:id/messages", handler.AdminReply)
			},
		},
		{
			name:   "get feature request",
			method: http.MethodGet,
			path:   "/admin/v1/features/not-a-uuid",
			register: func(router *gin.Engine, handler *AdminFeedbackHandler) {
				router.GET("/admin/v1/features/:id", handler.GetFeatureRequest)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			handler := NewAdminFeedbackHandler(nil, nil)
			router := gin.New()
			tt.register(router, handler)

			req := httptest.NewRequest(tt.method, tt.path, nil)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
			}

			var envelope feedbackHandlerEnvelope
			if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
				t.Fatalf("unmarshal response: %v", err)
			}
			if envelope.Error == nil || envelope.Error.Code != "INVALID_ID" {
				t.Fatalf("expected INVALID_ID, got body: %s", rec.Body.String())
			}
		})
	}
}
