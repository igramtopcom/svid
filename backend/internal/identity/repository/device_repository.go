package repository

import (
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/identity/model"
	"gorm.io/gorm"
)

type DeviceRepository struct {
	db *gorm.DB
}

func NewDeviceRepository(db *gorm.DB) *DeviceRepository {
	return &DeviceRepository{db: db}
}

func (r *DeviceRepository) FindByHardwareID(hardwareID string) (*model.Device, error) {
	var device model.Device
	err := r.db.Where("hardware_id = ?", hardwareID).First(&device).Error
	if err != nil {
		return nil, err
	}
	return &device, nil
}

// FindByBrandAndHardwareID looks up a device scoped to a specific brand.
// This prevents cross-brand collisions when the same physical device runs both Svid and VidCombo.
func (r *DeviceRepository) FindByBrandAndHardwareID(brand, hardwareID string) (*model.Device, error) {
	var device model.Device
	err := r.db.Where("brand = ? AND hardware_id = ?", brand, hardwareID).First(&device).Error
	if err != nil {
		return nil, err
	}
	return &device, nil
}

func (r *DeviceRepository) FindByID(id uuid.UUID) (*model.Device, error) {
	var device model.Device
	err := r.db.Where("id = ?", id).First(&device).Error
	if err != nil {
		return nil, err
	}
	return &device, nil
}

func (r *DeviceRepository) Create(device *model.Device) error {
	return r.db.Create(device).Error
}

func (r *DeviceRepository) Update(device *model.Device) error {
	return r.db.Save(device).Error
}

func (r *DeviceRepository) List(page, perPage int, os, brand, search string, isActive *bool) ([]model.Device, int64, error) {
	var devices []model.Device
	var total int64

	query := r.db.Model(&model.Device{})

	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	if os != "" {
		query = query.Where("os = ?", os)
	}
	if search != "" {
		like := "%" + search + "%"
		query = query.Where("device_name ILIKE ? OR hardware_id ILIKE ?", like, like)
	}
	if isActive != nil {
		query = query.Where("is_active = ?", *isActive)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("created_at DESC").Offset(offset).Limit(perPage).Find(&devices).Error; err != nil {
		return nil, 0, err
	}

	return devices, total, nil
}

// brandScope returns a query scoped to brand if non-empty.
func (r *DeviceRepository) brandScope(brand string) *gorm.DB {
	q := r.db.Model(&model.Device{})
	if brand != "" {
		q = q.Where("brand = ?", brand)
	}
	return q
}

