package repository

import (
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/assistant/model"
	"gorm.io/gorm"
)

type ChatRepository struct {
	db *gorm.DB
}

func NewChatRepository(db *gorm.DB) *ChatRepository {
	return &ChatRepository{db: db}
}

func (r *ChatRepository) CreateSession(session *model.ChatSession) error {
	return r.db.Create(session).Error
}

func (r *ChatRepository) FindSessionByID(id uuid.UUID) (*model.ChatSession, error) {
	var session model.ChatSession
	if err := r.db.Preload("Messages", func(db *gorm.DB) *gorm.DB {
		return db.Order("created_at ASC").Limit(200)
	}).Where("id = ?", id).First(&session).Error; err != nil {
		return nil, err
	}
	return &session, nil
}

func (r *ChatRepository) UpdateSession(session *model.ChatSession) error {
	return r.db.Save(session).Error
}

func (r *ChatRepository) ListByDevice(deviceID uuid.UUID) ([]model.ChatSession, error) {
	var sessions []model.ChatSession
	if err := r.db.Preload("Messages", func(db *gorm.DB) *gorm.DB {
		return db.Order("created_at ASC").Limit(50)
	}).Where("device_id = ?", deviceID).Order("updated_at DESC").Limit(100).Find(&sessions).Error; err != nil {
		return nil, err
	}
	return sessions, nil
}

func (r *ChatRepository) List(page, perPage int, status, brand string) ([]model.ChatSession, int64, error) {
	var sessions []model.ChatSession
	var total int64

	query := r.db.Model(&model.ChatSession{})
	if status != "" {
		query = query.Where("status = ?", status)
	}
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("updated_at DESC").Offset(offset).Limit(perPage).Find(&sessions).Error; err != nil {
		return nil, 0, err
	}

	return sessions, total, nil
}

func (r *ChatRepository) CreateMessage(msg *model.ChatMessage) error {
	return r.db.Create(msg).Error
}

func (r *ChatRepository) CountSessions(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.ChatSession{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.Count(&count).Error
	return count, err
}

func (r *ChatRepository) CountActiveSessions(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.ChatSession{}).Where("status = ?", "active")
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.Count(&count).Error
	return count, err
}

func (r *ChatRepository) CountMessages(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.ChatMessage{})
	if brand != "" {
		query = query.Where("session_id IN (SELECT id FROM chat_sessions WHERE device_id IN (SELECT id FROM devices WHERE brand = ?))", brand)
	}
	err := query.Count(&count).Error
	return count, err
}

func (r *ChatRepository) TotalTokensUsed(brand string) (int64, error) {
	var total int64
	query := r.db.Model(&model.ChatMessage{}).Select("COALESCE(SUM(tokens_used), 0)")
	if brand != "" {
		query = query.Where("session_id IN (SELECT id FROM chat_sessions WHERE device_id IN (SELECT id FROM devices WHERE brand = ?))", brand)
	}
	err := query.Scan(&total).Error
	return total, err
}
