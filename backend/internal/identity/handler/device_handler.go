package handler

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/identity/dto"
	"github.com/snakeloader/backend/internal/identity/service"
	"github.com/snakeloader/backend/internal/middleware"
	"github.com/snakeloader/backend/internal/pkg/crypto"
	"github.com/snakeloader/backend/internal/pkg/validator"
	"github.com/snakeloader/backend/internal/response"
)

type DeviceHandler struct {
	service        *service.DeviceService
	authMiddleware *middleware.AuthMiddleware
}

func NewDeviceHandler(svc *service.DeviceService) *DeviceHandler {
	return &DeviceHandler{service: svc}
}

// SetAuthMiddleware injects the auth middleware for cache invalidation.
func (h *DeviceHandler) SetAuthMiddleware(mw *middleware.AuthMiddleware) {
	h.authMiddleware = mw
}

// Register godoc
// @Summary Register a device
// @Description Register a new device or retrieve existing API key for a device
// @Tags Devices
// @Accept json
// @Produce json
// @Param request body dto.RegisterDeviceRequest true "Device registration data"
// @Success 200 {object} response.Response{data=dto.RegisterResponse} "Existing device"
// @Success 201 {object} response.Response{data=dto.RegisterResponse} "New device registered"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 403 {object} response.Response "Device inactive"
// @Failure 500 {object} response.Response "Internal error"
// @Router /api/v1/devices/register [post]
func (h *DeviceHandler) Register(c *gin.Context) {
	var req dto.RegisterDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	result, err := h.service.RegisterDevice(req, c.ClientIP(), c.GetHeader("User-Agent"))
	if err != nil {
		if errors.Is(err, service.ErrDeviceInactive) {
			response.Error(c, http.StatusForbidden, "DEVICE_INACTIVE", "Device has been deactivated")
			return
		}
		if errors.Is(err, service.ErrRegisterCooldown) {
			response.Error(c, http.StatusTooManyRequests, "REGISTER_COOLDOWN", "Please wait before re-registering")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to register device")
		return
	}

	status := http.StatusOK
	if result.IsNew {
		status = http.StatusCreated
	}
	response.Success(c, status, result)
}

// Heartbeat godoc
// @Summary Send device heartbeat
// @Description Update device last seen time and return server time
// @Tags Devices
// @Accept json
// @Produce json
// @Param request body dto.HeartbeatRequest true "Heartbeat data"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=dto.HeartbeatResponse} "Success"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal error"
// @Router /api/v1/devices/heartbeat [post]
func (h *DeviceHandler) Heartbeat(c *gin.Context) {
	deviceID, exists := c.Get(middleware.DeviceIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "Device not authenticated")
		return
	}

	var req dto.HeartbeatRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	// If brand changed, invalidate auth cache so next request reads fresh brand from DB
	currentBrand, _ := c.Get(middleware.DeviceBrandKey)
	brandChanged := req.Brand != "" && currentBrand != req.Brand

	result, err := h.service.Heartbeat(deviceID.(uuid.UUID), req)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to process heartbeat")
		return
	}

	if brandChanged && h.authMiddleware != nil {
		hash := crypto.HashAPIKey(c.GetHeader("X-API-Key"))
		h.authMiddleware.InvalidateCache(hash)
	}

	response.Success(c, http.StatusOK, result)
}
