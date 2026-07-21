package handler

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/snakeloader/backend/internal/identity/dto"
)

type fakeDashboardStatsProvider struct {
	comprehensiveBrand string
	trendsBrand        string
	trendsDays         int
	comprehensiveResp  *dto.ComprehensiveStatsResponse
	trendsResp         *dto.DashboardTrendsResponse
	brandResp          *dto.BrandComparisonResponse
	err                error
}

func (f *fakeDashboardStatsProvider) GetComprehensiveStats(brand string) (*dto.ComprehensiveStatsResponse, error) {
	f.comprehensiveBrand = brand
	if f.comprehensiveResp == nil {
		f.comprehensiveResp = &dto.ComprehensiveStatsResponse{}
	}
	return f.comprehensiveResp, f.err
}

func (f *fakeDashboardStatsProvider) GetBrandComparison() (*dto.BrandComparisonResponse, error) {
	if f.brandResp == nil {
		f.brandResp = &dto.BrandComparisonResponse{}
	}
	return f.brandResp, f.err
}

func (f *fakeDashboardStatsProvider) GetDashboardTrends(days int, brand string) (*dto.DashboardTrendsResponse, error) {
	f.trendsDays = days
	f.trendsBrand = brand
	if f.trendsResp == nil {
		f.trendsResp = &dto.DashboardTrendsResponse{}
	}
	return f.trendsResp, f.err
}

type fakeActivityFeedProvider struct {
	limit int
	brand string
	resp  *dto.ActivityFeedResponse
	err   error
}

func (f *fakeActivityFeedProvider) GetRecentActivity(limit int, brand string) (*dto.ActivityFeedResponse, error) {
	f.limit = limit
	f.brand = brand
	if f.resp == nil {
		f.resp = &dto.ActivityFeedResponse{}
	}
	return f.resp, f.err
}

type fakeTopCustomersProvider struct {
	limit int
	brand string
	resp  *dto.TopCustomersResponse
	err   error
}

func (f *fakeTopCustomersProvider) GetTopCustomers(limit int, brand string) (*dto.TopCustomersResponse, error) {
	f.limit = limit
	f.brand = brand
	if f.resp == nil {
		f.resp = &dto.TopCustomersResponse{}
	}
	return f.resp, f.err
}

type handlerEnvelope struct {
	Success bool            `json:"success"`
	Data    json.RawMessage `json:"data"`
	Error   *struct {
		Code string `json:"code"`
	} `json:"error,omitempty"`
}

func TestComprehensiveStats_PassesBrandAndReturnsPayload(t *testing.T) {
	gin.SetMode(gin.TestMode)

	provider := &fakeDashboardStatsProvider{
		comprehensiveResp: &dto.ComprehensiveStatsResponse{
			TotalDevices: 123,
			ActiveToday:  45,
		},
	}
	handler := NewAdminDeviceHandler(nil)
	handler.SetComprehensiveService(provider)

	router := gin.New()
	router.GET("/admin/v1/dashboard/comprehensive", handler.ComprehensiveStats)

	req := httptest.NewRequest(http.MethodGet, "/admin/v1/dashboard/comprehensive?brand=vidcombo", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if provider.comprehensiveBrand != "vidcombo" {
		t.Fatalf("expected brand vidcombo, got %q", provider.comprehensiveBrand)
	}

	var envelope handlerEnvelope
	if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	if !envelope.Success {
		t.Fatalf("expected success response, got body: %s", rec.Body.String())
	}

	var payload dto.ComprehensiveStatsResponse
	if err := json.Unmarshal(envelope.Data, &payload); err != nil {
		t.Fatalf("unmarshal payload: %v", err)
	}
	if payload.TotalDevices != 123 || payload.ActiveToday != 45 {
		t.Fatalf("unexpected payload: %+v", payload)
	}
}

func TestDashboardTrends_NormalizesDaysBounds(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name     string
		query    string
		expected int
	}{
		{"default on zero", "/admin/v1/dashboard/trends?days=0&brand=ssvid", 7},
		{"clamp to max", "/admin/v1/dashboard/trends?days=999&brand=vidcombo", 365},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			provider := &fakeDashboardStatsProvider{
				trendsResp: &dto.DashboardTrendsResponse{Days: tt.expected},
			}
			handler := NewAdminDeviceHandler(nil)
			handler.SetComprehensiveService(provider)

			router := gin.New()
			router.GET("/admin/v1/dashboard/trends", handler.DashboardTrends)

			req := httptest.NewRequest(http.MethodGet, tt.query, nil)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != http.StatusOK {
				t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
			}
			if provider.trendsDays != tt.expected {
				t.Fatalf("expected normalized days %d, got %d", tt.expected, provider.trendsDays)
			}
		})
	}
}

func TestDashboardActivity_NormalizesLimitAndPassesBrand(t *testing.T) {
	gin.SetMode(gin.TestMode)

	provider := &fakeActivityFeedProvider{
		resp: &dto.ActivityFeedResponse{
			Events: []dto.TimelineEvent{{Type: "transaction"}},
		},
	}
	handler := NewAdminDeviceHandler(nil)
	handler.SetActivityFeedService(provider)

	router := gin.New()
	router.GET("/admin/v1/dashboard/activity", handler.DashboardActivity)

	req := httptest.NewRequest(http.MethodGet, "/admin/v1/dashboard/activity?limit=999&brand=ssvid", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if provider.limit != 200 {
		t.Fatalf("expected limit clamped to 200, got %d", provider.limit)
	}
	if provider.brand != "ssvid" {
		t.Fatalf("expected brand ssvid, got %q", provider.brand)
	}
}

func TestDashboardTopCustomers_DefaultsLimitWhenInvalid(t *testing.T) {
	gin.SetMode(gin.TestMode)

	provider := &fakeTopCustomersProvider{
		resp: &dto.TopCustomersResponse{
			Customers: []dto.TopCustomerSummary{{ContactEmail: "a@example.com"}},
		},
	}
	handler := NewAdminDeviceHandler(nil)
	handler.SetTopCustomersService(provider)

	router := gin.New()
	router.GET("/admin/v1/dashboard/top-customers", handler.DashboardTopCustomers)

	req := httptest.NewRequest(http.MethodGet, "/admin/v1/dashboard/top-customers?limit=0&brand=vidcombo", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if provider.limit != 10 {
		t.Fatalf("expected invalid limit to fall back to 10, got %d", provider.limit)
	}
	if provider.brand != "vidcombo" {
		t.Fatalf("expected brand vidcombo, got %q", provider.brand)
	}
}

func TestComprehensiveStats_PropagatesServiceFailure(t *testing.T) {
	gin.SetMode(gin.TestMode)

	handler := NewAdminDeviceHandler(nil)
	handler.SetComprehensiveService(&fakeDashboardStatsProvider{err: errors.New("boom")})

	router := gin.New()
	router.GET("/admin/v1/dashboard/comprehensive", handler.ComprehensiveStats)

	req := httptest.NewRequest(http.MethodGet, "/admin/v1/dashboard/comprehensive", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d: %s", rec.Code, rec.Body.String())
	}

	var envelope handlerEnvelope
	if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
		t.Fatalf("unmarshal error response: %v", err)
	}
	if envelope.Success {
		t.Fatalf("expected failure response, got body: %s", rec.Body.String())
	}
	if envelope.Error == nil || envelope.Error.Code != "INTERNAL_ERROR" {
		t.Fatalf("unexpected error envelope: %+v", envelope.Error)
	}
}
