package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/analytics/dto"
	"github.com/snakeloader/backend/internal/analytics/service"
	identitymodel "github.com/snakeloader/backend/internal/identity/model"
	"github.com/snakeloader/backend/internal/middleware"
	"github.com/snakeloader/backend/internal/pkg/validator"
	"github.com/snakeloader/backend/internal/response"
)

// AnalyticsHandler handles device-facing analytics endpoints
type AnalyticsHandler struct {
	service *service.AnalyticsService
}

func NewAnalyticsHandler(svc *service.AnalyticsService) *AnalyticsHandler {
	return &AnalyticsHandler{service: svc}
}

// TrackEvent godoc
// @Summary Track analytics events
// @Description Track one or more analytics events from the device. Events are used to monitor app usage, feature adoption, and user behavior.
// @Tags Analytics
// @Accept json
// @Produce json
// @Param request body dto.TrackEventsRequest true "Events to track (max 50 events per request)"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response "Successfully tracked events with count"
// @Failure 400 {object} response.Response "Validation error - invalid event data"
// @Failure 401 {object} response.Response "Unauthorized - invalid or missing API key"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/analytics/events [post]
func (h *AnalyticsHandler) TrackEvent(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)
	device := getDevice(c)
	os := ""
	appVersion := ""
	if device != nil {
		os = device.OS
		appVersion = device.AppVersion
	}

	var req dto.TrackEventsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	count, err := h.service.TrackEvents(deviceID.(uuid.UUID), os, appVersion, req)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to track events")
		return
	}

	response.Success(c, http.StatusOK, gin.H{"tracked": count})
}

// TrackBootstrapEvent godoc
// @Summary Track bootstrap telemetry
// @Description Record a pre-auth startup or registration event before the device has an API key.
// @Tags Analytics
// @Accept json
// @Produce json
// @Param request body dto.TrackBootstrapEventRequest true "Bootstrap event"
// @Success 200 {object} response.Response "Bootstrap event tracked"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/bootstrap/events [post]
func (h *AnalyticsHandler) TrackBootstrapEvent(c *gin.Context) {
	var req dto.TrackBootstrapEventRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	if err := h.service.TrackBootstrapEvent(req, c.ClientIP(), c.GetHeader("User-Agent")); err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to track bootstrap event")
		return
	}

	response.Success(c, http.StatusOK, gin.H{"tracked": true})
}

// TrackDownloadError godoc
// @Summary Track a download error
// @Description Record a structured download error from the device
// @Tags Analytics
// @Accept json
// @Produce json
// @Param request body dto.TrackDownloadErrorRequest true "Download error data"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response "Download error tracked"
// @Router /api/v1/analytics/download-errors [post]
func (h *AnalyticsHandler) TrackDownloadError(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)
	device := getDevice(c)
	os := ""
	osVersion := ""
	appVersion := ""
	if device != nil {
		os = device.OS
		osVersion = device.OSVersion
		appVersion = device.AppVersion
	}

	var req dto.TrackDownloadErrorRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	if err := h.service.TrackDownloadError(deviceID.(uuid.UUID), os, osVersion, appVersion, req); err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to track download error")
		return
	}

	response.Success(c, http.StatusOK, gin.H{"tracked": true})
}

func getDevice(c *gin.Context) *identitymodel.Device {
	val, exists := c.Get(middleware.DeviceKey)
	if !exists {
		return nil
	}
	device, ok := val.(*identitymodel.Device)
	if !ok {
		return nil
	}
	return device
}
