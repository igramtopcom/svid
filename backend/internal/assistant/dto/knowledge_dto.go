package dto

import (
	"github.com/snakeloader/backend/internal/assistant/model"
)

// --- Requests ---

type CreateKnowledgeRequest struct {
	Title    string `json:"title" binding:"required,max=500"`
	Content  string `json:"content" binding:"required"`
	Category string `json:"category" binding:"required,oneof=faq tutorial troubleshooting"`
	Tags     string `json:"tags"`
	IsActive bool   `json:"is_active"`
}

type UpdateKnowledgeRequest struct {
	Title    *string `json:"title" binding:"omitempty,max=500"`
	Content  *string `json:"content"`
	Category *string `json:"category" binding:"omitempty,oneof=faq tutorial troubleshooting"`
	Tags     *string `json:"tags"`
	IsActive *bool   `json:"is_active"`
}

// --- Responses ---

type KnowledgeResponse struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Content   string `json:"content"`
	Category  string `json:"category"`
	Tags      string `json:"tags,omitempty"`
	IsActive  bool   `json:"is_active"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
}

// --- Mappers ---

func KnowledgeToResponse(k *model.KnowledgeBase) KnowledgeResponse {
	return KnowledgeResponse{
		ID:        k.ID.String(),
		Title:     k.Title,
		Content:   k.Content,
		Category:  k.Category,
		Tags:      k.Tags,
		IsActive:  k.IsActive,
		CreatedAt: k.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt: k.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
}

func KnowledgesToResponse(entries []model.KnowledgeBase) []KnowledgeResponse {
	result := make([]KnowledgeResponse, len(entries))
	for i := range entries {
		result[i] = KnowledgeToResponse(&entries[i])
	}
	return result
}
