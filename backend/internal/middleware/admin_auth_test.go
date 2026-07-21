package middleware

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/identity/model"
	jwtpkg "github.com/snakeloader/backend/internal/pkg/jwt"
)

type fakeAdminLookup struct {
	admin *model.Admin
	err   error
}

func (f *fakeAdminLookup) FindByID(id uuid.UUID) (*model.Admin, error) {
	if f.err != nil {
		return nil, f.err
	}
	if f.admin == nil {
		return nil, errors.New("not found")
	}
	return f.admin, nil
}

type authEnvelope struct {
	Success bool `json:"success"`
	Error   *struct {
		Code string `json:"code"`
	} `json:"error,omitempty"`
}

func TestAdminAuthMiddleware_RequiresToken(t *testing.T) {
	gin.SetMode(gin.TestMode)

	mw := &AdminAuthMiddleware{
		jwtManager: jwtpkg.NewManager("secret", 1),
		adminRepo:  &fakeAdminLookup{},
	}

	router := gin.New()
	router.Use(mw.RequireJWT())
	router.GET("/admin/v1/devices", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/admin/v1/devices", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d: %s", rec.Code, rec.Body.String())
	}

	var envelope authEnvelope
	if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	if envelope.Error == nil || envelope.Error.Code != "MISSING_TOKEN" {
		t.Fatalf("expected MISSING_TOKEN, got body: %s", rec.Body.String())
	}
}

func TestAdminAuthMiddleware_AllowsBearerTokenAndInjectsBrandScope(t *testing.T) {
	gin.SetMode(gin.TestMode)

	adminID := uuid.New()
	manager := jwtpkg.NewManager("secret", 1)
	token, _, err := manager.Generate(adminID, "vidcombo")
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}

	mw := &AdminAuthMiddleware{
		jwtManager: manager,
		adminRepo: &fakeAdminLookup{
			admin: &model.Admin{ID: adminID, Email: "admin@example.com", BrandScope: "vidcombo"},
		},
	}

	router := gin.New()
	router.Use(mw.RequireJWT())
	router.GET("/admin/v1/devices", func(c *gin.Context) {
		if got := c.Query("brand"); got != "vidcombo" {
			t.Fatalf("expected injected brand scope vidcombo, got %q", got)
		}
		if adminIDValue, ok := c.Get(AdminIDKey); !ok || adminIDValue != adminID {
			t.Fatalf("expected admin ID in context, got %#v", adminIDValue)
		}
		c.Status(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/admin/v1/devices?brand=ssvid", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestAdminAuthMiddleware_AllowsQueryTokenForSSE(t *testing.T) {
	gin.SetMode(gin.TestMode)

	adminID := uuid.New()
	manager := jwtpkg.NewManager("secret", 1)
	token, _, err := manager.Generate(adminID)
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}

	mw := &AdminAuthMiddleware{
		jwtManager: manager,
		adminRepo: &fakeAdminLookup{
			admin: &model.Admin{ID: adminID, Email: "admin@example.com"},
		},
	}

	router := gin.New()
	router.Use(mw.RequireJWT())
	router.GET("/admin/v1/notifications/stream", func(c *gin.Context) {
		if got := c.Query("brand"); got != "ssvid" {
			t.Fatalf("expected super-admin query brand to remain ssvid, got %q", got)
		}
		c.Status(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/admin/v1/notifications/stream?token="+token+"&brand=ssvid", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestAdminAuthMiddleware_RejectsInvalidTokenAndMissingAdmin(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name         string
		token        string
		adminRepo    adminLookup
		expectedCode string
	}{
		{
			name:         "invalid token",
			token:        "bad-token",
			adminRepo:    &fakeAdminLookup{},
			expectedCode: "INVALID_TOKEN",
		},
		{
			name: "admin missing",
			adminRepo: &fakeAdminLookup{
				err: errors.New("missing"),
			},
			expectedCode: "INVALID_TOKEN",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			manager := jwtpkg.NewManager("secret", 1)
			token := tt.token
			if token == "" {
				generated, _, err := manager.Generate(uuid.New())
				if err != nil {
					t.Fatalf("generate token: %v", err)
				}
				token = generated
			}

			mw := &AdminAuthMiddleware{
				jwtManager: manager,
				adminRepo:  tt.adminRepo,
			}

			router := gin.New()
			router.Use(mw.RequireJWT())
			router.GET("/admin/v1/devices", func(c *gin.Context) {
				c.Status(http.StatusOK)
			})

			req := httptest.NewRequest(http.MethodGet, "/admin/v1/devices", nil)
			req.Header.Set("Authorization", "Bearer "+token)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != http.StatusUnauthorized {
				t.Fatalf("expected 401, got %d: %s", rec.Code, rec.Body.String())
			}

			var envelope authEnvelope
			if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
				t.Fatalf("unmarshal response: %v", err)
			}
			if envelope.Error == nil || envelope.Error.Code != tt.expectedCode {
				t.Fatalf("expected error code %q, got body: %s", tt.expectedCode, rec.Body.String())
			}
		})
	}
}

func TestSetBrandQuery_ReplacesExistingValue(t *testing.T) {
	raw := setBrandQuery("brand=ssvid&limit=20", "vidcombo")
	if raw != "brand=vidcombo&limit=20" && raw != "limit=20&brand=vidcombo" {
		t.Fatalf("unexpected query string: %q", raw)
	}
}
