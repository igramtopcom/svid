package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/snakeloader/backend/internal/identity/model"
)

type fakeAuditLogLister struct {
	page         int
	perPage      int
	adminID      string
	action       string
	resourceType string
	dateFrom     *time.Time
	dateTo       *time.Time
}

func (f *fakeAuditLogLister) List(page, perPage int, adminID, action, resourceType string, dateFrom, dateTo *time.Time) ([]model.AuditLog, int64, error) {
	f.page = page
	f.perPage = perPage
	f.adminID = adminID
	f.action = action
	f.resourceType = resourceType
	f.dateFrom = dateFrom
	f.dateTo = dateTo
	return nil, 0, nil
}

type auditHandlerEnvelope struct {
	Success bool `json:"success"`
	Error   *struct {
		Code string `json:"code"`
	} `json:"error,omitempty"`
}

func TestListAuditLogs_RejectsInvalidDates(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name         string
		query        string
		expectedCode string
	}{
		{name: "invalid date_from", query: "/admin/v1/audit-logs?date_from=2026-99-01", expectedCode: "INVALID_DATE"},
		{name: "invalid date_to", query: "/admin/v1/audit-logs?date_to=not-a-date", expectedCode: "INVALID_DATE"},
		{name: "start after end", query: "/admin/v1/audit-logs?date_from=2026-04-03&date_to=2026-04-01", expectedCode: "INVALID_DATE_RANGE"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			handler := &AdminAuditHandler{repo: &fakeAuditLogLister{}}
			router := gin.New()
			router.GET("/admin/v1/audit-logs", handler.ListAuditLogs)

			req := httptest.NewRequest(http.MethodGet, tt.query, nil)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
			}

			var envelope auditHandlerEnvelope
			if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
				t.Fatalf("unmarshal response: %v", err)
			}
			if envelope.Error == nil || envelope.Error.Code != tt.expectedCode {
				t.Fatalf("expected error code %q, got body: %s", tt.expectedCode, rec.Body.String())
			}
		})
	}
}

func TestListAuditLogs_PassesNormalizedFilters(t *testing.T) {
	gin.SetMode(gin.TestMode)

	repo := &fakeAuditLogLister{}
	handler := &AdminAuditHandler{repo: repo}
	router := gin.New()
	router.GET("/admin/v1/audit-logs", handler.ListAuditLogs)

	req := httptest.NewRequest(http.MethodGet, "/admin/v1/audit-logs?page=0&per_page=999&admin_id=admin-1&action=delete&resource_type=license&date_from=2026-04-01&date_to=2026-04-02", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if repo.page != 1 || repo.perPage != 100 {
		t.Fatalf("expected normalized pagination page=1 perPage=100, got page=%d perPage=%d", repo.page, repo.perPage)
	}
	if repo.adminID != "admin-1" || repo.action != "delete" || repo.resourceType != "license" {
		t.Fatalf("unexpected filters: admin=%q action=%q resource=%q", repo.adminID, repo.action, repo.resourceType)
	}
	if repo.dateFrom == nil || repo.dateFrom.Format("2006-01-02") != "2026-04-01" {
		t.Fatalf("unexpected dateFrom: %#v", repo.dateFrom)
	}
	if repo.dateTo == nil || repo.dateTo.Format(time.RFC3339) != "2026-04-02T23:59:59Z" {
		t.Fatalf("unexpected dateTo: %#v", repo.dateTo)
	}
}
