package response

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func init() {
	gin.SetMode(gin.TestMode)
}

func TestSuccess(t *testing.T) {
	router := gin.New()
	router.GET("/test", func(c *gin.Context) {
		Success(c, http.StatusOK, gin.H{"msg": "hello"})
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp Response
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}

	if !resp.Success {
		t.Error("expected success=true")
	}
	if resp.Error != nil {
		t.Error("expected no error")
	}
}

func TestError(t *testing.T) {
	router := gin.New()
	router.GET("/test", func(c *gin.Context) {
		Error(c, http.StatusNotFound, "NOT_FOUND", "Resource not found")
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}

	var resp Response
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}

	if resp.Success {
		t.Error("expected success=false")
	}
	if resp.Error == nil {
		t.Fatal("expected error info")
	}
	if resp.Error.Code != "NOT_FOUND" {
		t.Errorf("expected code NOT_FOUND, got %s", resp.Error.Code)
	}
	if resp.Error.Message != "Resource not found" {
		t.Errorf("unexpected message: %s", resp.Error.Message)
	}
}

func TestValidationError(t *testing.T) {
	router := gin.New()
	router.POST("/test", func(c *gin.Context) {
		ValidationError(c, map[string]string{
			"email":    "required",
			"password": "too short",
		})
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/test", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422, got %d", w.Code)
	}

	var resp Response
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}

	if resp.Success {
		t.Error("expected success=false")
	}
	if resp.Error.Code != "VALIDATION_ERROR" {
		t.Errorf("expected VALIDATION_ERROR, got %s", resp.Error.Code)
	}
	if len(resp.Error.Details) != 2 {
		t.Errorf("expected 2 detail fields, got %d", len(resp.Error.Details))
	}
}

func TestPaginated(t *testing.T) {
	router := gin.New()
	router.GET("/test", func(c *gin.Context) {
		items := []gin.H{{"id": 1}, {"id": 2}}
		Paginated(c, items, 50, 1, 20)
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var raw map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &raw); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}

	if raw["success"] != true {
		t.Error("expected success=true")
	}

	data := raw["data"].(map[string]interface{})
	if data["total"].(float64) != 50 {
		t.Errorf("expected total=50, got %v", data["total"])
	}
	if data["page"].(float64) != 1 {
		t.Errorf("expected page=1, got %v", data["page"])
	}
	if data["per_page"].(float64) != 20 {
		t.Errorf("expected per_page=20, got %v", data["per_page"])
	}
	if data["total_pages"].(float64) != 3 {
		t.Errorf("expected total_pages=3, got %v", data["total_pages"])
	}
}

func TestPaginated_TotalPages_RoundsUp(t *testing.T) {
	router := gin.New()
	router.GET("/test", func(c *gin.Context) {
		Paginated(c, []gin.H{}, 51, 1, 20)
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	router.ServeHTTP(w, req)

	var raw map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &raw)
	data := raw["data"].(map[string]interface{})

	// 51 items / 20 per page = 3 pages (ceil)
	if data["total_pages"].(float64) != 3 {
		t.Errorf("expected total_pages=3, got %v", data["total_pages"])
	}
}

func TestSuccess_CustomStatus(t *testing.T) {
	router := gin.New()
	router.POST("/test", func(c *gin.Context) {
		Success(c, http.StatusCreated, gin.H{"id": "abc"})
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/test", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d", w.Code)
	}
}
