package handler

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"github.com/snakeloader/backend/internal/pkg/validator"
	"github.com/snakeloader/backend/internal/product/dto"
	"github.com/snakeloader/backend/internal/product/service"
	"github.com/snakeloader/backend/internal/response"
)

// AdminProductHandler handles admin-facing product control endpoints
type AdminProductHandler struct {
	service *service.ProductService
}

func NewAdminProductHandler(svc *service.ProductService) *AdminProductHandler {
	return &AdminProductHandler{service: svc}
}

// ==================== Feature Flags ====================

// ListFlags godoc
// @Summary List all feature flags
// @Description Returns all feature flags with their configurations
// @Tags Admin - Flags
// @Accept json
// @Produce json
// @Security BearerAuth
// @Success 200 {object} response.Response "Feature flags list retrieved successfully"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/flags [get]
func (h *AdminProductHandler) ListFlags(c *gin.Context) {
	flags, err := h.service.ListFeatureFlags()
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list feature flags")
		return
	}

	response.Success(c, http.StatusOK, flags)
}

// CreateFlag godoc
// @Summary Create a new feature flag
// @Description Creates a new feature flag with the specified configuration
// @Tags Admin - Flags
// @Accept json
// @Produce json
// @Param request body dto.CreateFeatureFlagRequest true "Feature flag creation request"
// @Security BearerAuth
// @Success 201 {object} response.Response "Feature flag created successfully"
// @Failure 400 {object} response.Response "Invalid request body"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 409 {object} response.Response "Feature flag with this key already exists"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/flags [post]
func (h *AdminProductHandler) CreateFlag(c *gin.Context) {
	var req dto.CreateFeatureFlagRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	flag, err := h.service.CreateFeatureFlag(req)
	if err != nil {
		if errors.Is(err, service.ErrDuplicateKey) {
			response.Error(c, http.StatusConflict, "DUPLICATE_KEY", "A feature flag with this key already exists")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to create feature flag")
		return
	}

	response.Success(c, http.StatusCreated, flag)
}

// GetFlag godoc
// @Summary Get a feature flag by ID
// @Description Returns a single feature flag by its UUID
// @Tags Admin - Flags
// @Accept json
// @Produce json
// @Param id path string true "Feature flag UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response "Feature flag retrieved successfully"
// @Failure 400 {object} response.Response "Invalid feature flag ID format"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 404 {object} response.Response "Feature flag not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/flags/{id} [get]
func (h *AdminProductHandler) GetFlag(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid feature flag ID format")
		return
	}

	flag, err := h.service.GetFeatureFlag(id)
	if err != nil {
		if errors.Is(err, service.ErrFeatureFlagNotFound) {
			response.Error(c, http.StatusNotFound, "FLAG_NOT_FOUND", "Feature flag not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get feature flag")
		return
	}

	response.Success(c, http.StatusOK, flag)
}

// UpdateFlag godoc
// @Summary Update a feature flag
// @Description Updates an existing feature flag with the provided fields
// @Tags Admin - Flags
// @Accept json
// @Produce json
// @Param id path string true "Feature flag UUID"
// @Param request body dto.UpdateFeatureFlagRequest true "Feature flag update request"
// @Security BearerAuth
// @Success 200 {object} response.Response "Feature flag updated successfully"
// @Failure 400 {object} response.Response "Invalid request body or ID format"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 404 {object} response.Response "Feature flag not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/flags/{id} [patch]
func (h *AdminProductHandler) UpdateFlag(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid feature flag ID format")
		return
	}

	var req dto.UpdateFeatureFlagRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	flag, err := h.service.UpdateFeatureFlag(id, req)
	if err != nil {
		if errors.Is(err, service.ErrFeatureFlagNotFound) {
			response.Error(c, http.StatusNotFound, "FLAG_NOT_FOUND", "Feature flag not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to update feature flag")
		return
	}

	response.Success(c, http.StatusOK, flag)
}

// DeleteFlag godoc
// @Summary Delete a feature flag
// @Description Permanently deletes a feature flag by its UUID
// @Tags Admin - Flags
// @Accept json
// @Produce json
// @Param id path string true "Feature flag UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response "Feature flag deleted successfully"
// @Failure 400 {object} response.Response "Invalid feature flag ID format"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 404 {object} response.Response "Feature flag not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/flags/{id} [delete]
func (h *AdminProductHandler) DeleteFlag(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid feature flag ID format")
		return
	}

	if err := h.service.DeleteFeatureFlag(id); err != nil {
		if errors.Is(err, service.ErrFeatureFlagNotFound) {
			response.Error(c, http.StatusNotFound, "FLAG_NOT_FOUND", "Feature flag not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to delete feature flag")
		return
	}

	response.Success(c, http.StatusOK, gin.H{"deleted": true})
}

// ==================== Remote Config ====================

// ListConfigs godoc
// @Summary List all remote configs
// @Description Returns all remote configuration key-value pairs
// @Tags Admin - Config
// @Accept json
// @Produce json
// @Security BearerAuth
// @Success 200 {object} response.Response "Remote configs list retrieved successfully"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/config [get]
func (h *AdminProductHandler) ListConfigs(c *gin.Context) {
	configs, err := h.service.ListRemoteConfigs()
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list remote configs")
		return
	}

	response.Success(c, http.StatusOK, configs)
}

// CreateConfig godoc
// @Summary Create a new remote config
// @Description Creates a new remote configuration key-value pair
// @Tags Admin - Config
// @Accept json
// @Produce json
// @Param request body dto.CreateRemoteConfigRequest true "Remote config creation request"
// @Security BearerAuth
// @Success 201 {object} response.Response "Remote config created successfully"
// @Failure 400 {object} response.Response "Invalid request body"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 409 {object} response.Response "Config with this key already exists"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/config [post]
func (h *AdminProductHandler) CreateConfig(c *gin.Context) {
	var req dto.CreateRemoteConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	cfg, err := h.service.CreateRemoteConfig(req)
	if err != nil {
		if errors.Is(err, service.ErrDuplicateKey) {
			response.Error(c, http.StatusConflict, "DUPLICATE_KEY", "A config with this key already exists")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to create remote config")
		return
	}

	response.Success(c, http.StatusCreated, cfg)
}

// GetConfig godoc
// @Summary Get a remote config by ID
// @Description Returns a single remote config by its UUID
// @Tags Admin - Config
// @Accept json
// @Produce json
// @Param id path string true "Remote config UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response "Remote config retrieved successfully"
// @Failure 400 {object} response.Response "Invalid config ID format"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 404 {object} response.Response "Remote config not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/config/{id} [get]
func (h *AdminProductHandler) GetConfig(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid config ID format")
		return
	}

	cfg, err := h.service.GetRemoteConfig(id)
	if err != nil {
		if errors.Is(err, service.ErrRemoteConfigNotFound) {
			response.Error(c, http.StatusNotFound, "CONFIG_NOT_FOUND", "Remote config not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get remote config")
		return
	}

	response.Success(c, http.StatusOK, cfg)
}

// UpdateConfig godoc
// @Summary Update a remote config
// @Description Updates an existing remote config with the provided fields
// @Tags Admin - Config
// @Accept json
// @Produce json
// @Param id path string true "Remote config UUID"
// @Param request body dto.UpdateRemoteConfigRequest true "Remote config update request"
// @Security BearerAuth
// @Success 200 {object} response.Response "Remote config updated successfully"
// @Failure 400 {object} response.Response "Invalid request body or ID format"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 404 {object} response.Response "Remote config not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/config/{id} [patch]
func (h *AdminProductHandler) UpdateConfig(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid config ID format")
		return
	}

	var req dto.UpdateRemoteConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	cfg, err := h.service.UpdateRemoteConfig(id, req)
	if err != nil {
		if errors.Is(err, service.ErrRemoteConfigNotFound) {
			response.Error(c, http.StatusNotFound, "CONFIG_NOT_FOUND", "Remote config not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to update remote config")
		return
	}

	response.Success(c, http.StatusOK, cfg)
}

// DeleteConfig godoc
// @Summary Delete a remote config
// @Description Permanently deletes a remote config by its UUID
// @Tags Admin - Config
// @Accept json
// @Produce json
// @Param id path string true "Remote config UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response "Remote config deleted successfully"
// @Failure 400 {object} response.Response "Invalid config ID format"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 404 {object} response.Response "Remote config not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/config/{id} [delete]
func (h *AdminProductHandler) DeleteConfig(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid config ID format")
		return
	}

	if err := h.service.DeleteRemoteConfig(id); err != nil {
		if errors.Is(err, service.ErrRemoteConfigNotFound) {
			response.Error(c, http.StatusNotFound, "CONFIG_NOT_FOUND", "Remote config not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to delete remote config")
		return
	}

	response.Success(c, http.StatusOK, gin.H{"deleted": true})
}

// ==================== App Releases ====================

// ListReleases godoc
// @Summary List all app releases
// @Description Returns a paginated list of app releases with optional platform and channel filters
// @Tags Admin - Releases
// @Accept json
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param platform query string false "Filter by platform (e.g., windows, macos, linux)"
// @Param channel query string false "Filter by release channel (e.g., stable, beta, alpha)"
// @Security BearerAuth
// @Success 200 {object} response.Response "Paginated releases list retrieved successfully"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/releases [get]
func (h *AdminProductHandler) ListReleases(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)

	releases, total, err := h.service.ListAppReleases(
		page, perPage,
		c.Query("platform"),
		c.Query("channel"),
	)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list releases")
		return
	}

	response.Paginated(c, releases, total, page, perPage)
}

// CreateRelease godoc
// @Summary Create a new app release
// @Description Creates a new app release with version, platform, and download information
// @Tags Admin - Releases
// @Accept json
// @Produce json
// @Param request body dto.CreateAppReleaseRequest true "App release creation request"
// @Security BearerAuth
// @Success 201 {object} response.Response "App release created successfully"
// @Failure 400 {object} response.Response "Invalid request body"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/releases [post]
func (h *AdminProductHandler) CreateRelease(c *gin.Context) {
	var req dto.CreateAppReleaseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	release, err := h.service.CreateAppRelease(req)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to create release")
		return
	}

	response.Success(c, http.StatusCreated, release)
}

// GetRelease godoc
// @Summary Get an app release by ID
// @Description Returns a single app release by its UUID
// @Tags Admin - Releases
// @Accept json
// @Produce json
// @Param id path string true "App release UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response "App release retrieved successfully"
// @Failure 400 {object} response.Response "Invalid release ID format"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 404 {object} response.Response "App release not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/releases/{id} [get]
func (h *AdminProductHandler) GetRelease(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid release ID format")
		return
	}

	release, err := h.service.GetAppRelease(id)
	if err != nil {
		if errors.Is(err, service.ErrAppReleaseNotFound) {
			response.Error(c, http.StatusNotFound, "RELEASE_NOT_FOUND", "App release not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get release")
		return
	}

	response.Success(c, http.StatusOK, release)
}

// UpdateRelease godoc
// @Summary Update an app release
// @Description Updates an existing app release with the provided fields
// @Tags Admin - Releases
// @Accept json
// @Produce json
// @Param id path string true "App release UUID"
// @Param request body dto.UpdateAppReleaseRequest true "App release update request"
// @Security BearerAuth
// @Success 200 {object} response.Response "App release updated successfully"
// @Failure 400 {object} response.Response "Invalid request body or ID format"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 404 {object} response.Response "App release not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/releases/{id} [patch]
func (h *AdminProductHandler) UpdateRelease(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid release ID format")
		return
	}

	var req dto.UpdateAppReleaseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	release, err := h.service.UpdateAppRelease(id, req)
	if err != nil {
		if errors.Is(err, service.ErrAppReleaseNotFound) {
			response.Error(c, http.StatusNotFound, "RELEASE_NOT_FOUND", "App release not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to update release")
		return
	}

	response.Success(c, http.StatusOK, release)
}

// ==================== Announcements ====================

// ListAnnouncements godoc
// @Summary List all announcements
// @Description Returns a paginated list of announcements with optional type and active filters
// @Tags Admin - Announcements
// @Accept json
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param type query string false "Filter by announcement type"
// @Param active query string false "Filter active announcements only (true/false)"
// @Security BearerAuth
// @Success 200 {object} response.Response "Paginated announcements list retrieved successfully"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/announcements [get]
func (h *AdminProductHandler) ListAnnouncements(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)
	activeOnly := c.Query("active") == "true"

	announcements, total, err := h.service.ListAnnouncements(
		page, perPage,
		c.Query("type"),
		activeOnly,
	)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list announcements")
		return
	}

	response.Paginated(c, announcements, total, page, perPage)
}

// CreateAnnouncement godoc
// @Summary Create a new announcement
// @Description Creates a new announcement with title, content, and targeting options
// @Tags Admin - Announcements
// @Accept json
// @Produce json
// @Param request body dto.CreateAnnouncementRequest true "Announcement creation request"
// @Security BearerAuth
// @Success 201 {object} response.Response "Announcement created successfully"
// @Failure 400 {object} response.Response "Invalid request body"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/announcements [post]
func (h *AdminProductHandler) CreateAnnouncement(c *gin.Context) {
	var req dto.CreateAnnouncementRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	ann, err := h.service.CreateAnnouncement(req)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to create announcement")
		return
	}

	response.Success(c, http.StatusCreated, ann)
}

// GetAnnouncement godoc
// @Summary Get an announcement by ID
// @Description Returns a single announcement by its UUID
// @Tags Admin - Announcements
// @Accept json
// @Produce json
// @Param id path string true "Announcement UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response "Announcement retrieved successfully"
// @Failure 400 {object} response.Response "Invalid announcement ID format"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 404 {object} response.Response "Announcement not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/announcements/{id} [get]
func (h *AdminProductHandler) GetAnnouncement(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid announcement ID format")
		return
	}

	ann, err := h.service.GetAnnouncement(id)
	if err != nil {
		if errors.Is(err, service.ErrAnnouncementNotFound) {
			response.Error(c, http.StatusNotFound, "ANNOUNCEMENT_NOT_FOUND", "Announcement not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get announcement")
		return
	}

	response.Success(c, http.StatusOK, ann)
}

// UpdateAnnouncement godoc
// @Summary Update an announcement
// @Description Updates an existing announcement with the provided fields
// @Tags Admin - Announcements
// @Accept json
// @Produce json
// @Param id path string true "Announcement UUID"
// @Param request body dto.UpdateAnnouncementRequest true "Announcement update request"
// @Security BearerAuth
// @Success 200 {object} response.Response "Announcement updated successfully"
// @Failure 400 {object} response.Response "Invalid request body or ID format"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 404 {object} response.Response "Announcement not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/announcements/{id} [patch]
func (h *AdminProductHandler) UpdateAnnouncement(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid announcement ID format")
		return
	}

	var req dto.UpdateAnnouncementRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	ann, err := h.service.UpdateAnnouncement(id, req)
	if err != nil {
		if errors.Is(err, service.ErrAnnouncementNotFound) {
			response.Error(c, http.StatusNotFound, "ANNOUNCEMENT_NOT_FOUND", "Announcement not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to update announcement")
		return
	}

	response.Success(c, http.StatusOK, ann)
}

// DeleteAnnouncement godoc
// @Summary Delete an announcement
// @Description Permanently deletes an announcement by its UUID
// @Tags Admin - Announcements
// @Accept json
// @Produce json
// @Param id path string true "Announcement UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response "Announcement deleted successfully"
// @Failure 400 {object} response.Response "Invalid announcement ID format"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 404 {object} response.Response "Announcement not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/announcements/{id} [delete]
func (h *AdminProductHandler) DeleteAnnouncement(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid announcement ID format")
		return
	}

	if err := h.service.DeleteAnnouncement(id); err != nil {
		if errors.Is(err, service.ErrAnnouncementNotFound) {
			response.Error(c, http.StatusNotFound, "ANNOUNCEMENT_NOT_FOUND", "Announcement not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to delete announcement")
		return
	}

	response.Success(c, http.StatusOK, gin.H{"deleted": true})
}

// ProductStats godoc
// @Summary Get product statistics
// @Description Returns aggregated statistics for product-related data including flags, configs, releases, and announcements
// @Tags Admin - Stats
// @Accept json
// @Produce json
// @Security BearerAuth
// @Success 200 {object} response.Response "Product statistics retrieved successfully"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing token"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/product/stats [get]
func (h *AdminProductHandler) ProductStats(c *gin.Context) {
	stats, err := h.service.GetProductStats()
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get product stats")
		return
	}

	response.Success(c, http.StatusOK, stats)
}
