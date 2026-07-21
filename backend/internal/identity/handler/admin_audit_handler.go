package handler

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/snakeloader/backend/internal/identity/model"
	"github.com/snakeloader/backend/internal/identity/repository"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"github.com/snakeloader/backend/internal/response"
)

type AdminAuditHandler struct {
	repo auditLogLister
}

type auditLogLister interface {
	List(page, perPage int, adminID, action, resourceType string, dateFrom, dateTo *time.Time) ([]model.AuditLog, int64, error)
}

func NewAdminAuditHandler(repo *repository.AuditLogRepository) *AdminAuditHandler {
	return &AdminAuditHandler{repo: repo}
}

func (h *AdminAuditHandler) ListAuditLogs(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "30"))
	page, perPage = pagination.Normalize(page, perPage, 30)

	var dateFrom, dateTo *time.Time
	if df := c.Query("date_from"); df != "" {
		t, err := time.Parse("2006-01-02", df)
		if err != nil {
			response.Error(c, http.StatusBadRequest, "INVALID_DATE", "Invalid date_from format (use YYYY-MM-DD)")
			return
		}
		dateFrom = &t
	}
	if dt := c.Query("date_to"); dt != "" {
		t, err := time.Parse("2006-01-02", dt)
		if err != nil {
			response.Error(c, http.StatusBadRequest, "INVALID_DATE", "Invalid date_to format (use YYYY-MM-DD)")
			return
		}
		end := t.Add(24*time.Hour - time.Second)
		dateTo = &end
	}
	if dateFrom != nil && dateTo != nil && dateFrom.After(*dateTo) {
		response.Error(c, http.StatusBadRequest, "INVALID_DATE_RANGE", "date_from must be before or equal to date_to")
		return
	}

	logs, total, err := h.repo.List(
		page, perPage,
		c.Query("admin_id"),
		c.Query("action"),
		c.Query("resource_type"),
		dateFrom, dateTo,
	)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list audit logs")
		return
	}

	type AuditLogResponse struct {
		ID           string `json:"id"`
		AdminID      string `json:"admin_id"`
		AdminEmail   string `json:"admin_email"`
		Action       string `json:"action"`
		ResourceType string `json:"resource_type"`
		ResourceID   string `json:"resource_id"`
		Path         string `json:"path"`
		RequestBody  string `json:"request_body,omitempty"`
		StatusCode   int    `json:"status_code"`
		IPAddress    string `json:"ip_address"`
		CreatedAt    string `json:"created_at"`
	}

	items := make([]AuditLogResponse, len(logs))
	for i, l := range logs {
		items[i] = AuditLogResponse{
			ID:           l.ID.String(),
			AdminID:      l.AdminID.String(),
			AdminEmail:   l.AdminEmail,
			Action:       l.Action,
			ResourceType: l.ResourceType,
			ResourceID:   l.ResourceID,
			Path:         l.Path,
			RequestBody:  l.RequestBody,
			StatusCode:   l.StatusCode,
			IPAddress:    l.IPAddress,
			CreatedAt:    l.CreatedAt.Format(time.RFC3339),
		}
	}

	response.Paginated(c, items, total, page, perPage)
}
