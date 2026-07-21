package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/snakeloader/backend/internal/identity/model"
	"github.com/snakeloader/backend/internal/middleware"
	"github.com/snakeloader/backend/internal/product/service"
	"github.com/snakeloader/backend/internal/response"
)

// ProductHandler handles device-facing product control endpoints
type ProductHandler struct {
	service *service.ProductService
}

func NewProductHandler(svc *service.ProductService) *ProductHandler {
	return &ProductHandler{service: svc}
}

// GetFlags godoc
// @Summary Get feature flags for device
// @Description Returns all active feature flags applicable to the device based on tier and platform
// @Tags Product - Flags
// @Accept json
// @Produce json
// @Security ApiKeyAuth
// @Success 200 {object} response.Response "Feature flags retrieved successfully"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing API key"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/config/flags [get]
func (h *ProductHandler) GetFlags(c *gin.Context) {
	device := getDevice(c)
	tier := "free"
	platform := ""
	if device != nil {
		tier = device.Tier
		platform = device.OS
	}

	flags, err := h.service.GetDeviceFlags(tier, platform)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get feature flags")
		return
	}

	response.Success(c, http.StatusOK, flags)
}

// GetConfig godoc
// @Summary Get remote configuration
// @Description Returns all active remote configuration key-value pairs for the device
// @Tags Product - Config
// @Accept json
// @Produce json
// @Security ApiKeyAuth
// @Success 200 {object} response.Response "Remote config retrieved successfully"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing API key"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/config/remote [get]
func (h *ProductHandler) GetConfig(c *gin.Context) {
	configs, err := h.service.GetDeviceConfig()
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get remote config")
		return
	}

	response.Success(c, http.StatusOK, configs)
}

// CheckUpdate godoc
// @Summary Check for app updates
// @Description Checks if a newer version of the app is available for the specified platform and channel. Public endpoint (release metadata only); brand is resolved from query param, falling back to device context when present.
// @Tags Product - Releases
// @Accept json
// @Produce json
// @Param platform query string true "Device platform (e.g., windows, macos, linux)"
// @Param version query string true "Current app version (semantic versioning)"
// @Param channel query string false "Release channel (stable, beta, alpha)" default(stable)
// @Param brand query string false "Brand (svid, vidcombo). Falls back to authenticated device's brand or 'svid'."
// @Success 200 {object} response.Response "Update check result with available version info"
// @Failure 400 {object} response.Response "Missing required parameters"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/updates/check [get]
func (h *ProductHandler) CheckUpdate(c *gin.Context) {
	platform := c.Query("platform")
	version := c.Query("version")
	channel := c.DefaultQuery("channel", "stable")

	// Determine brand: explicit param > device's registered brand > default "svid".
	// v1.6.0 VidCombo clients don't send brand param, so we fall back to the
	// brand the device registered with during heartbeat/registration.
	brand := c.Query("brand")
	if brand == "" {
		if device := getDevice(c); device != nil && device.Brand != "" {
			brand = device.Brand
		} else {
			brand = "svid"
		}
	}

	if platform == "" || version == "" {
		response.Error(c, http.StatusBadRequest, "MISSING_PARAMS", "platform and version are required query parameters")
		return
	}

	result, err := h.service.CheckForUpdate(platform, version, channel, brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to check for updates")
		return
	}

	response.Success(c, http.StatusOK, result)
}

// GetAnnouncements godoc
// @Summary Get active announcements
// @Description Returns all active announcements applicable to the device based on tier and platform
// @Tags Product - Announcements
// @Accept json
// @Produce json
// @Security ApiKeyAuth
// @Success 200 {object} response.Response "Announcements retrieved successfully"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing API key"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/announcements [get]
func (h *ProductHandler) GetAnnouncements(c *gin.Context) {
	device := getDevice(c)
	tier := "free"
	platform := ""
	if device != nil {
		tier = device.Tier
		platform = device.OS
	}

	announcements, err := h.service.GetDeviceAnnouncements(tier, platform)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get announcements")
		return
	}

	response.Success(c, http.StatusOK, announcements)
}

func getDevice(c *gin.Context) *model.Device {
	val, exists := c.Get(middleware.DeviceKey)
	if !exists {
		return nil
	}
	device, ok := val.(*model.Device)
	if !ok {
		return nil
	}
	return device
}
