package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	bugsdto "github.com/snakeloader/backend/internal/bugs/dto"
)

type fakeCrashGroupMergeProvider struct {
	limit           int
	includeResolved bool
	backfillReq     bugsdto.BackfillCrashGroupMergesRequest
}

func (f *fakeCrashGroupMergeProvider) ListCrashGroupMergeCandidates(limit int, includeResolved bool) ([]bugsdto.CrashGroupMergeCandidateResponse, error) {
	f.limit = limit
	f.includeResolved = includeResolved
	return []bugsdto.CrashGroupMergeCandidateResponse{}, nil
}

func (f *fakeCrashGroupMergeProvider) BackfillCrashGroupMerges(req bugsdto.BackfillCrashGroupMergesRequest) (*bugsdto.CrashGroupBackfillMergeReportResponse, error) {
	f.backfillReq = req
	return &bugsdto.CrashGroupBackfillMergeReportResponse{DryRun: true}, nil
}

type bugHandlerEnvelope struct {
	Success bool            `json:"success"`
	Data    json.RawMessage `json:"data"`
	Error   *struct {
		Code string `json:"code"`
	} `json:"error,omitempty"`
}

func TestListCrashGroupMergeCandidates_NormalizesLimitAndParsesIncludeResolved(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name             string
		query            string
		expectedLimit    int
		expectedResolved bool
	}{
		{name: "defaults invalid to two hundred", query: "/admin/v1/crash-groups/merge-candidates?limit=0&include_resolved=TRUE", expectedLimit: 200, expectedResolved: true},
		{name: "clamps oversized to max", query: "/admin/v1/crash-groups/merge-candidates?limit=999", expectedLimit: 500, expectedResolved: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			provider := &fakeCrashGroupMergeProvider{}
			handler := NewAdminBugHandler(nil)
			handler.SetCrashGroupMergeService(provider)

			router := gin.New()
			router.GET("/admin/v1/crash-groups/merge-candidates", handler.ListCrashGroupMergeCandidates)

			req := httptest.NewRequest(http.MethodGet, tt.query, nil)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != http.StatusOK {
				t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
			}
			if provider.limit != tt.expectedLimit {
				t.Fatalf("expected limit %d, got %d", tt.expectedLimit, provider.limit)
			}
			if provider.includeResolved != tt.expectedResolved {
				t.Fatalf("expected include_resolved=%t, got %t", tt.expectedResolved, provider.includeResolved)
			}
		})
	}
}

func TestBackfillCrashGroupMerges_AllowsEmptyBody(t *testing.T) {
	gin.SetMode(gin.TestMode)

	provider := &fakeCrashGroupMergeProvider{}
	handler := NewAdminBugHandler(nil)
	handler.SetCrashGroupMergeService(provider)

	router := gin.New()
	router.POST("/admin/v1/crash-groups/backfill-merge", handler.BackfillCrashGroupMerges)

	req := httptest.NewRequest(http.MethodPost, "/admin/v1/crash-groups/backfill-merge", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if provider.backfillReq != (bugsdto.BackfillCrashGroupMergesRequest{}) {
		t.Fatalf("expected zero-value backfill request, got %+v", provider.backfillReq)
	}
}

func TestBugHandlers_RejectInvalidIDs(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name         string
		method       string
		path         string
		body         []byte
		register     func(router *gin.Engine, handler *AdminBugHandler)
		expectedCode string
	}{
		{
			name:   "get crash group",
			method: http.MethodGet,
			path:   "/admin/v1/crash-groups/not-a-uuid",
			register: func(router *gin.Engine, handler *AdminBugHandler) {
				router.GET("/admin/v1/crash-groups/:id", handler.GetCrashGroup)
			},
			expectedCode: "INVALID_ID",
		},
		{
			name:   "merge crash groups invalid source",
			method: http.MethodPost,
			path:   "/admin/v1/crash-groups/merge",
			body:   []byte(`{"target_id":"11111111-1111-1111-1111-111111111111","source_ids":["bad-id"]}`),
			register: func(router *gin.Engine, handler *AdminBugHandler) {
				router.POST("/admin/v1/crash-groups/merge", handler.MergeCrashGroups)
			},
			expectedCode: "INVALID_ID",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			handler := NewAdminBugHandler(nil)
			router := gin.New()
			tt.register(router, handler)

			req := httptest.NewRequest(tt.method, tt.path, bytes.NewReader(tt.body))
			req.Header.Set("Content-Type", "application/json")
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
			}

			var envelope bugHandlerEnvelope
			if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
				t.Fatalf("unmarshal response: %v", err)
			}
			if envelope.Error == nil || envelope.Error.Code != tt.expectedCode {
				t.Fatalf("expected error code %q, got body: %s", tt.expectedCode, rec.Body.String())
			}
		})
	}
}
