package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type FeatureRequest struct {
	ID          uuid.UUID     `gorm:"type:uuid;primaryKey"`
	DeviceID    uuid.UUID     `gorm:"type:uuid;not null;index"`
	Title       string        `gorm:"size:500;not null"`
	Description string        `gorm:"type:text;not null"`
	Status      string        `gorm:"size:20;not null;default:'pending';index"` // pending, planned, in_progress, completed, declined
	Upvotes     int           `gorm:"default:0"`
	AdminNotes  string        `gorm:"type:text"`
	CreatedAt   time.Time     `gorm:"index"`
	UpdatedAt   time.Time
	Votes       []FeatureVote `gorm:"foreignKey:FeatureRequestID;constraint:OnDelete:CASCADE"`
}

func (f *FeatureRequest) BeforeCreate(tx *gorm.DB) error {
	if f.ID == uuid.Nil {
		f.ID = uuid.New()
	}
	if f.Status == "" {
		f.Status = "pending"
	}
	return nil
}

type FeatureVote struct {
	ID               uuid.UUID `gorm:"type:uuid;primaryKey"`
	FeatureRequestID uuid.UUID `gorm:"type:uuid;not null;uniqueIndex:idx_feature_device"`
	DeviceID         uuid.UUID `gorm:"type:uuid;not null;uniqueIndex:idx_feature_device"`
	CreatedAt        time.Time
}

func (v *FeatureVote) BeforeCreate(tx *gorm.DB) error {
	if v.ID == uuid.Nil {
		v.ID = uuid.New()
	}
	return nil
}
