package handler

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/alerts/dto"
	"github.com/snakeloader/backend/internal/alerts/service"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"github.com/snakeloader/backend/internal/pkg/validator"
	"github.com/snakeloader/backend/internal/response"
)

type AdminAlertHandler struct {
	service adminAlertService
}

type adminAlertService interface {
	ListConfigs() ([]dto.AlertConfigResponse, error)
	CreateConfig(req dto.CreateAlertConfigRequest) (*dto.AlertConfigResponse, error)
	GetConfig(id uuid.UUID) (*dto.AlertConfigResponse, error)
	UpdateConfig(id uuid.UUID, req dto.UpdateAlertConfigRequest) (*dto.AlertConfigResponse, error)
	DeleteConfig(id uuid.UUID) error
	TestAlert(id uuid.UUID) error
	ListLogs(page, perPage int, configID *uuid.UUID) ([]dto.AlertLogResponse, int64, error)
}

func NewAdminAlertHandler(svc *service.AlertService) *AdminAlertHandler {
	return &AdminAlertHandler{service: svc}
}

// ListConfigs godoc
// @Summary List alert configurations
// @Tags Admin - Alerts
// @Security BearerAuth
// @Success 200 {object} response.Response "Success"
// @Router /admin/v1/alerts [get]
func (h *AdminAlertHandler) ListConfigs(c *gin.Context) {
	configs, err := h.service.ListConfigs()
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list alert configs")
		return
	}
	response.Success(c, http.StatusOK, configs)
}

// CreateConfig godoc
// @Summary Create alert configuration
// @Tags Admin - Alerts
// @Security BearerAuth
// @Success 201 {object} response.Response "Created"
// @Router /admin/v1/alerts [post]
func (h *AdminAlertHandler) CreateConfig(c *gin.Context) {
	var req dto.CreateAlertConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	config, err := h.service.CreateConfig(req)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to create alert config")
		return
	}
	response.Success(c, http.StatusCreated, config)
}

// GetConfig godoc
// @Summary Get alert configuration
// @Tags Admin - Alerts
// @Security BearerAuth
// @Success 200 {object} response.Response "Success"
// @Router /admin/v1/alerts/{id} [get]
func (h *AdminAlertHandler) GetConfig(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid alert config ID")
		return
	}

	config, err := h.service.GetConfig(id)
	if err != nil {
		if errors.Is(err, service.ErrAlertConfigNotFound) {
			response.Error(c, http.StatusNotFound, "NOT_FOUND", "Alert config not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get alert config")
		return
	}
	response.Success(c, http.StatusOK, config)
}

// UpdateConfig godoc
// @Summary Update alert configuration
// @Tags Admin - Alerts
// @Security BearerAuth
// @Success 200 {object} response.Response "Success"
// @Router /admin/v1/alerts/{id} [patch]
func (h *AdminAlertHandler) UpdateConfig(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid alert config ID")
		return
	}

	var req dto.UpdateAlertConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	config, err := h.service.UpdateConfig(id, req)
	if err != nil {
		if errors.Is(err, service.ErrAlertConfigNotFound) {
			response.Error(c, http.StatusNotFound, "NOT_FOUND", "Alert config not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to update alert config")
		return
	}
	response.Success(c, http.StatusOK, config)
}

// DeleteConfig godoc
// @Summary Delete alert configuration
// @Tags Admin - Alerts
// @Security BearerAuth
// @Success 200 {object} response.Response "Success"
// @Router /admin/v1/alerts/{id} [delete]
func (h *AdminAlertHandler) DeleteConfig(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid alert config ID")
		return
	}

	if err := h.service.DeleteConfig(id); err != nil {
		if errors.Is(err, service.ErrAlertConfigNotFound) {
			response.Error(c, http.StatusNotFound, "NOT_FOUND", "Alert config not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to delete alert config")
		return
	}
	response.Success(c, http.StatusOK, gin.H{"deleted": true})
}

// TestAlert godoc
// @Summary Test alert notification
// @Tags Admin - Alerts
// @Security BearerAuth
// @Success 200 {object} response.Response "Success"
// @Router /admin/v1/alerts/{id}/test [post]
func (h *AdminAlertHandler) TestAlert(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid alert config ID")
		return
	}

	if err := h.service.TestAlert(id); err != nil {
		if errors.Is(err, service.ErrAlertConfigNotFound) {
			response.Error(c, http.StatusNotFound, "NOT_FOUND", "Alert config not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "ALERT_SEND_FAILED", err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"sent": true})
}

// ListLogs godoc
// @Summary List alert logs
// @Tags Admin - Alerts
// @Security BearerAuth
// @Success 200 {object} response.Response "Success"
// @Router /admin/v1/alerts/logs [get]
func (h *AdminAlertHandler) ListLogs(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)

	var configID *uuid.UUID
	if idStr := c.Query("config_id"); idStr != "" {
		parsed, err := uuid.Parse(idStr)
		if err != nil {
			response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid alert config ID")
			return
		}
		configID = &parsed
	}

	logs, total, err := h.service.ListLogs(page, perPage, configID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list alert logs")
		return
	}
	response.Paginated(c, logs, total, page, perPage)
}
