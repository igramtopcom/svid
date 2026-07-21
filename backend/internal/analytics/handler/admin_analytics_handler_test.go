package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	analyticsdto "github.com/snakeloader/backend/internal/analytics/dto"
	analyticsrepo "github.com/snakeloader/backend/internal/analytics/repository"
)

type fakeAdminAnalyticsService struct {
	topLimit           int
	topBrand           string
	bootstrapPage      int
	bootstrapPerPage   int
	bootstrapBrand     string
	bootstrapOS        string
	bootstrapStage     string
	bootstrapStatus    string
	bootstrapErrorCode string
	downloadErrorDays  int
	downloadErrorBrand string
	downloadDays       int
	downloadBrand      string
}

func (f *fakeAdminAnalyticsService) ListEvents(page, perPage int, eventType, os, appVersion, brand string) ([]analyticsdto.EventResponse, int64, error) {
	return nil, 0, nil
}

func (f *fakeAdminAnalyticsService) ListBootstrapEvents(page, perPage int, brand, os, appVersion, stage, status, errorCode string, dateFrom, dateTo *time.Time) ([]analyticsdto.BootstrapEventResponse, int64, error) {
	f.bootstrapPage = page
	f.bootstrapPerPage = perPage
	f.bootstrapBrand = brand
	f.bootstrapOS = os
	f.bootstrapStage = stage
	f.bootstrapStatus = status
	f.bootstrapErrorCode = errorCode
	return []analyticsdto.BootstrapEventResponse{{
		InstallID:  "install-123",
		Brand:      brand,
		OS:         os,
		AppVersion: "1.7.3",
		Stage:      stage,
		Status:     status,
		ErrorCode:  errorCode,
	}}, 1, nil
}

func (f *fakeAdminAnalyticsService) GetOverview(brand string) (*analyticsdto.AnalyticsOverview, error) {
	return &analyticsdto.AnalyticsOverview{}, nil
}

func (f *fakeAdminAnalyticsService) GetTopEvents(limit int, brand string) ([]analyticsrepo.EventTypeCount, error) {
	f.topLimit = limit
	f.topBrand = brand
	return []analyticsrepo.EventTypeCount{{EventType: "app_open", Count: 12}}, nil
}

func (f *fakeAdminAnalyticsService) GetDailyStats(startDate, endDate time.Time, metricName string) ([]analyticsdto.DailyStatsResponse, error) {
	return nil, nil
}

func (f *fakeAdminAnalyticsService) ListDownloadErrors(page, perPage int, errorCode, errorPhase, diagnosticErrorCode, platform, os, appVersion, brand string, dateFrom, dateTo *time.Time) ([]analyticsdto.DownloadErrorResponse, int64, error) {
	return nil, 0, nil
}

func (f *fakeAdminAnalyticsService) GetDownloadErrorStats(days int, brand string) (*analyticsdto.DownloadErrorStatsResponse, error) {
	f.downloadErrorDays = days
	f.downloadErrorBrand = brand
	return &analyticsdto.DownloadErrorStatsResponse{}, nil
}

func (f *fakeAdminAnalyticsService) GetDownloadStats(days int, brand string) (*analyticsdto.DownloadStatsResponse, error) {
	f.downloadDays = days
	f.downloadBrand = brand
	return &analyticsdto.DownloadStatsResponse{}, nil
}

type analyticsHandlerEnvelope struct {
	Success bool            `json:"success"`
	Data    json.RawMessage `json:"data"`
	Error   *struct {
		Code string `json:"code"`
	} `json:"error,omitempty"`
}

func TestTopEvents_NormalizesLimitAndPassesBrand(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name          string
		query         string
		expectedLimit int
		expectedBrand string
	}{
		{name: "defaults invalid to ten", query: "/admin/v1/analytics/top-events?limit=0&brand=vidcombo", expectedLimit: 10, expectedBrand: "vidcombo"},
		{name: "clamps to max", query: "/admin/v1/analytics/top-events?limit=999&brand=ssvid", expectedLimit: 100, expectedBrand: "ssvid"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc := &fakeAdminAnalyticsService{}
			handler := &AdminAnalyticsHandler{service: svc}

			router := gin.New()
			router.GET("/admin/v1/analytics/top-events", handler.TopEvents)

			req := httptest.NewRequest(http.MethodGet, tt.query, nil)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != http.StatusOK {
				t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
			}
			if svc.topLimit != tt.expectedLimit {
				t.Fatalf("expected limit %d, got %d", tt.expectedLimit, svc.topLimit)
			}
			if svc.topBrand != tt.expectedBrand {
				t.Fatalf("expected brand %q, got %q", tt.expectedBrand, svc.topBrand)
			}
		})
	}
}

func TestListBootstrapEvents_PassesFilters(t *testing.T) {
	gin.SetMode(gin.TestMode)

	svc := &fakeAdminAnalyticsService{}
	handler := &AdminAnalyticsHandler{service: svc}

	router := gin.New()
	router.GET("/admin/v1/analytics/bootstrap-events", handler.ListBootstrapEvents)

	req := httptest.NewRequest(
		http.MethodGet,
		"/admin/v1/analytics/bootstrap-events?page=2&per_page=5&brand=vidcombo&os=windows&stage=register&status=failed&error_code=network",
		nil,
	)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if svc.bootstrapPage != 2 || svc.bootstrapPerPage != 5 {
		t.Fatalf("unexpected pagination: page=%d per_page=%d", svc.bootstrapPage, svc.bootstrapPerPage)
	}
	if svc.bootstrapBrand != "vidcombo" || svc.bootstrapOS != "windows" ||
		svc.bootstrapStage != "register" || svc.bootstrapStatus != "failed" ||
		svc.bootstrapErrorCode != "network" {
		t.Fatalf("unexpected filters: %+v", svc)
	}
}

func TestDownloadStats_NormalizesDaysBounds(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name          string
		path          string
		expectedDays  int
		expectedBrand string
		check         func(t *testing.T, svc *fakeAdminAnalyticsService)
	}{
		{
			name:          "download errors default invalid to thirty",
			path:          "/admin/v1/analytics/download-errors/stats?days=0&brand=vidcombo",
			expectedDays:  30,
			expectedBrand: "vidcombo",
			check: func(t *testing.T, svc *fakeAdminAnalyticsService) {
				if svc.downloadErrorDays != 30 || svc.downloadErrorBrand != "vidcombo" {
					t.Fatalf("unexpected download-error stats args: days=%d brand=%q", svc.downloadErrorDays, svc.downloadErrorBrand)
				}
			},
		},
		{
			name:          "download stats clamp to max",
			path:          "/admin/v1/analytics/downloads?days=999&brand=ssvid",
			expectedDays:  365,
			expectedBrand: "ssvid",
			check: func(t *testing.T, svc *fakeAdminAnalyticsService) {
				if svc.downloadDays != 365 || svc.downloadBrand != "ssvid" {
					t.Fatalf("unexpected download stats args: days=%d brand=%q", svc.downloadDays, svc.downloadBrand)
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc := &fakeAdminAnalyticsService{}
			handler := &AdminAnalyticsHandler{service: svc}

			router := gin.New()
			router.GET("/admin/v1/analytics/download-errors/stats", handler.DownloadErrorStats)
			router.GET("/admin/v1/analytics/downloads", handler.DownloadStats)

			req := httptest.NewRequest(http.MethodGet, tt.path, nil)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != http.StatusOK {
				t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
			}
			tt.check(t, svc)
		})
	}
}

func TestDailyStats_RejectsInvalidDateRanges(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name         string
		query        string
		expectedCode string
	}{
		{name: "start after end", query: "/admin/v1/analytics/daily?start=2026-04-10&end=2026-04-01", expectedCode: "INVALID_DATE_RANGE"},
		{name: "range too large", query: "/admin/v1/analytics/daily?start=2024-01-01&end=2026-04-01", expectedCode: "DATE_RANGE_TOO_LARGE"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			handler := &AdminAnalyticsHandler{}

			router := gin.New()
			router.GET("/admin/v1/analytics/daily", handler.DailyStats)

			req := httptest.NewRequest(http.MethodGet, tt.query, nil)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
			}

			var envelope analyticsHandlerEnvelope
			if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
				t.Fatalf("unmarshal response: %v", err)
			}
			if envelope.Error == nil || envelope.Error.Code != tt.expectedCode {
				t.Fatalf("expected error code %q, got body: %s", tt.expectedCode, rec.Body.String())
			}
		})
	}
}
