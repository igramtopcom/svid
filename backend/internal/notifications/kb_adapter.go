package notifications

import (
	"github.com/snakeloader/backend/internal/assistant/repository"
)

// KBAdapter bridges the assistant knowledge base repository to the autonomous agent.
type KBAdapter struct {
	repo *repository.KnowledgeRepository
}

// NewKBAdapter creates a knowledge base adapter.
func NewKBAdapter(repo *repository.KnowledgeRepository) *KBAdapter {
	if repo == nil {
		return nil
	}
	return &KBAdapter{repo: repo}
}

// GetActiveKnowledge returns all active knowledge base entries.
func (a *KBAdapter) GetActiveKnowledge() ([]KnowledgeEntry, error) {
	if a == nil {
		return nil, nil
	}

	entries, err := a.repo.ListActive()
	if err != nil {
		return nil, err
	}

	result := make([]KnowledgeEntry, len(entries))
	for i, e := range entries {
		result[i] = KnowledgeEntry{
			Category: e.Category,
			Title:    e.Title,
			Content:  e.Content,
		}
	}
	return result, nil
}
