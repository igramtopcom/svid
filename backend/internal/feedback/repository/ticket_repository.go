package repository

import (
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/feedback/model"
	"github.com/snakeloader/backend/internal/pkg/timeutil"
	"gorm.io/gorm"
	"time"
)

type TicketRepository struct {
	db *gorm.DB
}

func NewTicketRepository(db *gorm.DB) *TicketRepository {
	return &TicketRepository{db: db}
}

func (r *TicketRepository) Create(ticket *model.Ticket) error {
	return r.db.Create(ticket).Error
}

func (r *TicketRepository) FindByID(id uuid.UUID) (*model.Ticket, error) {
	var ticket model.Ticket
	if err := r.db.Preload("Messages", func(db *gorm.DB) *gorm.DB {
		return db.Order("created_at ASC").Limit(200)
	}).Where("id = ?", id).First(&ticket).Error; err != nil {
		return nil, err
	}
	return &ticket, nil
}

func (r *TicketRepository) Update(ticket *model.Ticket) error {
	return r.db.Save(ticket).Error
}

func (r *TicketRepository) ListByDevice(deviceID uuid.UUID) ([]model.Ticket, error) {
	var tickets []model.Ticket
	if err := r.db.Preload("Messages", func(db *gorm.DB) *gorm.DB {
		return db.Order("created_at ASC").Limit(50)
	}).Where("device_id = ?", deviceID).Order("created_at DESC").Limit(100).Find(&tickets).Error; err != nil {
		return nil, err
	}
	return tickets, nil
}

func (r *TicketRepository) List(page, perPage int, status, category, priority, brand, search, deviceID string) ([]model.Ticket, int64, error) {
	var tickets []model.Ticket
	var total int64

	query := r.db.Model(&model.Ticket{})

	if status != "" {
		query = query.Where("status = ?", status)
	}
	if category != "" {
		query = query.Where("category = ?", category)
	}
	if priority != "" {
		query = query.Where("priority = ?", priority)
	}
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	if deviceID != "" {
		query = query.Where("device_id = ?", deviceID)
	}
	if search != "" {
		like := "%" + search + "%"
		query = query.Where("subject ILIKE ?", like)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("created_at DESC").Offset(offset).Limit(perPage).Find(&tickets).Error; err != nil {
		return nil, 0, err
	}

	return tickets, total, nil
}

func (r *TicketRepository) CreateMessage(msg *model.TicketMessage) error {
	return r.db.Create(msg).Error
}

func (r *TicketRepository) CountAll(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.Ticket{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.Count(&count).Error
	return count, err
}

func (r *TicketRepository) CountByStatus(brand string) (map[string]int64, error) {
	type result struct {
		Status string
		Count  int64
	}
	var results []result
	query := r.db.Model(&model.Ticket{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.Select("status, count(*) as count").Group("status").Find(&results).Error
	if err != nil {
		return nil, err
	}
	counts := make(map[string]int64)
	for _, r := range results {
		counts[r.Status] = r.Count
	}
	return counts, nil
}

func (r *TicketRepository) CountOpenToday(brand string) (int64, error) {
	var count int64
	today, tomorrow := timeutil.UTCDayBounds(time.Now())
	query := r.db.Model(&model.Ticket{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.
		Where("status IN (?, ?) AND created_at >= ? AND created_at < ?", "open", "in_progress", today, tomorrow).
		Count(&count).Error
	return count, err
}
