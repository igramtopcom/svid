package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	premiumdto "github.com/snakeloader/backend/internal/premium/dto"
	premiumservice "github.com/snakeloader/backend/internal/premium/service"
)

type fakeAdminPremiumFinanceProvider struct {
	revenueDays  int
	revenueBrand string
	auditToken   string
	mrrMonths    int
	mrrBrand     string
}

func (f *fakeAdminPremiumFinanceProvider) GetRevenueReport(days int, brand string) (*premiumdto.RevenueReportResponse, error) {
	f.revenueDays = days
	f.revenueBrand = brand
	return &premiumdto.RevenueReportResponse{TotalRevenue: 12345}, nil
}

func (f *fakeAdminPremiumFinanceProvider) AuditInvoicesViaAdmin(confirmToken string) (*premiumservice.InvoiceAuditReport, error) {
	f.auditToken = confirmToken
	return &premiumservice.InvoiceAuditReport{DryRun: true, TotalScanned: 3}, nil
}

func (f *fakeAdminPremiumFinanceProvider) GetMRRTrend(months int, brand string) ([]premiumdto.MRRPoint, error) {
	f.mrrMonths = months
	f.mrrBrand = brand
	return []premiumdto.MRRPoint{{Month: "2026-04", AmountCents: 799}}, nil
}

type premiumHandlerEnvelope struct {
	Success bool            `json:"success"`
	Data    json.RawMessage `json:"data"`
	Error   *struct {
		Code string `json:"code"`
	} `json:"error,omitempty"`
}

func TestRevenueReport_NormalizesDaysAndPassesBrand(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name          string
		query         string
		expectedDays  int
		expectedBrand string
	}{
		{name: "defaults invalid to thirty", query: "/admin/v1/finance/revenue?days=0&brand=vidcombo", expectedDays: 30, expectedBrand: "vidcombo"},
		{name: "clamps oversized to max", query: "/admin/v1/finance/revenue?days=999&brand=svid", expectedDays: 365, expectedBrand: "svid"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			finance := &fakeAdminPremiumFinanceProvider{}
			handler := NewAdminPremiumHandler(nil)
			handler.SetFinanceService(finance)

			router := gin.New()
			router.GET("/admin/v1/finance/revenue", handler.RevenueReport)

			req := httptest.NewRequest(http.MethodGet, tt.query, nil)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != http.StatusOK {
				t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
			}
			if finance.revenueDays != tt.expectedDays {
				t.Fatalf("expected days %d, got %d", tt.expectedDays, finance.revenueDays)
			}
			if finance.revenueBrand != tt.expectedBrand {
				t.Fatalf("expected brand %q, got %q", tt.expectedBrand, finance.revenueBrand)
			}
		})
	}
}

func TestMRRTrend_NormalizesMonthsAndPassesBrand(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name           string
		query          string
		expectedMonths int
		expectedBrand  string
	}{
		{name: "defaults invalid to twelve", query: "/admin/v1/subscriptions/mrr-trend?months=0&brand=vidcombo", expectedMonths: 12, expectedBrand: "vidcombo"},
		{name: "clamps oversized to max", query: "/admin/v1/subscriptions/mrr-trend?months=99&brand=svid", expectedMonths: 36, expectedBrand: "svid"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			finance := &fakeAdminPremiumFinanceProvider{}
			handler := NewAdminPremiumHandler(nil)
			handler.SetFinanceService(finance)

			router := gin.New()
			router.GET("/admin/v1/subscriptions/mrr-trend", handler.MRRTrend)

			req := httptest.NewRequest(http.MethodGet, tt.query, nil)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != http.StatusOK {
				t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
			}
			if finance.mrrMonths != tt.expectedMonths {
				t.Fatalf("expected months %d, got %d", tt.expectedMonths, finance.mrrMonths)
			}
			if finance.mrrBrand != tt.expectedBrand {
				t.Fatalf("expected brand %q, got %q", tt.expectedBrand, finance.mrrBrand)
			}
		})
	}
}

func TestAuditInvoices_AllowsEmptyBodyAndDefaultsToDryRunToken(t *testing.T) {
	gin.SetMode(gin.TestMode)

	finance := &fakeAdminPremiumFinanceProvider{}
	handler := NewAdminPremiumHandler(nil)
	handler.SetFinanceService(finance)

	router := gin.New()
	router.POST("/admin/v1/premium/invoices/audit", handler.AuditInvoices)

	req := httptest.NewRequest(http.MethodPost, "/admin/v1/premium/invoices/audit", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if finance.auditToken != "" {
		t.Fatalf("expected empty confirm token for dry-run, got %q", finance.auditToken)
	}
}

func TestPremiumHandlers_RejectInvalidIDs(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name         string
		method       string
		path         string
		register     func(router *gin.Engine, handler *AdminPremiumHandler)
		expectedCode string
	}{
		{
			name:   "get license",
			method: http.MethodGet,
			path:   "/admin/v1/licenses/not-a-uuid",
			register: func(router *gin.Engine, handler *AdminPremiumHandler) {
				router.GET("/admin/v1/licenses/:id", handler.GetLicense)
			},
			expectedCode: "INVALID_ID",
		},
		{
			name:   "refund transaction",
			method: http.MethodPost,
			path:   "/admin/v1/transactions/not-a-uuid/refund",
			register: func(router *gin.Engine, handler *AdminPremiumHandler) {
				router.POST("/admin/v1/transactions/:id/refund", handler.RefundTransaction)
			},
			expectedCode: "INVALID_ID",
		},
		{
			name:   "get transaction",
			method: http.MethodGet,
			path:   "/admin/v1/transactions/not-a-uuid",
			register: func(router *gin.Engine, handler *AdminPremiumHandler) {
				router.GET("/admin/v1/transactions/:id", handler.GetTransaction)
			},
			expectedCode: "INVALID_ID",
		},
		{
			name:   "get invoice",
			method: http.MethodGet,
			path:   "/admin/v1/invoices/not-a-uuid",
			register: func(router *gin.Engine, handler *AdminPremiumHandler) {
				router.GET("/admin/v1/invoices/:id", handler.GetInvoice)
			},
			expectedCode: "INVALID_ID",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			handler := NewAdminPremiumHandler(nil)
			router := gin.New()
			tt.register(router, handler)

			req := httptest.NewRequest(tt.method, tt.path, nil)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
			}

			var envelope premiumHandlerEnvelope
			if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
				t.Fatalf("unmarshal response: %v", err)
			}
			if envelope.Error == nil || envelope.Error.Code != tt.expectedCode {
				t.Fatalf("expected error code %q, got body: %s", tt.expectedCode, rec.Body.String())
			}
		})
	}
}
