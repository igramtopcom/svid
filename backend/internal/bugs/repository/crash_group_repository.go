package repository

import (
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/bugs/model"
	"gorm.io/gorm"
)

type CrashGroupRepository struct {
	db *gorm.DB
}

func NewCrashGroupRepository(db *gorm.DB) *CrashGroupRepository {
	return &CrashGroupRepository{db: db}
}

func (r *CrashGroupRepository) Create(group *model.CrashGroup) error {
	return r.db.Create(group).Error
}

func (r *CrashGroupRepository) FindByID(id uuid.UUID) (*model.CrashGroup, error) {
	var group model.CrashGroup
	err := r.db.Where("id = ?", id).First(&group).Error
	if err != nil {
		return nil, err
	}
	return &group, nil
}

func (r *CrashGroupRepository) FindByFingerprint(fingerprint string) (*model.CrashGroup, error) {
	var group model.CrashGroup
	err := r.db.Where("fingerprint = ?", fingerprint).First(&group).Error
	if err != nil {
		return nil, err
	}
	return &group, nil
}

func (r *CrashGroupRepository) FindByFingerprints(fingerprints []string) (*model.CrashGroup, error) {
	var group model.CrashGroup
	err := r.db.
		Where("fingerprint IN ?", fingerprints).
		Order("last_seen_at DESC").
		First(&group).Error
	if err != nil {
		return nil, err
	}
	return &group, nil
}

func (r *CrashGroupRepository) FindByIDs(ids []uuid.UUID) ([]model.CrashGroup, error) {
	if len(ids) == 0 {
		return nil, nil
	}

	var groups []model.CrashGroup
	if err := r.db.Where("id IN ?", ids).Find(&groups).Error; err != nil {
		return nil, err
	}
	return groups, nil
}

func (r *CrashGroupRepository) ListRecentActiveByPlatform(os string, limit int) ([]model.CrashGroup, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}

	var groups []model.CrashGroup
	query := r.db.Model(&model.CrashGroup{}).
		Where("status NOT IN ?", []string{"resolved", "wont_fix"}).
		Order("last_seen_at DESC").
		Limit(limit)

	if os != "" {
		query = query.Where("platforms ILIKE ?", "%"+os+"%")
	}

	if err := query.Find(&groups).Error; err != nil {
		return nil, err
	}
	return groups, nil
}

func (r *CrashGroupRepository) ListForMergeReview(limit int, includeResolved bool) ([]model.CrashGroup, error) {
	if limit <= 0 || limit > 500 {
		limit = 200
	}

	var groups []model.CrashGroup
	query := r.db.Model(&model.CrashGroup{}).
		Order("last_seen_at DESC").
		Limit(limit)

	if !includeResolved {
		query = query.Where("status NOT IN ?", []string{"resolved", "wont_fix"})
	}

	if err := query.Find(&groups).Error; err != nil {
		return nil, err
	}
	return groups, nil
}

func (r *CrashGroupRepository) List(page, perPage int, status, severity, search, brand string) ([]model.CrashGroup, int64, error) {
	var groups []model.CrashGroup
	var total int64

	query := r.db.Model(&model.CrashGroup{})

	if brand != "" {
		query = query.Where("id IN (SELECT crash_group_id FROM crash_reports WHERE device_id IN (SELECT id FROM devices WHERE brand = ?))", brand)
	}
	if status != "" {
		query = query.Where("status = ?", status)
	}
	if severity != "" {
		query = query.Where("severity = ?", severity)
	}
	if search != "" {
		query = query.Where("title ILIKE ? OR admin_notes ILIKE ?", "%"+search+"%", "%"+search+"%")
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("last_seen_at DESC").Offset(offset).Limit(perPage).Find(&groups).Error; err != nil {
		return nil, 0, err
	}

	return groups, total, nil
}

func (r *CrashGroupRepository) UpdateFields(id uuid.UUID, fields map[string]interface{}) error {
	fields["updated_at"] = time.Now()
	return r.db.Model(&model.CrashGroup{}).Where("id = ?", id).Updates(fields).Error
}

// IncrementCounts atomically increments crash_count and updates last_seen_at.
// Also increments device_count if this device hasn't been seen in this group before.
func (r *CrashGroupRepository) IncrementCounts(groupID, deviceID uuid.UUID, appVersion, os string) error {
	now := time.Now()

	// Check if this device already has a crash in this group
	var existingCount int64
	r.db.Model(&model.CrashReport{}).
		Where("crash_group_id = ? AND device_id = ?", groupID, deviceID).
		Count(&existingCount)

	deviceIncrement := 0
	if existingCount <= 1 { // <=1 because the new crash may already be inserted
		deviceIncrement = 1
	}

	return r.db.Exec(`
		UPDATE crash_groups
		SET crash_count = crash_count + 1,
		    device_count = device_count + ?,
		    last_seen_at = ?,
		    versions = CASE
		        WHEN versions IS NULL OR versions = '' THEN ?
		        WHEN versions NOT LIKE ? THEN versions || ',' || ?
		        ELSE versions
		    END,
		    platforms = CASE
		        WHEN platforms IS NULL OR platforms = '' THEN ?
		        WHEN platforms NOT LIKE ? THEN platforms || ',' || ?
		        ELSE platforms
		    END,
		    updated_at = ?
		WHERE id = ?
	`, deviceIncrement, now,
		appVersion, "%"+appVersion+"%", appVersion,
		os, "%"+os+"%", os,
		now, groupID,
	).Error
}

func (r *CrashGroupRepository) CountAll(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.CrashGroup{})
	if brand != "" {
		query = query.Where("id IN (SELECT crash_group_id FROM crash_reports WHERE device_id IN (SELECT id FROM devices WHERE brand = ?))", brand)
	}
	err := query.Count(&count).Error
	return count, err
}

func (r *CrashGroupRepository) CountByStatus(brand string) (map[string]int64, error) {
	type result struct {
		Status string
		Count  int64
	}
	var results []result
	query := r.db.Model(&model.CrashGroup{})
	if brand != "" {
		query = query.Where("id IN (SELECT crash_group_id FROM crash_reports WHERE device_id IN (SELECT id FROM devices WHERE brand = ?))", brand)
	}
	err := query.
		Select("status, count(*) as count").
		Group("status").Scan(&results).Error
	if err != nil {
		return nil, err
	}
	m := make(map[string]int64)
	for _, r := range results {
		m[r.Status] = r.Count
	}
	return m, nil
}

func (r *CrashGroupRepository) CountActive(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.CrashGroup{})
	if brand != "" {
		query = query.Where("id IN (SELECT crash_group_id FROM crash_reports WHERE device_id IN (SELECT id FROM devices WHERE brand = ?))", brand)
	}
	err := query.
		Where("status IN ?", []string{"new", "investigating", "fixing"}).
		Count(&count).Error
	return count, err
}

func (r *CrashGroupRepository) CountBySeverity(brand string) (map[string]int64, error) {
	type result struct {
		Severity string
		Count    int64
	}
	var results []result
	query := r.db.Model(&model.CrashGroup{})
	if brand != "" {
		query = query.Where("id IN (SELECT crash_group_id FROM crash_reports WHERE device_id IN (SELECT id FROM devices WHERE brand = ?))", brand)
	}
	err := query.
		Select("severity, count(*) as count").
		Group("severity").Scan(&results).Error
	if err != nil {
		return nil, err
	}
	m := make(map[string]int64)
	for _, r := range results {
		m[r.Severity] = r.Count
	}
	return m, nil
}

func (r *CrashGroupRepository) TopGroups(limit, days int) ([]model.CrashGroup, error) {
	var groups []model.CrashGroup
	since := time.Now().AddDate(0, 0, -days)
	err := r.db.Where("last_seen_at >= ?", since).
		Order("crash_count DESC").
		Limit(limit).
		Find(&groups).Error
	return groups, err
}

func (r *CrashGroupRepository) AggregateForGroupIDs(groupIDs []uuid.UUID) (int64, int64, error) {
	if len(groupIDs) == 0 {
		return 0, 0, nil
	}

	var stats struct {
		CrashCount  int64 `gorm:"column:crash_count"`
		DeviceCount int64 `gorm:"column:device_count"`
	}
	err := r.db.Model(&model.CrashReport{}).
		Where("crash_group_id IN ?", groupIDs).
		Select("COUNT(*) AS crash_count, COUNT(DISTINCT device_id) AS device_count").
		Scan(&stats).Error
	if err != nil {
		return 0, 0, err
	}
	return stats.CrashCount, stats.DeviceCount, nil
}

// Merge reassigns all crashes from sourceIDs to targetID, reconciles the target
// group metadata, then deletes the source groups.
func (r *CrashGroupRepository) Merge(targetID uuid.UUID, sourceIDs []uuid.UUID, fields map[string]interface{}) error {
	sourceIDs = sanitizeMergeSourceIDs(targetID, sourceIDs)
	if len(sourceIDs) == 0 {
		return nil
	}

	return r.db.Transaction(func(tx *gorm.DB) error {
		// Reassign crashes
		if err := tx.Model(&model.CrashReport{}).
			Where("crash_group_id IN ?", sourceIDs).
			Update("crash_group_id", targetID).Error; err != nil {
			return err
		}

		var stats struct {
			CrashCount  int64      `gorm:"column:crash_count"`
			DeviceCount int64      `gorm:"column:device_count"`
			FirstSeenAt *time.Time `gorm:"column:first_seen_at"`
			LastSeenAt  *time.Time `gorm:"column:last_seen_at"`
		}
		if err := tx.Model(&model.CrashReport{}).
			Where("crash_group_id = ?", targetID).
			Select("COUNT(*) AS crash_count, COUNT(DISTINCT device_id) AS device_count, MIN(created_at) AS first_seen_at, MAX(created_at) AS last_seen_at").
			Scan(&stats).Error; err != nil {
			return err
		}

		var versions []string
		if err := tx.Model(&model.CrashReport{}).
			Where("crash_group_id = ? AND app_version IS NOT NULL AND app_version <> ''", targetID).
			Distinct().
			Pluck("app_version", &versions).Error; err != nil {
			return err
		}

		var platforms []string
		if err := tx.Model(&model.CrashReport{}).
			Where("crash_group_id = ? AND os IS NOT NULL AND os <> ''", targetID).
			Distinct().
			Pluck("os", &platforms).Error; err != nil {
			return err
		}

		sort.Strings(versions)
		sort.Strings(platforms)

		if fields == nil {
			fields = make(map[string]interface{})
		}
		fields["crash_count"] = stats.CrashCount
		fields["device_count"] = stats.DeviceCount
		fields["versions"] = strings.Join(versions, ",")
		fields["platforms"] = strings.Join(platforms, ",")
		fields["updated_at"] = time.Now()
		if stats.FirstSeenAt != nil {
			fields["first_seen_at"] = *stats.FirstSeenAt
		}
		if stats.LastSeenAt != nil {
			fields["last_seen_at"] = *stats.LastSeenAt
		}

		if err := tx.Model(&model.CrashGroup{}).Where("id = ?", targetID).Updates(fields).Error; err != nil {
			return err
		}

		// Delete source groups
		return tx.Where("id IN ?", sourceIDs).Delete(&model.CrashGroup{}).Error
	})
}

func sanitizeMergeSourceIDs(targetID uuid.UUID, sourceIDs []uuid.UUID) []uuid.UUID {
	seen := make(map[uuid.UUID]struct{}, len(sourceIDs))
	result := make([]uuid.UUID, 0, len(sourceIDs))
	for _, sourceID := range sourceIDs {
		if sourceID == uuid.Nil || sourceID == targetID {
			continue
		}
		if _, ok := seen[sourceID]; ok {
			continue
		}
		seen[sourceID] = struct{}{}
		result = append(result, sourceID)
	}
	return result
}
