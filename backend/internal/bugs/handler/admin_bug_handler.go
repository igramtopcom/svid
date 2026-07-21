package handler

import (
	"errors"
	"io"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/bugs/dto"
	"github.com/snakeloader/backend/internal/bugs/service"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"github.com/snakeloader/backend/internal/pkg/validator"
	"github.com/snakeloader/backend/internal/response"
)

type AdminBugHandler struct {
	service                *service.BugService
	crashGroupMergeService crashGroupMergeProvider
}

type crashGroupMergeProvider interface {
	ListCrashGroupMergeCandidates(limit int, includeResolved bool) ([]dto.CrashGroupMergeCandidateResponse, error)
	BackfillCrashGroupMerges(req dto.BackfillCrashGroupMergesRequest) (*dto.CrashGroupBackfillMergeReportResponse, error)
}

func NewAdminBugHandler(svc *service.BugService) *AdminBugHandler {
	return &AdminBugHandler{
		service:                svc,
		crashGroupMergeService: svc,
	}
}

func (h *AdminBugHandler) SetCrashGroupMergeService(provider crashGroupMergeProvider) {
	h.crashGroupMergeService = provider
}

// ListBugs godoc
// @Summary List all bug reports
// @Description Get paginated list of bug reports with optional filters
// @Tags Admin - Bugs
// @Accept json
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param status query string false "Filter by status (open, in_progress, resolved, closed, wont_fix)"
// @Param priority query string false "Filter by priority (low, medium, high, critical)"
// @Param os query string false "Filter by OS"
// @Param app_version query string false "Filter by app version"
// @Param search query string false "Search in title/description"
// @Param device_id query string false "Filter by device UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=response.PaginatedData} "Success"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/bugs [get]
func (h *AdminBugHandler) ListBugs(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)

	bugs, total, err := h.service.ListBugs(
		page, perPage,
		c.Query("status"),
		c.Query("priority"),
		c.Query("os"),
		c.Query("app_version"),
		c.Query("search"),
		c.Query("brand"),
		c.Query("device_id"),
	)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list bugs")
		return
	}

	response.Paginated(c, bugs, total, page, perPage)
}

// GetBug godoc
// @Summary Get bug report by ID
// @Description Get detailed information about a specific bug report
// @Tags Admin - Bugs
// @Accept json
// @Produce json
// @Param id path string true "Bug UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.BugResponse} "Success"
// @Failure 400 {object} response.Response "Invalid ID"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Bug not found"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/bugs/{id} [get]
func (h *AdminBugHandler) GetBug(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid bug ID format")
		return
	}

	bug, err := h.service.GetBug(id)
	if err != nil {
		if errors.Is(err, service.ErrBugNotFound) {
			response.Error(c, http.StatusNotFound, "BUG_NOT_FOUND", "Bug report not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get bug report")
		return
	}

	response.Success(c, http.StatusOK, bug)
}

// UpdateBug godoc
// @Summary Update bug report
// @Description Update bug status, priority, or admin notes
// @Tags Admin - Bugs
// @Accept json
// @Produce json
// @Param id path string true "Bug UUID"
// @Param request body dto.UpdateBugRequest true "Update data"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.BugResponse} "Success"
// @Failure 400 {object} response.Response "Invalid ID or validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Bug not found"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/bugs/{id} [patch]
func (h *AdminBugHandler) UpdateBug(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid bug ID format")
		return
	}

	var req dto.UpdateBugRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	bug, err := h.service.UpdateBug(id, req)
	if err != nil {
		if errors.Is(err, service.ErrBugNotFound) {
			response.Error(c, http.StatusNotFound, "BUG_NOT_FOUND", "Bug report not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to update bug report")
		return
	}

	response.Success(c, http.StatusOK, bug)
}

// ListCrashes godoc
// @Summary List all crash reports
// @Description Get paginated list of crash reports with optional filters
// @Tags Admin - Crashes
// @Accept json
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param severity query string false "Filter by severity"
// @Param app_version query string false "Filter by app version"
// @Param os query string false "Filter by OS"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=response.PaginatedData} "Success"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/crashes [get]
func (h *AdminBugHandler) ListCrashes(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)

	crashes, total, err := h.service.ListCrashes(
		page, perPage,
		c.Query("severity"),
		c.Query("app_version"),
		c.Query("os"),
		c.Query("brand"),
		c.Query("device_id"),
	)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list crashes")
		return
	}

	response.Paginated(c, crashes, total, page, perPage)
}

// GetCrash godoc
// @Summary Get crash report by ID
// @Description Get detailed information about a specific crash report
// @Tags Admin - Crashes
// @Accept json
// @Produce json
// @Param id path string true "Crash UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.CrashResponse} "Success"
// @Failure 400 {object} response.Response "Invalid ID"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Crash not found"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/crashes/{id} [get]
func (h *AdminBugHandler) GetCrash(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid crash ID format")
		return
	}

	crash, err := h.service.GetCrash(id)
	if err != nil {
		if errors.Is(err, service.ErrCrashNotFound) {
			response.Error(c, http.StatusNotFound, "CRASH_NOT_FOUND", "Crash report not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get crash report")
		return
	}

	response.Success(c, http.StatusOK, crash)
}

// BugStats godoc
// @Summary Get bug statistics
// @Description Get statistics for bugs and crashes
// @Tags Admin - Bugs
// @Accept json
// @Produce json
// @Security BearerAuth
// @Success 200 {object} response.Response "Success"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/bugs/stats [get]
func (h *AdminBugHandler) BugStats(c *gin.Context) {
	brand := c.Query("brand")
	bugStats, crashStats, err := h.service.GetBugStats(brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get bug stats")
		return
	}

	response.Success(c, http.StatusOK, gin.H{
		"bugs":    bugStats,
		"crashes": crashStats,
	})
}

// GetBugLog godoc
// @Summary Get bug diagnostic log
// @Description Retrieve the diagnostic log attached to a bug report
// @Tags Admin - Bugs
// @Param id path string true "Bug UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response "Success"
// @Router /admin/v1/bugs/{id}/log [get]
func (h *AdminBugHandler) GetBugLog(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid bug ID format")
		return
	}

	log, err := h.service.GetDiagnosticLog("bug", id)
	if err != nil {
		if errors.Is(err, service.ErrLogNotFound) {
			response.Error(c, http.StatusNotFound, "LOG_NOT_FOUND", "No diagnostic log for this bug report")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get diagnostic log")
		return
	}

	response.Success(c, http.StatusOK, log)
}

// UpdateCrash godoc
// @Summary Update crash report
// @Description Update admin notes on a crash report
// @Tags Admin - Crashes
// @Accept json
// @Produce json
// @Param id path string true "Crash UUID"
// @Param request body dto.UpdateCrashRequest true "Update data"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.CrashResponse} "Success"
// @Router /admin/v1/crashes/{id} [patch]
func (h *AdminBugHandler) UpdateCrash(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid crash ID format")
		return
	}

	var req dto.UpdateCrashRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	crash, err := h.service.UpdateCrash(id, req)
	if err != nil {
		if errors.Is(err, service.ErrCrashNotFound) {
			response.Error(c, http.StatusNotFound, "CRASH_NOT_FOUND", "Crash report not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to update crash report")
		return
	}

	response.Success(c, http.StatusOK, crash)
}

// ==================== Crash Group Endpoints ====================

// ListCrashGroups godoc
// @Summary List crash groups
// @Description Get paginated list of crash groups with optional filters
// @Tags Admin - Crash Groups
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param status query string false "Filter by status"
// @Param severity query string false "Filter by severity"
// @Param search query string false "Search in title/notes"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=response.PaginatedData} "Success"
// @Router /admin/v1/crash-groups [get]
func (h *AdminBugHandler) ListCrashGroups(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)

	groups, total, err := h.service.ListCrashGroups(
		page, perPage,
		c.Query("status"),
		c.Query("severity"),
		c.Query("search"),
		c.Query("brand"),
	)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list crash groups")
		return
	}

	response.Paginated(c, groups, total, page, perPage)
}

// ListCrashGroupMergeCandidates godoc
// @Summary List crash group merge candidates
// @Description Surface likely duplicate crash groups for historical cleanup/backfill
// @Tags Admin - Crash Groups
// @Param limit query int false "Max groups to scan" default(200)
// @Param include_resolved query bool false "Include resolved/wont_fix groups" default(false)
// @Security BearerAuth
// @Success 200 {object} response.Response "Success"
// @Router /admin/v1/crash-groups/merge-candidates [get]
func (h *AdminBugHandler) ListCrashGroupMergeCandidates(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "200"))
	limit = normalizePositiveQueryBound(limit, 200, 500)
	includeResolved, _ := strconv.ParseBool(c.DefaultQuery("include_resolved", "false"))

	candidates, err := h.crashGroupMergeService.ListCrashGroupMergeCandidates(limit, includeResolved)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list crash group merge candidates")
		return
	}

	response.Success(c, http.StatusOK, gin.H{
		"count":      len(candidates),
		"candidates": candidates,
	})
}

// BackfillCrashGroupMerges godoc
// @Summary Dry-run or execute bounded crash-group backfill merges
// @Description Apply historical crash-group merges in controlled batches; defaults to dry-run
// @Tags Admin - Crash Groups
// @Param request body dto.BackfillCrashGroupMergesRequest false "Backfill options"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.CrashGroupBackfillMergeReportResponse} "Success"
// @Router /admin/v1/crash-groups/backfill-merge [post]
func (h *AdminBugHandler) BackfillCrashGroupMerges(c *gin.Context) {
	var req dto.BackfillCrashGroupMergesRequest
	if err := c.ShouldBindJSON(&req); err != nil && !errors.Is(err, io.EOF) {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	report, err := h.crashGroupMergeService.BackfillCrashGroupMerges(req)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to execute crash group backfill merge")
		return
	}

	response.Success(c, http.StatusOK, report)
}

// GetCrashGroup godoc
// @Summary Get crash group by ID
// @Tags Admin - Crash Groups
// @Param id path string true "CrashGroup UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.CrashGroupResponse} "Success"
// @Router /admin/v1/crash-groups/{id} [get]
func (h *AdminBugHandler) GetCrashGroup(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid crash group ID format")
		return
	}

	group, err := h.service.GetCrashGroup(id)
	if err != nil {
		if errors.Is(err, service.ErrCrashGroupNotFound) {
			response.Error(c, http.StatusNotFound, "CRASH_GROUP_NOT_FOUND", "Crash group not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get crash group")
		return
	}

	response.Success(c, http.StatusOK, group)
}

// UpdateCrashGroup godoc
// @Summary Update crash group
// @Tags Admin - Crash Groups
// @Param id path string true "CrashGroup UUID"
// @Param request body dto.UpdateCrashGroupRequest true "Update data"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.CrashGroupResponse} "Success"
// @Router /admin/v1/crash-groups/{id} [patch]
func (h *AdminBugHandler) UpdateCrashGroup(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid crash group ID format")
		return
	}

	var req dto.UpdateCrashGroupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	group, err := h.service.UpdateCrashGroup(id, req)
	if err != nil {
		if errors.Is(err, service.ErrCrashGroupNotFound) {
			response.Error(c, http.StatusNotFound, "CRASH_GROUP_NOT_FOUND", "Crash group not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to update crash group")
		return
	}

	response.Success(c, http.StatusOK, group)
}

// MergeCrashGroups godoc
// @Summary Merge crash groups
// @Tags Admin - Crash Groups
// @Param request body dto.MergeCrashGroupsRequest true "Merge data"
// @Security BearerAuth
// @Success 200 {object} response.Response "Success"
// @Router /admin/v1/crash-groups/merge [post]
func (h *AdminBugHandler) MergeCrashGroups(c *gin.Context) {
	var req dto.MergeCrashGroupsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	targetID, err := uuid.Parse(req.TargetID)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid target ID format")
		return
	}

	sourceIDs := make([]uuid.UUID, len(req.SourceIDs))
	for i, s := range req.SourceIDs {
		id, err := uuid.Parse(s)
		if err != nil {
			response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid source ID format")
			return
		}
		sourceIDs[i] = id
	}

	if err := h.service.MergeCrashGroups(targetID, sourceIDs); err != nil {
		if errors.Is(err, service.ErrCrashGroupNotFound) {
			response.Error(c, http.StatusNotFound, "CRASH_GROUP_NOT_FOUND", "Target crash group not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to merge crash groups")
		return
	}

	response.Success(c, http.StatusOK, gin.H{"message": "Crash groups merged successfully"})
}

// ListGroupCrashes godoc
// @Summary List crashes in a crash group
// @Tags Admin - Crash Groups
// @Param id path string true "CrashGroup UUID"
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Security BearerAuth
// @Success 200 {object} response.Response{data=response.PaginatedData} "Success"
// @Router /admin/v1/crash-groups/{id}/crashes [get]
func (h *AdminBugHandler) ListGroupCrashes(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid crash group ID format")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)

	crashes, total, err := h.service.ListGroupCrashes(id, page, perPage)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list group crashes")
		return
	}

	response.Paginated(c, crashes, total, page, perPage)
}

// CrashGroupStats godoc
// @Summary Get crash group statistics
// @Tags Admin - Crash Groups
// @Security BearerAuth
// @Success 200 {object} response.Response "Success"
// @Router /admin/v1/crash-groups/stats [get]
func (h *AdminBugHandler) CrashGroupStats(c *gin.Context) {
	brand := c.Query("brand")
	stats, err := h.service.GetCrashGroupStats(brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get crash group stats")
		return
	}

	response.Success(c, http.StatusOK, stats)
}

// GetCrashLog godoc
// @Summary Get crash diagnostic log
// @Description Retrieve the diagnostic log attached to a crash report
// @Tags Admin - Crashes
// @Param id path string true "Crash UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response "Success"
// @Router /admin/v1/crashes/{id}/log [get]
func (h *AdminBugHandler) GetCrashLog(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid crash ID format")
		return
	}

	log, err := h.service.GetDiagnosticLog("crash", id)
	if err != nil {
		if errors.Is(err, service.ErrLogNotFound) {
			response.Error(c, http.StatusNotFound, "LOG_NOT_FOUND", "No diagnostic log for this crash report")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get diagnostic log")
		return
	}

	response.Success(c, http.StatusOK, log)
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
