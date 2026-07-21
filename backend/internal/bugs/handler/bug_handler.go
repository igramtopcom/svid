package handler

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/bugs/dto"
	"github.com/snakeloader/backend/internal/bugs/service"
	"github.com/snakeloader/backend/internal/middleware"
	"github.com/snakeloader/backend/internal/pkg/validator"
	"github.com/snakeloader/backend/internal/response"
)

type BugHandler struct {
	service *service.BugService
}

func NewBugHandler(svc *service.BugService) *BugHandler {
	return &BugHandler{service: svc}
}

// SubmitCrash godoc
// @Summary Submit crash report
// @Description Submit an automatic crash report from the application
// @Tags Bug Reports
// @Accept json
// @Produce json
// @Param request body dto.SubmitCrashRequest true "Crash data"
// @Security ApiKeyAuth
// @Success 201 {object} response.Response{data=dto.CrashResponse} "Created"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal error"
// @Router /api/v1/crashes [post]
func (h *BugHandler) SubmitCrash(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

	var req dto.SubmitCrashRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	result, err := h.service.SubmitCrash(deviceID.(uuid.UUID), req)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to submit crash report")
		return
	}

	response.Success(c, http.StatusCreated, result)
}

// SubmitBug godoc
// @Summary Submit bug report
// @Description Submit a user-reported bug with optional attachments
// @Tags Bug Reports
// @Accept json
// @Produce json
// @Param request body dto.SubmitBugRequest true "Bug report data"
// @Security ApiKeyAuth
// @Success 201 {object} response.Response{data=dto.BugResponse} "Created"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal error"
// @Router /api/v1/bugs [post]
func (h *BugHandler) SubmitBug(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

	var req dto.SubmitBugRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	result, err := h.service.SubmitBug(deviceID.(uuid.UUID), req)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to submit bug report")
		return
	}

	response.Success(c, http.StatusCreated, result)
}

// GetMyBugs godoc
// @Summary Get my bug reports
// @Description List bug reports submitted by the current device
// @Tags Bug Reports
// @Accept json
// @Produce json
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=[]dto.BugResponse} "Success"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal error"
// @Router /api/v1/bugs [get]
func (h *BugHandler) GetMyBugs(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

	bugs, err := h.service.ListDeviceBugs(deviceID.(uuid.UUID))
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list bugs")
		return
	}

	// Strip admin-only fields from device-facing response
	for i := range bugs {
		bugs[i].AdminNotes = ""
	}

	response.Success(c, http.StatusOK, bugs)
}

// GetBugStatus godoc
// @Summary Get bug report status
// @Description Get the current status of a specific bug report
// @Tags Bug Reports
// @Accept json
// @Produce json
// @Param id path string true "Bug UUID"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=dto.BugResponse} "Success"
// @Failure 400 {object} response.Response "Invalid ID"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Bug not found"
// @Failure 500 {object} response.Response "Internal error"
// @Router /api/v1/bugs/{id} [get]
func (h *BugHandler) GetBugStatus(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid bug ID format")
		return
	}

	bug, err := h.service.GetDeviceBug(id, deviceID.(uuid.UUID))
	if err != nil {
		if errors.Is(err, service.ErrBugNotFound) {
			response.Error(c, http.StatusNotFound, "BUG_NOT_FOUND", "Bug report not found")
			return
		}
		if errors.Is(err, service.ErrBugAccessDenied) {
			response.Error(c, http.StatusForbidden, "ACCESS_DENIED", "You do not have access to this bug report")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get bug report")
		return
	}

	// Strip admin-only fields from device-facing response
	bug.AdminNotes = ""

	response.Success(c, http.StatusOK, bug)
}
