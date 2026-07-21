package repository

import (
	"errors"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/premium/model"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type WebhookEventRepository struct {
	db *gorm.DB
}

func NewWebhookEventRepository(db *gorm.DB) *WebhookEventRepository {
	return &WebhookEventRepository{db: db}
}

// WebhookAction is the result of MarkProcessing — tells caller whether to
// run the handler, ACK as duplicate, or signal Stripe to retry.
type WebhookAction string

const (
	// WebhookActionProcess: this worker claimed the event, run the handler.
	WebhookActionProcess WebhookAction = "process"
	// WebhookActionSkip: event already processed successfully, return 200.
	WebhookActionSkip WebhookAction = "skip"
	// WebhookActionRetry: another worker holds an in-flight claim (fresh < 5min);
	// return non-2xx so Stripe retries within the redelivery window. Critical:
	// must NOT return 200 here — if the lock-holder crashes before MarkCompleted,
	// the event would otherwise be permanently lost. Stripe retry + 5-min stale
	// reclaim is the recovery path.
	WebhookActionRetry WebhookAction = "retry"
)

// MarkProcessing atomically claims a webhook event for processing.
//
// Returns one of three actions:
//   - WebhookActionProcess: new claim (or stale-reclaim) — caller runs handler
//   - WebhookActionSkip:    already processed — caller returns 200
//   - WebhookActionRetry:   another worker holds it (fresh) — caller returns 409
//
// If a previous attempt left the event in "processing" or "failed" state
// (crash or error) AND it's older than staleProcessingThreshold, we reclaim
// it so Stripe's retry succeeds.
func (r *WebhookEventRepository) MarkProcessing(eventID, eventType string) (WebhookAction, error) {
	err := r.db.Create(&model.WebhookEvent{
		EventID:   eventID,
		EventType: eventType,
		Status:    "processing",
	}).Error
	if err == nil {
		return WebhookActionProcess, nil // New event
	}
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) || pgErr.Code != "23505" {
		logger.Log.Error().Err(err).Str("event_id", eventID).Msg("Failed to insert webhook event")
		return "", err // Real DB error
	}

	// Duplicate row. Row-lock + check-then-update inside a transaction so
	// PostgreSQL serializes concurrent claims. Three outcomes:
	//   - processed       → skip permanently (already done)
	//   - processing+fresh → another worker owns it; signal Stripe to retry
	//                        rather than ACK with 200 (worker may crash before
	//                        MarkCompleted; ACK-then-lose would permanently
	//                        drop the event)
	//   - failed OR stale  → reclaim
	const staleProcessingThreshold = 5 * time.Minute
	var action WebhookAction
	txErr := r.db.Transaction(func(tx *gorm.DB) error {
		var existing model.WebhookEvent
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("event_id = ?", eventID).First(&existing).Error; err != nil {
			return err
		}
		if existing.Status == "processed" {
			action = WebhookActionSkip
			return nil
		}
		if existing.Status == "processing" &&
			time.Since(existing.CreatedAt) < staleProcessingThreshold {
			// Fresh in-flight by another worker. Do NOT ACK; signal retry so
			// Stripe redelivers within its 3-day window. If the lock-holder
			// completes normally, future retries hit the "processed" branch
			// above and skip cleanly. If it crashes, the 5-min staleness
			// elapses and the next retry reclaims here.
			action = WebhookActionRetry
			return nil
		}
		// Failed OR stale-processing: reclaim. Reset CreatedAt so any further
		// duplicate within the threshold of THIS reclaim is also blocked.
		now := time.Now()
		if err := tx.Model(&existing).Updates(map[string]interface{}{
			"status":     "processing",
			"created_at": now,
		}).Error; err != nil {
			return err
		}
		action = WebhookActionProcess
		return nil
	})
	if txErr != nil {
		return "", txErr
	}
	return action, nil
}

// MarkCompleted updates a webhook event to "processed" status after successful handling.
func (r *WebhookEventRepository) MarkCompleted(eventID string) error {
	now := time.Now()
	return r.db.Model(&model.WebhookEvent{}).
		Where("event_id = ?", eventID).
		Updates(map[string]interface{}{
			"status":       "processed",
			"processed_at": now,
		}).Error
}

// MarkFailed updates a webhook event to "failed" status so Stripe retries will be accepted.
func (r *WebhookEventRepository) MarkFailed(eventID string) error {
	return r.db.Model(&model.WebhookEvent{}).
		Where("event_id = ?", eventID).
		Update("status", "failed").Error
}

// Remove deletes a webhook event record to allow retry on processing failure.
func (r *WebhookEventRepository) Remove(eventID string) error {
	return r.db.Where("event_id = ?", eventID).Delete(&model.WebhookEvent{}).Error
}

// List returns paginated webhook events with optional filters.
func (r *WebhookEventRepository) List(page, perPage int, eventType, status string) ([]model.WebhookEvent, int64, error) {
	query := r.db.Model(&model.WebhookEvent{})
	if eventType != "" {
		query = query.Where("event_type = ?", eventType)
	}
	if status != "" {
		query = query.Where("status = ?", status)
	}

	var total int64
	query.Count(&total)

	var events []model.WebhookEvent
	err := query.Order("created_at DESC").
		Offset((page - 1) * perPage).
		Limit(perPage).
		Find(&events).Error
	return events, total, err
}
