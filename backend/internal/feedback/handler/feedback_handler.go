package handler

import (
	"errors"
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/feedback/dto"
	"github.com/snakeloader/backend/internal/feedback/service"
	"github.com/snakeloader/backend/internal/middleware"
	"github.com/snakeloader/backend/internal/pkg/sse"
	"github.com/snakeloader/backend/internal/pkg/validator"
	"github.com/snakeloader/backend/internal/response"
)

// FeedbackHandler handles device-facing feedback endpoints
type FeedbackHandler struct {
	service *service.FeedbackService
	hub     *sse.Hub
}

func NewFeedbackHandler(svc *service.FeedbackService, hub *sse.Hub) *FeedbackHandler {
	return &FeedbackHandler{service: svc, hub: hub}
}

// CreateTicket godoc
// @Summary Create a new support ticket
// @Description Creates a new support ticket for the authenticated device
// @Tags Tickets
// @Accept json
// @Produce json
// @Param request body dto.CreateTicketRequest true "Ticket creation request"
// @Security ApiKeyAuth
// @Success 201 {object} response.Response "Ticket created successfully"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/tickets [post]
func (h *FeedbackHandler) CreateTicket(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

	var req dto.CreateTicketRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	ticket, err := h.service.CreateTicket(deviceID.(uuid.UUID), req)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to create ticket")
		return
	}

	response.Success(c, http.StatusCreated, ticket)
}

// ListMyTickets godoc
// @Summary List device's tickets
// @Description Returns all support tickets created by the authenticated device
// @Tags Tickets
// @Accept json
// @Produce json
// @Security ApiKeyAuth
// @Success 200 {object} response.Response "List of tickets"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/tickets [get]
func (h *FeedbackHandler) ListMyTickets(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

	tickets, err := h.service.ListDeviceTickets(deviceID.(uuid.UUID))
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list tickets")
		return
	}

	response.Success(c, http.StatusOK, tickets)
}

// GetMyTicket godoc
// @Summary Get a specific ticket
// @Description Returns details of a specific ticket owned by the authenticated device
// @Tags Tickets
// @Accept json
// @Produce json
// @Param id path string true "Ticket ID (UUID)"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response "Ticket details"
// @Failure 400 {object} response.Response "Invalid ticket ID format"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 403 {object} response.Response "Access denied"
// @Failure 404 {object} response.Response "Ticket not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/tickets/{id} [get]
func (h *FeedbackHandler) GetMyTicket(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid ticket ID format")
		return
	}

	ticket, err := h.service.GetDeviceTicket(id, deviceID.(uuid.UUID))
	if err != nil {
		if errors.Is(err, service.ErrTicketNotFound) {
			response.Error(c, http.StatusNotFound, "TICKET_NOT_FOUND", "Ticket not found")
			return
		}
		if errors.Is(err, service.ErrTicketAccessDenied) {
			response.Error(c, http.StatusForbidden, "ACCESS_DENIED", "You do not have access to this ticket")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get ticket")
		return
	}

	response.Success(c, http.StatusOK, ticket)
}

// ReplyToTicket godoc
// @Summary Reply to a ticket
// @Description Sends a message reply to an existing ticket owned by the authenticated device
// @Tags Tickets
// @Accept json
// @Produce json
// @Param id path string true "Ticket ID (UUID)"
// @Param request body dto.SendMessageRequest true "Message content"
// @Security ApiKeyAuth
// @Success 201 {object} response.Response "Message sent successfully"
// @Failure 400 {object} response.Response "Invalid ticket ID or validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 403 {object} response.Response "Access denied"
// @Failure 404 {object} response.Response "Ticket not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/tickets/{id}/messages [post]
func (h *FeedbackHandler) ReplyToTicket(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

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

	msg, err := h.service.SendDeviceMessage(ticketID, deviceID.(uuid.UUID), req)
	if err != nil {
		if errors.Is(err, service.ErrTicketNotFound) {
			response.Error(c, http.StatusNotFound, "TICKET_NOT_FOUND", "Ticket not found")
			return
		}
		if errors.Is(err, service.ErrTicketAccessDenied) {
			response.Error(c, http.StatusForbidden, "ACCESS_DENIED", "You do not have access to this ticket")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to send message")
		return
	}

	response.Success(c, http.StatusCreated, msg)
}

// CreateFeatureRequest godoc
// @Summary Create a new feature request
// @Description Creates a new feature request submitted by the authenticated device
// @Tags Feature Requests
// @Accept json
// @Produce json
// @Param request body dto.CreateFeatureRequestRequest true "Feature request details"
// @Security ApiKeyAuth
// @Success 201 {object} response.Response "Feature request created successfully"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/features [post]
func (h *FeedbackHandler) CreateFeatureRequest(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

	var req dto.CreateFeatureRequestRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	fr, err := h.service.CreateFeatureRequest(deviceID.(uuid.UUID), req)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to create feature request")
		return
	}

	response.Success(c, http.StatusCreated, fr)
}

// ListFeatureRequests godoc
// @Summary List all feature requests
// @Description Returns a list of all feature requests sorted by upvotes
// @Tags Feature Requests
// @Accept json
// @Produce json
// @Security ApiKeyAuth
// @Success 200 {object} response.Response "List of feature requests with total count"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/features [get]
func (h *FeedbackHandler) ListFeatureRequests(c *gin.Context) {
	fr, total, err := h.service.ListFeatureRequests(1, 50, "", "upvotes", "", "")
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list feature requests")
		return
	}

	// Strip admin-only fields from device-facing response
	for i := range fr {
		fr[i].AdminNotes = ""
	}

	response.Success(c, http.StatusOK, gin.H{
		"items": fr,
		"total": total,
	})
}

// VoteFeatureRequest godoc
// @Summary Vote for a feature request
// @Description Adds an upvote from the authenticated device to a feature request
// @Tags Feature Requests
// @Accept json
// @Produce json
// @Param id path string true "Feature Request ID (UUID)"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response "Vote recorded successfully"
// @Failure 400 {object} response.Response "Invalid feature request ID format"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Feature request not found"
// @Failure 409 {object} response.Response "Already voted for this feature request"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/features/{id}/vote [post]
func (h *FeedbackHandler) VoteFeatureRequest(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

	featureID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid feature request ID format")
		return
	}

	vote, err := h.service.VoteFeatureRequest(featureID, deviceID.(uuid.UUID))
	if err != nil {
		if errors.Is(err, service.ErrFeatureRequestNotFound) {
			response.Error(c, http.StatusNotFound, "FEATURE_NOT_FOUND", "Feature request not found")
			return
		}
		if errors.Is(err, service.ErrAlreadyVoted) {
			response.Error(c, http.StatusConflict, "ALREADY_VOTED", "You have already voted for this feature request")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to vote")
		return
	}

	response.Success(c, http.StatusOK, vote)
}

// SubmitRating godoc
// @Summary Submit an app rating
// @Description Submits or updates a rating for the app from the authenticated device
// @Tags Ratings
// @Accept json
// @Produce json
// @Param request body dto.SubmitRatingRequest true "Rating details"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response "Rating submitted successfully"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/ratings [post]
func (h *FeedbackHandler) SubmitRating(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

	var req dto.SubmitRatingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	rating, err := h.service.SubmitRating(deviceID.(uuid.UUID), req)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to submit rating")
		return
	}

	response.Success(c, http.StatusOK, rating)
}

// StreamTicket godoc
// @Summary Stream real-time ticket updates
// @Description Opens an SSE connection for real-time ticket message updates
// @Tags Tickets
// @Produce text/event-stream
// @Param id path string true "Ticket ID (UUID)"
// @Security ApiKeyAuth
// @Success 200 {string} string "SSE stream"
// @Failure 400 {object} response.Response "Invalid ticket ID format"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 403 {object} response.Response "Access denied"
// @Failure 404 {object} response.Response "Ticket not found"
// @Router /api/v1/tickets/{id}/stream [get]
func (h *FeedbackHandler) StreamTicket(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

	ticketID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid ticket ID format")
		return
	}

	// Verify ownership
	_, err = h.service.GetDeviceTicket(ticketID, deviceID.(uuid.UUID))
	if err != nil {
		if errors.Is(err, service.ErrTicketNotFound) {
			response.Error(c, http.StatusNotFound, "TICKET_NOT_FOUND", "Ticket not found")
			return
		}
		if errors.Is(err, service.ErrTicketAccessDenied) {
			response.Error(c, http.StatusForbidden, "ACCESS_DENIED", "You do not have access to this ticket")
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
