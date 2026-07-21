package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	alertsdto "github.com/snakeloader/backend/internal/alerts/dto"
	alertsservice "github.com/snakeloader/backend/internal/alerts/service"
)

type fakeAdminAlertService struct {
	configID *uuid.UUID
	testErr  error
}

func (f *fakeAdminAlertService) ListConfigs() ([]alertsdto.AlertConfigResponse, error) {
	return nil, nil
}

func (f *fakeAdminAlertService) CreateConfig(req alertsdto.CreateAlertConfigRequest) (*alertsdto.AlertConfigResponse, error) {
	return &alertsdto.AlertConfigResponse{}, nil
}

func (f *fakeAdminAlertService) GetConfig(id uuid.UUID) (*alertsdto.AlertConfigResponse, error) {
	return &alertsdto.AlertConfigResponse{}, nil
}

func (f *fakeAdminAlertService) UpdateConfig(id uuid.UUID, req alertsdto.UpdateAlertConfigRequest) (*alertsdto.AlertConfigResponse, error) {
	return &alertsdto.AlertConfigResponse{}, nil
}

func (f *fakeAdminAlertService) DeleteConfig(id uuid.UUID) error {
	return nil
}

func (f *fakeAdminAlertService) TestAlert(id uuid.UUID) error {
	return f.testErr
}

func (f *fakeAdminAlertService) ListLogs(page, perPage int, configID *uuid.UUID) ([]alertsdto.AlertLogResponse, int64, error) {
	f.configID = configID
	return nil, 0, nil
}

type alertHandlerEnvelope struct {
	Success bool `json:"success"`
	Error   *struct {
		Code string `json:"code"`
	} `json:"error,omitempty"`
}

func TestListLogs_RejectsInvalidConfigID(t *testing.T) {
	gin.SetMode(gin.TestMode)

	handler := &AdminAlertHandler{service: &fakeAdminAlertService{}}
	router := gin.New()
	router.GET("/admin/v1/alerts/logs", handler.ListLogs)

	req := httptest.NewRequest(http.MethodGet, "/admin/v1/alerts/logs?config_id=bad-id", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestTestAlert_MapsNotFoundTo404(t *testing.T) {
	gin.SetMode(gin.TestMode)

	handler := &AdminAlertHandler{service: &fakeAdminAlertService{testErr: alertsservice.ErrAlertConfigNotFound}}
	router := gin.New()
	router.POST("/admin/v1/alerts/:id/test", handler.TestAlert)

	req := httptest.NewRequest(http.MethodPost, "/admin/v1/alerts/11111111-1111-1111-1111-111111111111/test", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d: %s", rec.Code, rec.Body.String())
	}

	var envelope alertHandlerEnvelope
	if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	if envelope.Error == nil || envelope.Error.Code != "NOT_FOUND" {
		t.Fatalf("expected NOT_FOUND, got body: %s", rec.Body.String())
	}
}
