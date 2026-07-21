package dto

import (
	"github.com/snakeloader/backend/internal/feedback/model"
)

// --- Requests ---

type CreateTicketRequest struct {
	Subject       string `json:"subject" binding:"required,max=500"`
	Category      string `json:"category" binding:"required,oneof=general billing technical feature_request"`
	Message       string `json:"message" binding:"required,max=50000"`          // Initial message content
	DiagnosticLog string `json:"diagnostic_log" binding:"omitempty,max=500000"` // last ~200 lines of app log
}

type UpdateTicketRequest struct {
	Status   *string `json:"status" binding:"omitempty,oneof=open in_progress waiting_for_customer resolved closed"`
	Priority *string `json:"priority" binding:"omitempty,oneof=low medium high critical"`
}

type SendMessageRequest struct {
	Content string `json:"content" binding:"required,max=50000"`
}

// --- Responses ---

type TicketResponse struct {
	ID          string            `json:"id"`
	DeviceID    string            `json:"device_id"`
	Subject     string            `json:"subject"`
	Category    string            `json:"category"`
	Status      string            `json:"status"`
	Priority    string            `json:"priority"`
	AISessionID string            `json:"ai_session_id,omitempty"`
	CreatedAt   string            `json:"created_at"`
	UpdatedAt   string            `json:"updated_at"`
	Messages    []MessageResponse `json:"messages,omitempty"`
}

type TicketListResponse struct {
	ID        string `json:"id"`
	DeviceID  string `json:"device_id"`
	Subject   string `json:"subject"`
	Category  string `json:"category"`
	Status    string `json:"status"`
	Priority  string `json:"priority"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
}

type MessageResponse struct {
	ID         string `json:"id"`
	TicketID   string `json:"ticket_id"`
	SenderType string `json:"sender_type"`
	SenderID   string `json:"sender_id"`
	Content    string `json:"content"`
	CreatedAt  string `json:"created_at"`
}

// --- Mappers ---

func TicketToResponse(t *model.Ticket) TicketResponse {
	resp := TicketResponse{
		ID:        t.ID.String(),
		DeviceID:  t.DeviceID.String(),
		Subject:   t.Subject,
		Category:  t.Category,
		Status:    t.Status,
		Priority:  t.Priority,
		CreatedAt: t.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt: t.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
	if t.AISessionID != nil {
		resp.AISessionID = t.AISessionID.String()
	}
	if len(t.Messages) > 0 {
		resp.Messages = MessagesToResponse(t.Messages)
	}
	return resp
}

func TicketToListResponse(t *model.Ticket) TicketListResponse {
	return TicketListResponse{
		ID:        t.ID.String(),
		DeviceID:  t.DeviceID.String(),
		Subject:   t.Subject,
		Category:  t.Category,
		Status:    t.Status,
		Priority:  t.Priority,
		CreatedAt: t.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt: t.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
}

func TicketsToListResponse(tickets []model.Ticket) []TicketListResponse {
	result := make([]TicketListResponse, len(tickets))
	for i := range tickets {
		result[i] = TicketToListResponse(&tickets[i])
	}
	return result
}

func MessageToResponse(m *model.TicketMessage) MessageResponse {
	return MessageResponse{
		ID:         m.ID.String(),
		TicketID:   m.TicketID.String(),
		SenderType: m.SenderType,
		SenderID:   m.SenderID.String(),
		Content:    m.Content,
		CreatedAt:  m.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
}

func MessagesToResponse(messages []model.TicketMessage) []MessageResponse {
	result := make([]MessageResponse, len(messages))
	for i := range messages {
		result[i] = MessageToResponse(&messages[i])
	}
	return result
}
