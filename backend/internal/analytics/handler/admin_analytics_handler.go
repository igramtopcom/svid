package handler

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/snakeloader/backend/internal/analytics/dto"
	"github.com/snakeloader/backend/internal/analytics/repository"
	"github.com/snakeloader/backend/internal/analytics/service"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"github.com/snakeloader/backend/internal/response"
)

// AdminAnalyticsHandler handles admin-facing analytics endpoints
type AdminAnalyticsHandler struct {
	service adminAnalyticsService
}

type adminAnalyticsService interface {
	ListEvents(page, perPage int, eventType, os, appVersion, brand string) ([]dto.EventResponse, int64, error)
	ListBootstrapEvents(page, perPage int, brand, os, appVersion, stage, status, errorCode string, dateFrom, dateTo *time.Time) ([]dto.BootstrapEventResponse, int64, error)
	GetOverview(brand string) (*dto.AnalyticsOverview, error)
	GetTopEvents(limit int, brand string) ([]repository.EventTypeCount, error)
	GetDailyStats(startDate, endDate time.Time, metricName string) ([]dto.DailyStatsResponse, error)
	ListDownloadErrors(page, perPage int, errorCode, errorPhase, diagnosticErrorCode, platform, os, appVersion, brand string, dateFrom, dateTo *time.Time) ([]dto.DownloadErrorResponse, int64, error)
	GetDownloadErrorStats(days int, brand string) (*dto.DownloadErrorStatsResponse, error)
	GetDownloadStats(days int, brand string) (*dto.DownloadStatsResponse, error)
}

func NewAdminAnalyticsHandler(svc *service.AnalyticsService) *AdminAnalyticsHandler {
	return &AdminAnalyticsHandler{service: svc}
}

// ListEvents godoc
// @Summary List analytics events
// @Description Retrieve a paginated list of analytics events with optional filtering by event type, OS, and app version.
// @Tags Admin - Analytics
// @Accept json
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param event_type query string false "Filter by event type"
// @Param os query string false "Filter by operating system"
// @Param app_version query string false "Filter by app version"
// @Param brand query string false "Filter by brand (e.g. svid, vidcombo)"
// @Security BearerAuth
// @Success 200 {object} response.Response "Paginated list of events"
// @Failure 401 {object} response.Response "Unauthorized - invalid or missing JWT token"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/analytics/events [get]
func (h *AdminAnalyticsHandler) ListEvents(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)

	events, total, err := h.service.ListEvents(
		page, perPage,
		c.Query("event_type"),
		c.Query("os"),
		c.Query("app_version"),
		c.Query("brand"),
	)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list events")
		return
	}

	response.Paginated(c, events, total, page, perPage)
}

// ListBootstrapEvents godoc
// @Summary List bootstrap events
// @Description Retrieve pre-auth startup/registration telemetry for devices that may never have registered.
// @Tags Admin - Analytics
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param brand query string false "Filter by brand"
// @Param os query string false "Filter by OS"
// @Param app_version query string false "Filter by app version"
// @Param stage query string false "Filter by bootstrap stage"
// @Param status query string false "Filter by status"
// @Param error_code query string false "Filter by error code"
// @Param date_from query string false "Filter from date (YYYY-MM-DD)"
// @Param date_to query string false "Filter to date (YYYY-MM-DD)"
// @Security BearerAuth
// @Success 200 {object} response.Response "Paginated bootstrap events"
// @Router /admin/v1/analytics/bootstrap-events [get]
func (h *AdminAnalyticsHandler) ListBootstrapEvents(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)

	var dateFrom, dateTo *time.Time
	if df := c.Query("date_from"); df != "" {
		if t, err := time.Parse("2006-01-02", df); err == nil {
			dateFrom = &t
		}
	}
	if dt := c.Query("date_to"); dt != "" {
		if t, err := time.Parse("2006-01-02", dt); err == nil {
			end := t.Add(24*time.Hour - time.Second)
			dateTo = &end
		}
	}

	events, total, err := h.service.ListBootstrapEvents(
		page, perPage,
		c.Query("brand"),
		c.Query("os"),
		c.Query("app_version"),
		c.Query("stage"),
		c.Query("status"),
		c.Query("error_code"),
		dateFrom, dateTo,
	)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list bootstrap events")
		return
	}

	response.Paginated(c, events, total, page, perPage)
}

// Overview godoc
// @Summary Get analytics overview
// @Description Get an overview of analytics data including total events, events today, active devices, and breakdowns by OS and version.
// @Tags Admin - Analytics
// @Accept json
// @Produce json
// @Security BearerAuth
// @Success 200 {object} response.Response "Analytics overview data"
// @Failure 401 {object} response.Response "Unauthorized - invalid or missing JWT token"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/analytics/stats [get]
func (h *AdminAnalyticsHandler) Overview(c *gin.Context) {
	brand := c.Query("brand")
	overview, err := h.service.GetOverview(brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get analytics overview")
		return
	}

	response.Success(c, http.StatusOK, overview)
}

// TopEvents godoc
// @Summary Get top events
// @Description Retrieve the most frequently occurring event types, useful for understanding feature usage and user behavior patterns.
// @Tags Admin - Analytics
// @Accept json
// @Produce json
// @Param limit query int false "Number of top events to return" default(10)
// @Security BearerAuth
// @Success 200 {object} response.Response "List of top events with counts"
// @Failure 401 {object} response.Response "Unauthorized - invalid or missing JWT token"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/analytics/top-events [get]
func (h *AdminAnalyticsHandler) TopEvents(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "10"))
	limit = normalizePositiveQueryBound(limit, 10, 100)
	brand := c.Query("brand")

	top, err := h.service.GetTopEvents(limit, brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get top events")
		return
	}

	response.Success(c, http.StatusOK, top)
}

// DailyStats godoc
// @Summary Get daily statistics
// @Description Retrieve daily aggregated statistics for a date range. Useful for tracking trends and generating reports.
// @Tags Admin - Analytics
// @Accept json
// @Produce json
// @Param start query string false "Start date in YYYY-MM-DD format" default(30 days ago)
// @Param end query string false "End date in YYYY-MM-DD format" default(today)
// @Param metric query string false "Filter by specific metric name"
// @Security BearerAuth
// @Success 200 {object} response.Response "Daily statistics data"
// @Failure 400 {object} response.Response "Invalid date format"
// @Failure 401 {object} response.Response "Unauthorized - invalid or missing JWT token"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/analytics/daily [get]
func (h *AdminAnalyticsHandler) DailyStats(c *gin.Context) {
	startStr := c.DefaultQuery("start", time.Now().AddDate(0, 0, -30).Format("2006-01-02"))
	endStr := c.DefaultQuery("end", time.Now().Format("2006-01-02"))

	start, err := time.Parse("2006-01-02", startStr)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_DATE", "Invalid start date format (use YYYY-MM-DD)")
		return
	}
	end, err := time.Parse("2006-01-02", endStr)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_DATE", "Invalid end date format (use YYYY-MM-DD)")
		return
	}

	// Enforce maximum date range of 365 days to prevent unbounded queries
	if end.Sub(start).Hours() > 365*24 {
		response.Error(c, http.StatusBadRequest, "DATE_RANGE_TOO_LARGE", "Date range must not exceed 365 days")
		return
	}
	if start.After(end) {
		response.Error(c, http.StatusBadRequest, "INVALID_DATE_RANGE", "Start date must be before or equal to end date")
		return
	}

	stats, err := h.service.GetDailyStats(start, end, c.Query("metric"))
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get daily stats")
		return
	}

	response.Success(c, http.StatusOK, stats)
}

// ==================== Download Error Intelligence ====================

// ListDownloadErrors godoc
// @Summary List download errors
// @Tags Admin - Analytics
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param error_code query string false "Filter by error code"
// @Param error_phase query string false "Filter by error phase"
// @Param diagnostic_error_code query string false "Filter by stored diagnostic error code (new rows/backfilled rows only)"
// @Param platform query string false "Filter by platform"
// @Param os query string false "Filter by OS"
// @Param app_version query string false "Filter by app version"
// @Param date_from query string false "Filter from date (YYYY-MM-DD)"
// @Param date_to query string false "Filter to date (YYYY-MM-DD)"
// @Param brand query string false "Filter by brand (e.g. svid, vidcombo)"
// @Security BearerAuth
// @Success 200 {object} response.Response "Paginated download errors"
// @Router /admin/v1/analytics/download-errors [get]
func (h *AdminAnalyticsHandler) ListDownloadErrors(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)

	var dateFrom, dateTo *time.Time
	if df := c.Query("date_from"); df != "" {
		if t, err := time.Parse("2006-01-02", df); err == nil {
			dateFrom = &t
		}
	}
	if dt := c.Query("date_to"); dt != "" {
		if t, err := time.Parse("2006-01-02", dt); err == nil {
			end := t.Add(24*time.Hour - time.Second) // end of day
			dateTo = &end
		}
	}

	errors, total, err := h.service.ListDownloadErrors(
		page, perPage,
		c.Query("error_code"),
		c.Query("error_phase"),
		c.Query("diagnostic_error_code"),
		c.Query("platform"),
		c.Query("os"),
		c.Query("app_version"),
		c.Query("brand"),
		dateFrom, dateTo,
	)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list download errors")
		return
	}

	response.Paginated(c, errors, total, page, perPage)
}

// DownloadErrorStats godoc
// @Summary Get download error statistics
// @Tags Admin - Analytics
// @Param days query int false "Number of days" default(30)
// @Security BearerAuth
// @Success 200 {object} response.Response "Download error stats"
// @Router /admin/v1/analytics/download-errors/stats [get]
func (h *AdminAnalyticsHandler) DownloadErrorStats(c *gin.Context) {
	days, _ := strconv.Atoi(c.DefaultQuery("days", "30"))
	days = normalizePositiveQueryBound(days, 30, 365)
	brand := c.Query("brand")

	stats, err := h.service.GetDownloadErrorStats(days, brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get download error stats")
		return
	}

	response.Success(c, http.StatusOK, stats)
}

// DownloadStats godoc
// @Summary Get download analytics
// @Description Aggregated download success/failure rates by platform, OS, and daily trends.
// @Tags Admin - Analytics
// @Param days query int false "Number of days for trend" default(30)
// @Security BearerAuth
// @Success 200 {object} response.Response "Download statistics"
// @Router /admin/v1/analytics/downloads [get]
func (h *AdminAnalyticsHandler) DownloadStats(c *gin.Context) {
	days, _ := strconv.Atoi(c.DefaultQuery("days", "30"))
	days = normalizePositiveQueryBound(days, 30, 365)
	brand := c.Query("brand")

	stats, err := h.service.GetDownloadStats(days, brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get download stats")
		return
	}

	response.Success(c, http.StatusOK, stats)
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
