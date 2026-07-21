package handler

import (
	"errors"
	"net/http"
	"runtime"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/identity/dto"
	"github.com/snakeloader/backend/internal/identity/model"
	"github.com/snakeloader/backend/internal/identity/repository"
	"github.com/snakeloader/backend/internal/identity/service"
	"github.com/snakeloader/backend/internal/middleware"
	"github.com/snakeloader/backend/internal/pkg/crypto"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"github.com/snakeloader/backend/internal/pkg/validator"
	"github.com/snakeloader/backend/internal/response"
	"gorm.io/gorm"
)

type AdminDeviceHandler struct {
	service              *service.DeviceService
	timelineService      deviceTimelineProvider
	comprehensiveService dashboardStatsProvider
	activityFeedService  activityFeedProvider
	topCustomersService  topCustomersProvider
	adminRepo            *repository.AdminRepository
	keyRepo              *repository.ApiKeyRepository
	db                   *gorm.DB
}

type deviceTimelineProvider interface {
	GetDeviceTimeline(deviceID uuid.UUID, page, perPage int, eventTypes string) (*dto.DeviceTimelineResponse, error)
}

type dashboardStatsProvider interface {
	GetComprehensiveStats(brand string) (*dto.ComprehensiveStatsResponse, error)
	GetBrandComparison() (*dto.BrandComparisonResponse, error)
	GetDashboardTrends(days int, brand string) (*dto.DashboardTrendsResponse, error)
}

type activityFeedProvider interface {
	GetRecentActivity(limit int, brand string) (*dto.ActivityFeedResponse, error)
}

type topCustomersProvider interface {
	GetTopCustomers(limit int, brand string) (*dto.TopCustomersResponse, error)
}

func NewAdminDeviceHandler(svc *service.DeviceService) *AdminDeviceHandler {
	return &AdminDeviceHandler{service: svc}
}

// SetTimelineService wires the timeline service (post-construction to avoid circular deps).
func (h *AdminDeviceHandler) SetTimelineService(ts deviceTimelineProvider) {
	h.timelineService = ts
}

// SetComprehensiveService wires the comprehensive stats service.
func (h *AdminDeviceHandler) SetComprehensiveService(cs dashboardStatsProvider) {
	h.comprehensiveService = cs
}

// SetActivityFeedService wires the activity feed service.
func (h *AdminDeviceHandler) SetActivityFeedService(af activityFeedProvider) {
	h.activityFeedService = af
}

// SetTopCustomersService wires the top customers service.
func (h *AdminDeviceHandler) SetTopCustomersService(tc topCustomersProvider) {
	h.topCustomersService = tc
}

// SetAdminRepo wires the admin repository for admin management.
func (h *AdminDeviceHandler) SetAdminRepo(repo *repository.AdminRepository) {
	h.adminRepo = repo
}

// SetKeyRepo wires the API key repository for key management.
func (h *AdminDeviceHandler) SetKeyRepo(repo *repository.ApiKeyRepository) {
	h.keyRepo = repo
}

// SetDB wires the database for system health checks.
func (h *AdminDeviceHandler) SetDB(db *gorm.DB) {
	h.db = db
}

// List godoc
// @Summary List all devices
// @Description Get paginated list of registered devices
// @Tags Admin - Devices
// @Accept json
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param os query string false "Filter by OS"
// @Param search query string false "Search by hardware_id or device_name"
// @Param is_active query bool false "Filter by active status"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=response.PaginatedData} "Success"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/devices [get]
func (h *AdminDeviceHandler) List(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)
	os := c.Query("os")
	brand := c.Query("brand")
	search := c.Query("search")

	var isActive *bool
	if val := c.Query("is_active"); val != "" {
		b := val == "true"
		isActive = &b
	}

	devices, total, err := h.service.ListDevices(page, perPage, os, brand, search, isActive)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list devices")
		return
	}

	response.Paginated(c, devices, total, page, perPage)
}

// Get godoc
// @Summary Get device by ID
// @Description Get detailed information about a specific device
// @Tags Admin - Devices
// @Accept json
// @Produce json
// @Param id path string true "Device UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.DeviceResponse} "Success"
// @Failure 400 {object} response.Response "Invalid ID"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Device not found"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/devices/{id} [get]
func (h *AdminDeviceHandler) Get(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid device ID format")
		return
	}

	device, err := h.service.GetDevice(id)
	if err != nil {
		if errors.Is(err, service.ErrDeviceNotFound) {
			response.Error(c, http.StatusNotFound, "DEVICE_NOT_FOUND", "Device not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get device")
		return
	}

	response.Success(c, http.StatusOK, device)
}

// Update godoc
// @Summary Update device
// @Description Update device tier or active status
// @Tags Admin - Devices
// @Accept json
// @Produce json
// @Param id path string true "Device UUID"
// @Param request body dto.UpdateDeviceRequest true "Update data"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.DeviceResponse} "Success"
// @Failure 400 {object} response.Response "Invalid ID or validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Device not found"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/devices/{id} [patch]
func (h *AdminDeviceHandler) Update(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid device ID format")
		return
	}

	var req dto.UpdateDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	device, err := h.service.UpdateDevice(id, req)
	if err != nil {
		if errors.Is(err, service.ErrDeviceNotFound) {
			response.Error(c, http.StatusNotFound, "DEVICE_NOT_FOUND", "Device not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to update device")
		return
	}

	response.Success(c, http.StatusOK, device)
}

// GetDeviceTimeline godoc
// @Summary Get device timeline
// @Description Get a chronological timeline of all events for a specific device
// @Tags Admin - Devices
// @Accept json
// @Produce json
// @Param id path string true "Device UUID"
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(50)
// @Param types query string false "Comma-separated event types: crash,bug_report,download_error,ticket,license,device_registered"
// @Security BearerAuth
// @Success 200 {object} response.Response "Device timeline"
// @Failure 400 {object} response.Response "Invalid ID"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/devices/{id}/timeline [get]
func (h *AdminDeviceHandler) GetDeviceTimeline(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid device ID format")
		return
	}

	if h.timelineService == nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Timeline service not available")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "50"))
	page, perPage = pagination.Normalize(page, perPage, 50)
	types := c.Query("types")

	timeline, err := h.timelineService.GetDeviceTimeline(id, page, perPage, types)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get device timeline")
		return
	}

	response.Success(c, http.StatusOK, timeline)
}

// ComprehensiveStats godoc
// @Summary Get comprehensive dashboard statistics
// @Description Aggregates all key metrics (devices, bugs, crash groups, download errors, revenue, tickets, ratings) in a single response
// @Tags Admin - Dashboard
// @Accept json
// @Produce json
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.ComprehensiveStatsResponse} "Success"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/dashboard/comprehensive [get]
func (h *AdminDeviceHandler) ComprehensiveStats(c *gin.Context) {
	if h.comprehensiveService == nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Comprehensive stats not available")
		return
	}

	brand := c.Query("brand")
	stats, err := h.comprehensiveService.GetComprehensiveStats(brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get comprehensive stats")
		return
	}

	response.Success(c, http.StatusOK, stats)
}

// BrandComparison returns key KPIs for each brand side-by-side.
func (h *AdminDeviceHandler) BrandComparison(c *gin.Context) {
	if h.comprehensiveService == nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Comprehensive stats not available")
		return
	}

	stats, err := h.comprehensiveService.GetBrandComparison()
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get brand comparison")
		return
	}

	response.Success(c, http.StatusOK, stats)
}

// DashboardTrends returns period-over-period comparison for key dashboard metrics.
func (h *AdminDeviceHandler) DashboardTrends(c *gin.Context) {
	if h.comprehensiveService == nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Comprehensive stats not available")
		return
	}

	days, _ := strconv.Atoi(c.DefaultQuery("days", "7"))
	days = normalizePositiveQueryBound(days, 7, 365)
	brand := c.Query("brand")

	trends, err := h.comprehensiveService.GetDashboardTrends(days, brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get dashboard trends")
		return
	}

	response.Success(c, http.StatusOK, trends)
}

// DashboardActivity returns the most recent system-wide events for the activity feed.
func (h *AdminDeviceHandler) DashboardActivity(c *gin.Context) {
	if h.activityFeedService == nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Activity feed not available")
		return
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "25"))
	limit = normalizePositiveQueryBound(limit, 25, 200)
	brand := c.Query("brand")

	activity, err := h.activityFeedService.GetRecentActivity(limit, brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get activity feed")
		return
	}

	response.Success(c, http.StatusOK, activity)
}

// DashboardTopCustomers returns the top revenue-generating customers.
func (h *AdminDeviceHandler) DashboardTopCustomers(c *gin.Context) {
	if h.topCustomersService == nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Top customers not available")
		return
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "10"))
	limit = normalizePositiveQueryBound(limit, 10, 100)
	brand := c.Query("brand")

	top, err := h.topCustomersService.GetTopCustomers(limit, brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get top customers")
		return
	}

	response.Success(c, http.StatusOK, top)
}

func normalizePositiveQueryBound(value, fallback, max int) int {
	if value <= 0 {
		return fallback
	}
	if value > max {
		return max
	}
	return value
}

// ==================== System Health ====================

func (h *AdminDeviceHandler) SystemHealth(c *gin.Context) {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	dbStatus := "ok"
	var dbPoolOpen, dbPoolIdle int
	if h.db != nil {
		sqlDB, err := h.db.DB()
		if err == nil {
			if err := sqlDB.Ping(); err != nil {
				dbStatus = "error: " + err.Error()
			}
			stats := sqlDB.Stats()
			dbPoolOpen = stats.OpenConnections
			dbPoolIdle = stats.Idle
		}
	}

	response.Success(c, http.StatusOK, gin.H{
		"status":        "ok",
		"timestamp":     time.Now().Format(time.RFC3339),
		"go_version":    runtime.Version(),
		"goroutines":    runtime.NumGoroutine(),
		"memory_mb":     m.Alloc / 1024 / 1024,
		"sys_memory_mb": m.Sys / 1024 / 1024,
		"gc_runs":       m.NumGC,
		"db_status":     dbStatus,
		"db_pool_open":  dbPoolOpen,
		"db_pool_idle":  dbPoolIdle,
	})
}

// ==================== Admin User Management ====================

func (h *AdminDeviceHandler) ListAdmins(c *gin.Context) {
	var admins []model.Admin
	if err := h.db.Order("created_at ASC").Find(&admins).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list admins")
		return
	}

	type AdminResponse struct {
		ID          string  `json:"id"`
		Email       string  `json:"email"`
		Name        string  `json:"name"`
		BrandScope  string  `json:"brand_scope"`
		CreatedAt   string  `json:"created_at"`
		LastLoginAt *string `json:"last_login_at"`
	}

	items := make([]AdminResponse, len(admins))
	for i, a := range admins {
		resp := AdminResponse{
			ID:         a.ID.String(),
			Email:      a.Email,
			Name:       a.Name,
			BrandScope: a.BrandScope,
			CreatedAt:  a.CreatedAt.Format(time.RFC3339),
		}
		if a.LastLoginAt != nil {
			t := a.LastLoginAt.Format(time.RFC3339)
			resp.LastLoginAt = &t
		}
		items[i] = resp
	}

	response.Success(c, http.StatusOK, items)
}

func (h *AdminDeviceHandler) CreateAdmin(c *gin.Context) {
	var req struct {
		Email      string `json:"email" binding:"required,email"`
		Password   string `json:"password" binding:"required,min=8"`
		Name       string `json:"name" binding:"required"`
		BrandScope string `json:"brand_scope" binding:"omitempty,oneof=svid vidcombo"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	hash, err := crypto.HashPassword(req.Password)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to hash password")
		return
	}

	admin := &model.Admin{
		Email:        req.Email,
		PasswordHash: hash,
		Name:         req.Name,
		BrandScope:   req.BrandScope,
	}
	if err := h.db.Create(admin).Error; err != nil {
		response.Error(c, http.StatusConflict, "EMAIL_EXISTS", "Admin with this email already exists")
		return
	}

	response.Success(c, http.StatusCreated, gin.H{
		"id":          admin.ID.String(),
		"email":       admin.Email,
		"name":        admin.Name,
		"brand_scope": admin.BrandScope,
	})
}

func (h *AdminDeviceHandler) UpdateAdmin(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid admin ID")
		return
	}

	var req struct {
		Name       *string `json:"name"`
		Password   *string `json:"password"`
		BrandScope *string `json:"brand_scope"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	updates := map[string]interface{}{}
	if req.Name != nil {
		updates["name"] = *req.Name
	}
	if req.Password != nil && *req.Password != "" {
		hash, err := crypto.HashPassword(*req.Password)
		if err != nil {
			response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to hash password")
			return
		}
		updates["password_hash"] = hash
	}
	if req.BrandScope != nil {
		// Validate brand scope value
		scope := *req.BrandScope
		if scope != "" && scope != "svid" && scope != "vidcombo" {
			response.Error(c, http.StatusBadRequest, "INVALID_BRAND_SCOPE", "brand_scope must be empty, 'svid', or 'vidcombo'")
			return
		}
		updates["brand_scope"] = scope
	}

	if len(updates) == 0 {
		response.Error(c, http.StatusBadRequest, "NO_CHANGES", "No fields to update")
		return
	}

	if err := h.db.Model(&model.Admin{}).Where("id = ?", id).Updates(updates).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to update admin")
		return
	}

	response.Success(c, http.StatusOK, gin.H{"message": "Admin updated"})
}

func (h *AdminDeviceHandler) DeleteAdmin(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid admin ID")
		return
	}

	// Prevent deleting yourself
	currentAdminID, _ := c.Get(middleware.AdminIDKey)
	if currentID, ok := currentAdminID.(uuid.UUID); ok && currentID == id {
		response.Error(c, http.StatusForbidden, "SELF_DELETE", "Cannot delete your own account")
		return
	}

	// Check at least one admin remains
	var count int64
	h.db.Model(&model.Admin{}).Count(&count)
	if count <= 1 {
		response.Error(c, http.StatusForbidden, "LAST_ADMIN", "Cannot delete the last admin account")
		return
	}

	if err := h.db.Delete(&model.Admin{}, "id = ?", id).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to delete admin")
		return
	}

	response.Success(c, http.StatusOK, gin.H{"message": "Admin deleted"})
}

// ==================== API Key Management ====================

func (h *AdminDeviceHandler) ListApiKeys(c *gin.Context) {
	deviceID, err := uuid.Parse(c.Param("deviceId"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid device ID")
		return
	}

	var keys []model.ApiKey
	if err := h.db.Where("device_id = ?", deviceID).Order("created_at DESC").Find(&keys).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list API keys")
		return
	}

	type KeyResponse struct {
		ID        string `json:"id"`
		DeviceID  string `json:"device_id"`
		IsRevoked bool   `json:"is_revoked"`
		IsValid   bool   `json:"is_valid"`
		CreatedAt string `json:"created_at"`
		ExpiresAt string `json:"expires_at"`
	}

	items := make([]KeyResponse, len(keys))
	for i, k := range keys {
		items[i] = KeyResponse{
			ID:        k.ID.String(),
			DeviceID:  k.DeviceID.String(),
			IsRevoked: k.IsRevoked,
			IsValid:   k.IsValid(),
			CreatedAt: k.CreatedAt.Format(time.RFC3339),
			ExpiresAt: k.ExpiresAt.Format(time.RFC3339),
		}
	}

	response.Success(c, http.StatusOK, items)
}

func (h *AdminDeviceHandler) RevokeApiKey(c *gin.Context) {
	keyID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid key ID")
		return
	}

	result := h.db.Model(&model.ApiKey{}).Where("id = ?", keyID).Update("is_revoked", true)
	if result.Error != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to revoke key")
		return
	}
	if result.RowsAffected == 0 {
		response.Error(c, http.StatusNotFound, "NOT_FOUND", "API key not found")
		return
	}

	response.Success(c, http.StatusOK, gin.H{"message": "API key revoked"})
}
