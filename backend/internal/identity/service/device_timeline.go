package service

import (
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/identity/dto"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"gorm.io/gorm"
)

// DeviceTimelineService provides a unified chronological view of all events for a device.
// Uses direct DB queries across module tables (read-only, admin-only).
type DeviceTimelineService struct {
	db *gorm.DB
}

func NewDeviceTimelineService(db *gorm.DB) *DeviceTimelineService {
	return &DeviceTimelineService{db: db}
}

// GetDeviceTimeline returns a paginated, chronologically-sorted list of events for a device.
// eventTypes filters by event type (comma-separated); empty = all types.
func (s *DeviceTimelineService) GetDeviceTimeline(deviceID uuid.UUID, page, perPage int, eventTypes string) (*dto.DeviceTimelineResponse, error) {
	page, perPage = pagination.Normalize(page, perPage, 50)

	// Parse requested event types
	typeFilter := parseEventTypes(eventTypes)

	// Build UNION ALL query across all relevant tables
	var unionParts []string
	var args []interface{}

	if shouldInclude(typeFilter, "crash") {
		unionParts = append(unionParts, `
			SELECT 'crash' AS type, cr.created_at AS timestamp,
				COALESCE(cr.error_message, 'Crash report') AS title,
				COALESCE(cr.severity, 'medium') AS severity,
				cr.id::text AS related_id,
				cr.app_version AS metadata
			FROM crash_reports cr
			WHERE cr.device_id = ?`)
		args = append(args, deviceID)
	}

	if shouldInclude(typeFilter, "bug_report") {
		unionParts = append(unionParts, `
			SELECT 'bug_report' AS type, br.created_at AS timestamp,
				br.title AS title,
				COALESCE(br.priority, 'medium') AS severity,
				br.id::text AS related_id,
				br.status AS metadata
			FROM bug_reports br
			WHERE br.device_id = ?`)
		args = append(args, deviceID)
	}

	if shouldInclude(typeFilter, "download_error") {
		unionParts = append(unionParts, `
			SELECT 'download_error' AS type, de.created_at AS timestamp,
				CONCAT(de.error_code, ' (', de.platform, ')') AS title,
				'medium' AS severity,
				de.id::text AS related_id,
				de.error_phase AS metadata
			FROM download_errors de
			WHERE de.device_id = ?`)
		args = append(args, deviceID)
	}

	if shouldInclude(typeFilter, "ticket") {
		unionParts = append(unionParts, `
			SELECT 'ticket' AS type, t.created_at AS timestamp,
				t.subject AS title,
				CASE WHEN t.priority = 'urgent' THEN 'high' ELSE COALESCE(t.priority, 'low') END AS severity,
				t.id::text AS related_id,
				t.status AS metadata
			FROM tickets t
			WHERE t.device_id = ?`)
		args = append(args, deviceID)
	}

	if shouldInclude(typeFilter, "license") {
		unionParts = append(unionParts, `
			SELECT 'license' AS type, pl.created_at AS timestamp,
				CONCAT('License ', pl.tier, ' (', pl.billing_cycle, ')') AS title,
				'info' AS severity,
				pl.id::text AS related_id,
				pl.payment_method AS metadata
			FROM premium_licenses pl
			WHERE pl.device_id = ?`)
		args = append(args, deviceID)
	}

	if shouldInclude(typeFilter, "device_registered") {
		unionParts = append(unionParts, `
			SELECT 'device_registered' AS type, d.created_at AS timestamp,
				CONCAT('Device registered: ', d.device_name) AS title,
				'info' AS severity,
				d.id::text AS related_id,
				CONCAT(d.os, ' ', d.os_version) AS metadata
			FROM devices d
			WHERE d.id = ?`)
		args = append(args, deviceID)
	}

	if len(unionParts) == 0 {
		return &dto.DeviceTimelineResponse{Events: []dto.TimelineEvent{}, TotalCount: 0}, nil
	}

	unionQuery := strings.Join(unionParts, " UNION ALL ")

	// Count total
	var totalCount int64
	countSQL := fmt.Sprintf("SELECT COUNT(*) FROM (%s) AS timeline", unionQuery)
	if err := s.db.Raw(countSQL, args...).Scan(&totalCount).Error; err != nil {
		return nil, fmt.Errorf("failed to count timeline events: %w", err)
	}

	// Fetch page (sorted newest first)
	offset := (page - 1) * perPage
	pageSQL := fmt.Sprintf("SELECT * FROM (%s) AS timeline ORDER BY timestamp DESC LIMIT ? OFFSET ?", unionQuery)
	pageArgs := append(args, perPage, offset)

	var rows []struct {
		Type      string    `gorm:"column:type"`
		Timestamp time.Time `gorm:"column:timestamp"`
		Title     string    `gorm:"column:title"`
		Severity  string    `gorm:"column:severity"`
		RelatedID string    `gorm:"column:related_id"`
		Metadata  string    `gorm:"column:metadata"`
	}
	if err := s.db.Raw(pageSQL, pageArgs...).Scan(&rows).Error; err != nil {
		return nil, fmt.Errorf("failed to query timeline: %w", err)
	}

	events := make([]dto.TimelineEvent, len(rows))
	for i, r := range rows {
		events[i] = dto.TimelineEvent{
			Type:        r.Type,
			Timestamp:   r.Timestamp.Format(time.RFC3339),
			Title:       r.Title,
			Description: descriptionForType(r.Type),
			Severity:    r.Severity,
			RelatedID:   r.RelatedID,
			Metadata:    r.Metadata,
		}
	}

	return &dto.DeviceTimelineResponse{
		Events:     events,
		TotalCount: totalCount,
	}, nil
}

func parseEventTypes(types string) map[string]bool {
	if types == "" {
		return nil // nil = all types
	}
	m := make(map[string]bool)
	for _, t := range strings.Split(types, ",") {
		t = strings.TrimSpace(t)
		if t != "" {
			m[t] = true
		}
	}
	return m
}

func shouldInclude(filter map[string]bool, eventType string) bool {
	if filter == nil {
		return true // no filter = include all
	}
	return filter[eventType]
}

func descriptionForType(eventType string) string {
	switch eventType {
	case "crash":
		return "Application crash reported"
	case "bug_report":
		return "Bug report submitted"
	case "download_error":
		return "Download error occurred"
	case "ticket":
		return "Support ticket created"
	case "license":
		return "License event"
	case "device_registered":
		return "Device first registered"
	default:
		return ""
	}
}
