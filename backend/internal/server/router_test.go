package server

import (
	"io/fs"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/fstest"
	"time"

	"github.com/gin-gonic/gin"
	alerthandler "github.com/snakeloader/backend/internal/alerts/handler"
	analyticshandler "github.com/snakeloader/backend/internal/analytics/handler"
	assistanthandler "github.com/snakeloader/backend/internal/assistant/handler"
	bughandler "github.com/snakeloader/backend/internal/bugs/handler"
	feedbackhandler "github.com/snakeloader/backend/internal/feedback/handler"
	identityhandler "github.com/snakeloader/backend/internal/identity/handler"
	"github.com/snakeloader/backend/internal/middleware"
	jwtpkg "github.com/snakeloader/backend/internal/pkg/jwt"
	premiumhandler "github.com/snakeloader/backend/internal/premium/handler"
	producthandler "github.com/snakeloader/backend/internal/product/handler"
)

func TestRegisterRoutes_AdminRoutesKeepPublicLoginAndProtectedEndpoints(t *testing.T) {
	gin.SetMode(gin.TestMode)

	engine := New(gin.TestMode, nil)
	RegisterRoutes(engine, RouterDeps{
		DeviceHandler:         new(identityhandler.DeviceHandler),
		AdminAuthHandler:      new(identityhandler.AdminAuthHandler),
		AdminDeviceHandler:    new(identityhandler.AdminDeviceHandler),
		BugHandler:            new(bughandler.BugHandler),
		AdminBugHandler:       new(bughandler.AdminBugHandler),
		ProductHandler:        new(producthandler.ProductHandler),
		AdminProductHandler:   new(producthandler.AdminProductHandler),
		CIReleaseHandler:      new(producthandler.CIReleaseHandler),
		FeedbackHandler:       new(feedbackhandler.FeedbackHandler),
		AdminFeedbackHandler:  new(feedbackhandler.AdminFeedbackHandler),
		AssistantHandler:      new(assistanthandler.AssistantHandler),
		AdminAssistantHandler: new(assistanthandler.AdminAssistantHandler),
		AnalyticsHandler:      new(analyticshandler.AnalyticsHandler),
		AdminAnalyticsHandler: new(analyticshandler.AdminAnalyticsHandler),
		PremiumHandler:        new(premiumhandler.PremiumHandler),
		AdminPremiumHandler:   new(premiumhandler.AdminPremiumHandler),
		WebhookHandler:        new(premiumhandler.WebhookHandler),
		AdminAlertHandler:     new(alerthandler.AdminAlertHandler),
		AdminAuditHandler:     new(identityhandler.AdminAuditHandler),
		AuthMiddleware:        middleware.NewAuthMiddleware(nil, nil),
		AdminAuthMW:           middleware.NewAdminAuthMiddleware(jwtpkg.NewManager("secret", 1), nil),
	}, time.Now())

	loginReq := httptest.NewRequest(http.MethodPost, "/admin/v1/auth/login", strings.NewReader(``))
	loginReq.Header.Set("Content-Type", "application/json")
	loginRec := httptest.NewRecorder()
	engine.ServeHTTP(loginRec, loginReq)

	if loginRec.Code == http.StatusUnauthorized {
		t.Fatalf("expected public admin login route to bypass JWT auth, got 401: %s", loginRec.Body.String())
	}

	devicesReq := httptest.NewRequest(http.MethodGet, "/admin/v1/devices", nil)
	devicesRec := httptest.NewRecorder()
	engine.ServeHTTP(devicesRec, devicesReq)

	if devicesRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected protected admin route to require JWT, got %d: %s", devicesRec.Code, devicesRec.Body.String())
	}
	if !strings.Contains(devicesRec.Body.String(), "MISSING_TOKEN") {
		t.Fatalf("expected MISSING_TOKEN response, got: %s", devicesRec.Body.String())
	}
}

func TestNewSPAHandler_ServesAssetsAndFallsBackToIndex(t *testing.T) {
	gin.SetMode(gin.TestMode)

	fsys := fstest.MapFS{
		"index.html":            &fstest.MapFile{Data: []byte("<html>admin</html>")},
		"assets/app.js":         &fstest.MapFile{Data: []byte("console.log('ok');")},
		"nested/chunk/index.js": &fstest.MapFile{Data: []byte("export default 1;")},
	}

	engine := gin.New()
	engine.GET("/dashboard-ui", newSPAHandler(fsys))
	engine.GET("/dashboard-ui/*filepath", newSPAHandler(fsys))

	tests := []struct {
		name         string
		path         string
		expectedCode int
		contains     string
	}{
		{name: "root serves index", path: "/dashboard-ui", expectedCode: http.StatusOK, contains: "<html>admin</html>"},
		{name: "existing asset served", path: "/dashboard-ui/assets/app.js", expectedCode: http.StatusOK, contains: "console.log('ok');"},
		{name: "missing asset falls back to index", path: "/dashboard-ui/missing.js", expectedCode: http.StatusOK, contains: "<html>admin</html>"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, tt.path, nil)
			rec := httptest.NewRecorder()
			engine.ServeHTTP(rec, req)

			if rec.Code != tt.expectedCode {
				t.Fatalf("expected %d, got %d: %s", tt.expectedCode, rec.Code, rec.Body.String())
			}
			if !strings.Contains(rec.Body.String(), tt.contains) {
				t.Fatalf("expected response to contain %q, got %q", tt.contains, rec.Body.String())
			}
		})
	}
}

func TestNewSPAHandler_Returns404WithoutIndex(t *testing.T) {
	gin.SetMode(gin.TestMode)

	engine := gin.New()
	engine.GET("/dashboard-ui/*filepath", newSPAHandler(fstest.MapFS{
		"assets/app.js": &fstest.MapFile{Data: []byte("ok")},
	}))

	req := httptest.NewRequest(http.MethodGet, "/dashboard-ui/missing.js", nil)
	rec := httptest.NewRecorder()
	engine.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "Admin dashboard not found") {
		t.Fatalf("unexpected body: %s", rec.Body.String())
	}
}

var _ fs.FS = fstest.MapFS{}
