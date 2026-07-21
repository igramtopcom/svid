package handler

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/assistant/dto"
	"github.com/snakeloader/backend/internal/assistant/service"
	"github.com/snakeloader/backend/internal/middleware"
	"github.com/snakeloader/backend/internal/pkg/validator"
	"github.com/snakeloader/backend/internal/response"
)

// AssistantHandler handles device-facing AI assistant endpoints
type AssistantHandler struct {
	service *service.AssistantService
}

func NewAssistantHandler(svc *service.AssistantService) *AssistantHandler {
	return &AssistantHandler{service: svc}
}

// CreateSession godoc
// @Summary Create a new chat session
// @Description Creates a new AI assistant chat session for the authenticated device with an initial message
// @Tags AI Assistant
// @Accept json
// @Produce json
// @Param request body dto.CreateSessionRequest true "Initial message to start the session"
// @Security ApiKeyAuth
// @Success 201 {object} response.Response{data=dto.SessionResponse} "Session created successfully"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing API key"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/assistant/sessions [post]
func (h *AssistantHandler) CreateSession(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

	var req dto.CreateSessionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	session, err := h.service.CreateSession(deviceID.(uuid.UUID), req)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to create chat session")
		return
	}

	response.Success(c, http.StatusCreated, session)
}

// ListSessions godoc
// @Summary List device chat sessions
// @Description Returns all AI assistant chat sessions for the authenticated device
// @Tags AI Assistant
// @Accept json
// @Produce json
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=[]dto.SessionListResponse} "List of chat sessions"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing API key"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/assistant/sessions [get]
func (h *AssistantHandler) ListSessions(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

	sessions, err := h.service.ListDeviceSessions(deviceID.(uuid.UUID))
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list sessions")
		return
	}

	response.Success(c, http.StatusOK, sessions)
}

// GetSession godoc
// @Summary Get a chat session by ID
// @Description Returns a specific AI assistant chat session with all messages for the authenticated device
// @Tags AI Assistant
// @Accept json
// @Produce json
// @Param id path string true "Session ID (UUID)"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=dto.SessionResponse} "Chat session with messages"
// @Failure 400 {object} response.Response "Invalid session ID format"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing API key"
// @Failure 403 {object} response.Response "Access denied - Session belongs to another device"
// @Failure 404 {object} response.Response "Session not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/assistant/sessions/{id} [get]
func (h *AssistantHandler) GetSession(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid session ID format")
		return
	}

	session, err := h.service.GetDeviceSession(id, deviceID.(uuid.UUID))
	if err != nil {
		if errors.Is(err, service.ErrSessionNotFound) {
			response.Error(c, http.StatusNotFound, "SESSION_NOT_FOUND", "Chat session not found")
			return
		}
		if errors.Is(err, service.ErrSessionAccessDenied) {
			response.Error(c, http.StatusForbidden, "ACCESS_DENIED", "You do not have access to this session")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get session")
		return
	}

	response.Success(c, http.StatusOK, session)
}

// SendMessage godoc
// @Summary Send a message to a chat session
// @Description Sends a user message to an existing chat session and receives an AI assistant response
// @Tags AI Assistant
// @Accept json
// @Produce json
// @Param id path string true "Session ID (UUID)"
// @Param request body dto.SendMessageRequest true "Message content"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=dto.ChatResponse} "User and assistant messages"
// @Failure 400 {object} response.Response "Invalid session ID or validation error or session closed"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing API key"
// @Failure 403 {object} response.Response "Access denied - Session belongs to another device"
// @Failure 404 {object} response.Response "Session not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/assistant/sessions/{id}/messages [post]
func (h *AssistantHandler) SendMessage(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid session ID format")
		return
	}

	var req dto.SendMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	chat, err := h.service.SendMessage(sessionID, deviceID.(uuid.UUID), req)
	if err != nil {
		if errors.Is(err, service.ErrSessionNotFound) {
			response.Error(c, http.StatusNotFound, "SESSION_NOT_FOUND", "Chat session not found")
			return
		}
		if errors.Is(err, service.ErrSessionAccessDenied) {
			response.Error(c, http.StatusForbidden, "ACCESS_DENIED", "You do not have access to this session")
			return
		}
		if errors.Is(err, service.ErrSessionClosed) {
			response.Error(c, http.StatusBadRequest, "SESSION_CLOSED", "This chat session is no longer active")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to send message")
		return
	}

	response.Success(c, http.StatusOK, chat)
}

// Escalate godoc
// @Summary Escalate a chat session to human support
// @Description Escalates the chat session to human support by creating a support ticket
// @Tags AI Assistant
// @Accept json
// @Produce json
// @Param id path string true "Session ID (UUID)"
// @Param request body dto.EscalateRequest true "Escalation details"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=dto.EscalationResponse} "Escalated session with ticket ID"
// @Failure 400 {object} response.Response "Invalid session ID or validation error"
// @Failure 401 {object} response.Response "Unauthorized - Invalid or missing API key"
// @Failure 403 {object} response.Response "Access denied - Session belongs to another device"
// @Failure 404 {object} response.Response "Session not found"
// @Failure 500 {object} response.Response "Internal server error"
// @Router /api/v1/assistant/sessions/{id}/escalate [post]
func (h *AssistantHandler) Escalate(c *gin.Context) {
	deviceID, _ := c.Get(middleware.DeviceIDKey)

	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid session ID format")
		return
	}

	var req dto.EscalateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	session, err := h.service.EscalateSession(sessionID, deviceID.(uuid.UUID), req)
	if err != nil {
		if errors.Is(err, service.ErrSessionNotFound) {
			response.Error(c, http.StatusNotFound, "SESSION_NOT_FOUND", "Chat session not found")
			return
		}
		if errors.Is(err, service.ErrSessionAccessDenied) {
			response.Error(c, http.StatusForbidden, "ACCESS_DENIED", "You do not have access to this session")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to escalate session")
		return
	}

	response.Success(c, http.StatusOK, session)
}
