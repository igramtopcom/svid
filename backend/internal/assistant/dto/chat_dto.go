package dto

import (
	"github.com/snakeloader/backend/internal/assistant/model"
)

// --- Requests ---

type CreateSessionRequest struct {
	Message string `json:"message" binding:"required"`
}

type SendMessageRequest struct {
	Message string `json:"message" binding:"required"`
}

type EscalateRequest struct {
	Subject string `json:"subject" binding:"required,max=500"`
}

// --- Responses ---

type SessionResponse struct {
	ID        string            `json:"id"`
	DeviceID  string            `json:"device_id"`
	Title     string            `json:"title"`
	Status    string            `json:"status"`
	CreatedAt string            `json:"created_at"`
	UpdatedAt string            `json:"updated_at"`
	Messages  []MessageResponse `json:"messages,omitempty"`
}

type SessionListResponse struct {
	ID        string `json:"id"`
	DeviceID  string `json:"device_id"`
	Title     string `json:"title"`
	Status    string `json:"status"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
}

type MessageResponse struct {
	ID         string `json:"id"`
	Role       string `json:"role"`
	Content    string `json:"content"`
	TokensUsed int    `json:"tokens_used,omitempty"`
	CreatedAt  string `json:"created_at"`
}

type ChatResponse struct {
	UserMessage      MessageResponse `json:"user_message"`
	AssistantMessage MessageResponse `json:"assistant_message"`
}

type EscalationResponse struct {
	Session  SessionResponse `json:"session"`
	TicketID string          `json:"ticket_id,omitempty"`
}

// --- Mappers ---

func SessionToResponse(s *model.ChatSession) SessionResponse {
	resp := SessionResponse{
		ID:        s.ID.String(),
		DeviceID:  s.DeviceID.String(),
		Title:     s.Title,
		Status:    s.Status,
		CreatedAt: s.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt: s.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
	if len(s.Messages) > 0 {
		resp.Messages = MessagesToResponse(s.Messages)
	}
	return resp
}

func SessionToListResponse(s *model.ChatSession) SessionListResponse {
	return SessionListResponse{
		ID:        s.ID.String(),
		DeviceID:  s.DeviceID.String(),
		Title:     s.Title,
		Status:    s.Status,
		CreatedAt: s.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt: s.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
}

func SessionsToListResponse(sessions []model.ChatSession) []SessionListResponse {
	result := make([]SessionListResponse, len(sessions))
	for i := range sessions {
		result[i] = SessionToListResponse(&sessions[i])
	}
	return result
}

func MessageToResponse(m *model.ChatMessage) MessageResponse {
	return MessageResponse{
		ID:         m.ID.String(),
		Role:       m.Role,
		Content:    m.Content,
		TokensUsed: m.TokensUsed,
		CreatedAt:  m.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
}

func MessagesToResponse(messages []model.ChatMessage) []MessageResponse {
	result := make([]MessageResponse, len(messages))
	for i := range messages {
		result[i] = MessageToResponse(&messages[i])
	}
	return result
}
