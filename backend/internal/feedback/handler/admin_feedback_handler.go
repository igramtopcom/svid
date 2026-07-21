package handler

import (
	"errors"
	"fmt"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/feedback/dto"
	"github.com/snakeloader/backend/internal/feedback/service"
	"github.com/snakeloader/backend/internal/middleware"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"github.com/snakeloader/backend/internal/pkg/sse"
	"github.com/snakeloader/backend/internal/pkg/validator"
	"github.com/snakeloader/backend/internal/response"
)

// AdminFeedbackHandler handles admin-facing feedback endpoints
type AdminFeedbackHandler struct {
	service *service.FeedbackService
	hub     *sse.Hub
}

func NewAdminFeedbackHandler(svc *service.FeedbackService, hub *sse.Hub) *AdminFeedbackHandler {
	return &AdminFeedbackHandler{service: svc, hub: hub}
}

// ==================== Tickets ====================

// ListTickets godoc
// @Summary List all tickets
// @Description Returns a paginated list of all support tickets with optional filters
// @Tags Admin - Tickets
// @Accept json
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param status query string false "Filter by status"
// @Param category query string false "Filter by category"
// @Param priority query string false "Filter by priority"
// @Param brand query string false "Filter by brand (e.g. svid, vidcombo)"
// @Param device_id query string false "Filter by device UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response "Paginated list of tickets"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/tickets [get]
func (h *AdminFeedbackHandler) ListTickets(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)

	tickets, total, err := h.service.ListTickets(
		page, perPage,
		c.Query("status"),
		c.Query("category"),
		c.Query("priority"),
		c.Query("brand"),
		c.Query("search"),
		c.Query("device_id"),
	)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list tickets")
		return
	}

	response.Paginated(c, tickets, total, page, perPage)
}

// GetTicket godoc
// @Summary Get a ticket by ID
// @Description Returns detailed information about a specific ticket including messages
// @Tags Admin - Tickets
// @Accept json
// @Produce json
// @Param id path string true "Ticket ID (UUID)"
// @Security BearerAuth
// @Success 200 {object} response.Response "Ticket details"
// @Failure 400 {object} response.Response "Invalid ticket ID format"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Ticket not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/tickets/{id} [get]
func (h *AdminFeedbackHandler) GetTicket(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid ticket ID format")
		return
	}

	ticket, err := h.service.GetTicket(id)
	if err != nil {
		if errors.Is(err, service.ErrTicketNotFound) {
			response.Error(c, http.StatusNotFound, "TICKET_NOT_FOUND", "Ticket not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get ticket")
		return
	}

	response.Success(c, http.StatusOK, ticket)
}

// UpdateTicket godoc
// @Summary Update a ticket
// @Description Updates ticket properties such as status, priority, or assigned admin
// @Tags Admin - Tickets
// @Accept json
// @Produce json
// @Param id path string true "Ticket ID (UUID)"
// @Param request body dto.UpdateTicketRequest true "Ticket update data"
// @Security BearerAuth
// @Success 200 {object} response.Response "Updated ticket"
// @Failure 400 {object} response.Response "Invalid ticket ID or validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Ticket not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/tickets/{id} [patch]
func (h *AdminFeedbackHandler) UpdateTicket(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid ticket ID format")
		return
	}

	var req dto.UpdateTicketRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	ticket, err := h.service.UpdateTicket(id, req)
	if err != nil {
		if errors.Is(err, service.ErrTicketNotFound) {
			response.Error(c, http.StatusNotFound, "TICKET_NOT_FOUND", "Ticket not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to update ticket")
		return
	}

	response.Success(c, http.StatusOK, ticket)
}

// AdminReply godoc
// @Summary Reply to a ticket as admin
// @Description Sends an admin reply message to a ticket
// @Tags Admin - Tickets
// @Accept json
// @Produce json
// @Param id path string true "Ticket ID (UUID)"
// @Param request body dto.SendMessageRequest true "Message content"
// @Security BearerAuth
// @Success 201 {object} response.Response "Message sent successfully"
// @Failure 400 {object} response.Response "Invalid ticket ID or validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Ticket not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/tickets/{id}/messages [post]
func (h *AdminFeedbackHandler) AdminReply(c *gin.Context) {
	adminID, _ := c.Get(middleware.AdminIDKey)

	ticketID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid ticket ID format")
		return
	}

	var req dto.SendMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	msg, err := h.service.SendAdminMessage(ticketID, adminID.(uuid.UUID), req)
	if err != nil {
		if errors.Is(err, service.ErrTicketNotFound) {
			response.Error(c, http.StatusNotFound, "TICKET_NOT_FOUND", "Ticket not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to send message")
		return
	}

	response.Success(c, http.StatusCreated, msg)
}

// ==================== Feature Requests ====================

// ListFeatureRequests godoc
// @Summary List all feature requests
// @Description Returns a paginated list of all feature requests with optional filters
// @Tags Admin - Feature Requests
// @Accept json
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param status query string false "Filter by status"
// @Param sort query string false "Sort by field (created_at, upvotes)" default(created_at)
// @Param brand query string false "Filter by brand (e.g. svid, vidcombo)"
// @Security BearerAuth
// @Success 200 {object} response.Response "Paginated list of feature requests"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/features [get]
func (h *AdminFeedbackHandler) ListFeatureRequests(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)
	sortBy := c.DefaultQuery("sort", "created_at")

	features, total, err := h.service.ListFeatureRequests(
		page, perPage,
		c.Query("status"),
		sortBy,
		c.Query("brand"),
		c.Query("search"),
	)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list feature requests")
		return
	}

	response.Paginated(c, features, total, page, perPage)
}

// GetFeatureRequest godoc
// @Summary Get a feature request by ID
// @Description Returns detailed information about a specific feature request
// @Tags Admin - Feature Requests
// @Accept json
// @Produce json
// @Param id path string true "Feature Request ID (UUID)"
// @Security BearerAuth
// @Success 200 {object} response.Response "Feature request details"
// @Failure 400 {object} response.Response "Invalid feature request ID format"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Feature request not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/features/{id} [get]
func (h *AdminFeedbackHandler) GetFeatureRequest(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid feature request ID format")
		return
	}

	fr, err := h.service.GetFeatureRequest(id)
	if err != nil {
		if errors.Is(err, service.ErrFeatureRequestNotFound) {
			response.Error(c, http.StatusNotFound, "FEATURE_NOT_FOUND", "Feature request not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get feature request")
		return
	}

	response.Success(c, http.StatusOK, fr)
}

// UpdateFeatureRequest godoc
// @Summary Update a feature request
// @Description Updates feature request properties such as status or admin notes
// @Tags Admin - Feature Requests
// @Accept json
// @Produce json
// @Param id path string true "Feature Request ID (UUID)"
// @Param request body dto.UpdateFeatureRequestRequest true "Feature request update data"
// @Security BearerAuth
// @Success 200 {object} response.Response "Updated feature request"
// @Failure 400 {object} response.Response "Invalid feature request ID or validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Feature request not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/features/{id} [patch]
func (h *AdminFeedbackHandler) UpdateFeatureRequest(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid feature request ID format")
		return
	}

	var req dto.UpdateFeatureRequestRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	fr, err := h.service.UpdateFeatureRequest(id, req)
	if err != nil {
		if errors.Is(err, service.ErrFeatureRequestNotFound) {
			response.Error(c, http.StatusNotFound, "FEATURE_NOT_FOUND", "Feature request not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to update feature request")
		return
	}

	response.Success(c, http.StatusOK, fr)
}

// ==================== Ratings ====================

// ListRatings godoc
// @Summary List all ratings
// @Description Returns a paginated list of all app ratings with optional rating filter
// @Tags Admin - Ratings
// @Accept json
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param rating query int false "Filter by specific rating value (1-5)"
// @Param brand query string false "Filter by brand (e.g. svid, vidcombo)"
// @Security BearerAuth
// @Success 200 {object} response.Response "Paginated list of ratings"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/ratings [get]
func (h *AdminFeedbackHandler) ListRatings(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)
	ratingFilter, _ := strconv.Atoi(c.DefaultQuery("rating", "0"))
	sort := c.DefaultQuery("sort", "date")

	ratings, total, err := h.service.ListRatings(page, perPage, ratingFilter, sort, c.Query("brand"))
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list ratings")
		return
	}

	response.Paginated(c, ratings, total, page, perPage)
}

// RatingStats godoc
// @Summary Get rating statistics
// @Description Returns aggregated statistics about app ratings including average and distribution
// @Tags Admin - Ratings
// @Accept json
// @Produce json
// @Security BearerAuth
// @Success 200 {object} response.Response "Rating statistics"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/ratings/stats [get]
func (h *AdminFeedbackHandler) RatingStats(c *gin.Context) {
	brand := c.Query("brand")
	stats, err := h.service.GetRatingStats(brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get rating stats")
		return
	}

	response.Success(c, http.StatusOK, stats)
}

// ==================== Combined Stats ====================

// FeedbackStats godoc
// @Summary Get combined feedback statistics
// @Description Returns aggregated statistics across all feedback types (tickets, features, ratings)
// @Tags Admin - Feedback
// @Accept json
// @Produce json
// @Security BearerAuth
// @Success 200 {object} response.Response "Combined feedback statistics"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /admin/v1/feedback/stats [get]
func (h *AdminFeedbackHandler) FeedbackStats(c *gin.Context) {
	brand := c.Query("brand")
	stats, err := h.service.GetFeedbackStats(brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get feedback stats")
		return
	}

	response.Success(c, http.StatusOK, stats)
}

// ==================== SSE Streaming ====================

// StreamTicket godoc
// @Summary Stream real-time ticket updates (admin)
// @Description Opens an SSE connection for real-time ticket message updates
// @Tags Admin - Tickets
// @Produce text/event-stream
// @Param id path string true "Ticket ID (UUID)"
// @Security BearerAuth
// @Success 200 {string} string "SSE stream"
// @Failure 400 {object} response.Response "Invalid ticket ID format"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Ticket not found"
// @Router /admin/v1/tickets/{id}/stream [get]
func (h *AdminFeedbackHandler) StreamTicket(c *gin.Context) {
	ticketID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid ticket ID format")
		return
	}

	// Verify ticket exists
	_, err = h.service.GetTicket(ticketID)
	if err != nil {
		if errors.Is(err, service.ErrTicketNotFound) {
			response.Error(c, http.StatusNotFound, "TICKET_NOT_FOUND", "Ticket not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to verify ticket")
		return
	}

	topic := fmt.Sprintf("ticket:%s", ticketID.String())
	if !sse.StreamHandler(c, h.hub, topic) {
		response.Error(c, http.StatusTooManyRequests, "SSE_LIMIT_REACHED", "Too many active connections for this topic")
	}
}

// StreamNotifications godoc
// @Summary Stream real-time admin notifications
// @Description Opens an SSE connection for real-time admin notifications (new tickets, messages, escalations)
// @Tags Admin - Feedback
// @Produce text/event-stream
// @Security BearerAuth
// @Success 200 {string} string "SSE stream"
// @Failure 401 {object} response.Response "Unauthorized"
// @Router /admin/v1/notifications/stream [get]
func (h *AdminFeedbackHandler) StreamNotifications(c *gin.Context) {
	if !sse.StreamHandler(c, h.hub, "admin:notifications") {
		response.Error(c, http.StatusTooManyRequests, "SSE_LIMIT_REACHED", "Too many active connections")
	}
}
