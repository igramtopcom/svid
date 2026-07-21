package handler

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/assistant/dto"
	"github.com/snakeloader/backend/internal/assistant/service"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"github.com/snakeloader/backend/internal/pkg/validator"
	"github.com/snakeloader/backend/internal/response"
)

// AdminAssistantHandler handles admin-facing AI assistant endpoints
type AdminAssistantHandler struct {
	service *service.AssistantService
}

func NewAdminAssistantHandler(svc *service.AssistantService) *AdminAssistantHandler {
	return &AdminAssistantHandler{service: svc}
}

// ==================== Chat Sessions ====================

// ListSessions godoc
// @Summary List all chat sessions
// @Description Returns a paginated list of all AI assistant chat sessions with optional status filter
// @Tags Admin - AI Sessions
// @Accept json
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param status query string false "Filter by session status (active, closed, escalated)"
// @Param brand query string false "Filter by brand (ssvid, vidcombo)"
// @Security BearerAuth
// @Success 200 {object} response.PaginatedData{data=[]dto.SessionListResponse} "Paginated list of sessions"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing JWT token"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/assistant/sessions [get]
func (h *AdminAssistantHandler) ListSessions(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)
	brand := c.Query("brand")

	sessions, total, err := h.service.ListSessions(page, perPage, c.Query("status"), brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list sessions")
		return
	}

	response.Paginated(c, sessions, total, page, perPage)
}

// GetSession godoc
// @Summary Get a chat session by ID
// @Description Returns a specific AI assistant chat session with all messages (admin access)
// @Tags Admin - AI Sessions
// @Accept json
// @Produce json
// @Param id path string true "Session ID (UUID)"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.SessionResponse} "Chat session with messages"
// @Failure 400 {object} response.Response "Invalid session ID format"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing JWT token"
// @Failure 404 {object} response.Response "Session not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/assistant/sessions/{id} [get]
func (h *AdminAssistantHandler) GetSession(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid session ID format")
		return
	}

	session, err := h.service.GetSession(id)
	if err != nil {
		if errors.Is(err, service.ErrSessionNotFound) {
			response.Error(c, http.StatusNotFound, "SESSION_NOT_FOUND", "Chat session not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get session")
		return
	}

	response.Success(c, http.StatusOK, session)
}

// ==================== Knowledge Base ====================

// ListKnowledge godoc
// @Summary List knowledge base entries
// @Description Returns a paginated list of knowledge base entries with optional category and active filters
// @Tags Admin - Knowledge Base
// @Accept json
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param category query string false "Filter by category (faq, tutorial, troubleshooting)"
// @Param active query bool false "Filter active entries only"
// @Security BearerAuth
// @Success 200 {object} response.PaginatedData{data=[]dto.KnowledgeResponse} "Paginated list of knowledge base entries"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing JWT token"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/assistant/knowledge [get]
func (h *AdminAssistantHandler) ListKnowledge(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)
	activeOnly := c.Query("active") == "true"

	entries, total, err := h.service.ListKnowledge(page, perPage, c.Query("category"), activeOnly)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list knowledge base")
		return
	}

	response.Paginated(c, entries, total, page, perPage)
}

// CreateKnowledge godoc
// @Summary Create a knowledge base entry
// @Description Creates a new knowledge base entry for the AI assistant
// @Tags Admin - Knowledge Base
// @Accept json
// @Produce json
// @Param request body dto.CreateKnowledgeRequest true "Knowledge base entry details"
// @Security BearerAuth
// @Success 201 {object} response.Response{data=dto.KnowledgeResponse} "Created knowledge base entry"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing JWT token"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/assistant/knowledge [post]
func (h *AdminAssistantHandler) CreateKnowledge(c *gin.Context) {
	var req dto.CreateKnowledgeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	kb, err := h.service.CreateKnowledge(req)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to create knowledge base entry")
		return
	}

	response.Success(c, http.StatusCreated, kb)
}

// GetKnowledge godoc
// @Summary Get a knowledge base entry by ID
// @Description Returns a specific knowledge base entry
// @Tags Admin - Knowledge Base
// @Accept json
// @Produce json
// @Param id path string true "Knowledge base entry ID (UUID)"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.KnowledgeResponse} "Knowledge base entry"
// @Failure 400 {object} response.Response "Invalid knowledge base ID format"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing JWT token"
// @Failure 404 {object} response.Response "Knowledge base entry not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/assistant/knowledge/{id} [get]
func (h *AdminAssistantHandler) GetKnowledge(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid knowledge base ID format")
		return
	}

	kb, err := h.service.GetKnowledge(id)
	if err != nil {
		if errors.Is(err, service.ErrKnowledgeNotFound) {
			response.Error(c, http.StatusNotFound, "KNOWLEDGE_NOT_FOUND", "Knowledge base entry not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get knowledge base entry")
		return
	}

	response.Success(c, http.StatusOK, kb)
}

// UpdateKnowledge godoc
// @Summary Update a knowledge base entry
// @Description Updates an existing knowledge base entry (partial update supported)
// @Tags Admin - Knowledge Base
// @Accept json
// @Produce json
// @Param id path string true "Knowledge base entry ID (UUID)"
// @Param request body dto.UpdateKnowledgeRequest true "Fields to update"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.KnowledgeResponse} "Updated knowledge base entry"
// @Failure 400 {object} response.Response "Invalid knowledge base ID or validation error"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing JWT token"
// @Failure 404 {object} response.Response "Knowledge base entry not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/assistant/knowledge/{id} [patch]
func (h *AdminAssistantHandler) UpdateKnowledge(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid knowledge base ID format")
		return
	}

	var req dto.UpdateKnowledgeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	kb, err := h.service.UpdateKnowledge(id, req)
	if err != nil {
		if errors.Is(err, service.ErrKnowledgeNotFound) {
			response.Error(c, http.StatusNotFound, "KNOWLEDGE_NOT_FOUND", "Knowledge base entry not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to update knowledge base entry")
		return
	}

	response.Success(c, http.StatusOK, kb)
}

// DeleteKnowledge godoc
// @Summary Delete a knowledge base entry
// @Description Permanently deletes a knowledge base entry
// @Tags Admin - Knowledge Base
// @Accept json
// @Produce json
// @Param id path string true "Knowledge base entry ID (UUID)"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=object} "Deletion confirmation"
// @Failure 400 {object} response.Response "Invalid knowledge base ID format"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing JWT token"
// @Failure 404 {object} response.Response "Knowledge base entry not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/assistant/knowledge/{id} [delete]
func (h *AdminAssistantHandler) DeleteKnowledge(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid knowledge base ID format")
		return
	}

	if err := h.service.DeleteKnowledge(id); err != nil {
		if errors.Is(err, service.ErrKnowledgeNotFound) {
			response.Error(c, http.StatusNotFound, "KNOWLEDGE_NOT_FOUND", "Knowledge base entry not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to delete knowledge base entry")
		return
	}

	response.Success(c, http.StatusOK, gin.H{"deleted": true})
}

// ==================== Stats ====================

// AssistantStats godoc
// @Summary Get AI assistant statistics
// @Description Returns statistics about AI assistant usage including session counts, message counts, and escalation rates
// @Tags Admin - AI Sessions
// @Accept json
// @Produce json
// @Param brand query string false "Filter by brand (ssvid, vidcombo)"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=object} "Assistant statistics"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing JWT token"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/assistant/stats [get]
func (h *AdminAssistantHandler) AssistantStats(c *gin.Context) {
	brand := c.Query("brand")
	stats, err := h.service.GetAssistantStats(brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get assistant stats")
		return
	}

	response.Success(c, http.StatusOK, stats)
}
