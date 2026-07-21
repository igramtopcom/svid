package service

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/alerts/dto"
	"github.com/snakeloader/backend/internal/alerts/model"
	"github.com/snakeloader/backend/internal/alerts/repository"
	"github.com/snakeloader/backend/internal/pkg/email"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"gorm.io/gorm"
)

var (
	ErrAlertConfigNotFound = errors.New("alert config not found")
)

type AlertService struct {
	repo          *repository.AlertRepository
	emailService  *email.Service
	telegramToken string
}

func NewAlertService(repo *repository.AlertRepository, emailService *email.Service, telegramToken string) *AlertService {
	return &AlertService{
		repo:          repo,
		emailService:  emailService,
		telegramToken: telegramToken,
	}
}

// CreateConfig creates a new alert configuration.
func (s *AlertService) CreateConfig(req dto.CreateAlertConfigRequest) (*dto.AlertConfigResponse, error) {
	config := &model.AlertConfig{
		Name:         req.Name,
		MetricType:   req.MetricType,
		Threshold:    req.Threshold,
		WindowMins:   req.WindowMins,
		Channel:      req.Channel,
		Destination:  req.Destination,
		IsEnabled:    true,
		CooldownMins: 60,
	}
	if req.IsEnabled != nil {
		config.IsEnabled = *req.IsEnabled
	}
	if req.CooldownMins > 0 {
		config.CooldownMins = req.CooldownMins
	}

	if err := s.repo.CreateConfig(config); err != nil {
		return nil, err
	}

	resp := dto.AlertConfigToResponse(config)
	return &resp, nil
}

// GetConfig returns a single alert configuration.
func (s *AlertService) GetConfig(id uuid.UUID) (*dto.AlertConfigResponse, error) {
	config, err := s.repo.FindConfigByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrAlertConfigNotFound
		}
		return nil, err
	}
	resp := dto.AlertConfigToResponse(config)
	return &resp, nil
}

// UpdateConfig updates an existing alert configuration.
func (s *AlertService) UpdateConfig(id uuid.UUID, req dto.UpdateAlertConfigRequest) (*dto.AlertConfigResponse, error) {
	config, err := s.repo.FindConfigByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrAlertConfigNotFound
		}
		return nil, err
	}

	if req.Name != nil {
		config.Name = *req.Name
	}
	if req.Threshold != nil {
		config.Threshold = *req.Threshold
	}
	if req.WindowMins != nil {
		config.WindowMins = *req.WindowMins
	}
	if req.Channel != nil {
		config.Channel = *req.Channel
	}
	if req.Destination != nil {
		config.Destination = *req.Destination
	}
	if req.IsEnabled != nil {
		config.IsEnabled = *req.IsEnabled
	}
	if req.CooldownMins != nil {
		config.CooldownMins = *req.CooldownMins
	}

	if err := s.repo.UpdateConfig(config); err != nil {
		return nil, err
	}

	resp := dto.AlertConfigToResponse(config)
	return &resp, nil
}

// DeleteConfig removes an alert configuration.
func (s *AlertService) DeleteConfig(id uuid.UUID) error {
	_, err := s.repo.FindConfigByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrAlertConfigNotFound
		}
		return err
	}
	return s.repo.DeleteConfig(id)
}

// ListConfigs returns all alert configurations.
func (s *AlertService) ListConfigs() ([]dto.AlertConfigResponse, error) {
	configs, err := s.repo.ListConfigs()
	if err != nil {
		return nil, err
	}
	return dto.AlertConfigsToResponse(configs), nil
}

// ListLogs returns paginated alert logs.
func (s *AlertService) ListLogs(page, perPage int, configID *uuid.UUID) ([]dto.AlertLogResponse, int64, error) {
	page, perPage = pagination.Normalize(page, perPage, 20)

	logs, total, err := s.repo.ListLogs(page, perPage, configID)
	if err != nil {
		return nil, 0, err
	}
	return dto.AlertLogsToResponse(logs), total, nil
}

// CheckAlerts evaluates all enabled alert configs against current metrics.
// Called periodically by the job scheduler.
func (s *AlertService) CheckAlerts() {
	configs, err := s.repo.ListEnabledConfigs()
	if err != nil {
		logger.Log.Error().Err(err).Msg("Failed to load alert configs")
		return
	}

	for _, config := range configs {
		// Check cooldown
		if config.LastFiredAt != nil {
			cooldownUntil := config.LastFiredAt.Add(time.Duration(config.CooldownMins) * time.Minute)
			if time.Now().Before(cooldownUntil) {
				continue
			}
		}

		var metricValue int
		switch config.MetricType {
		case "crash_rate":
			metricValue, err = s.repo.CountCrashesInWindow(config.WindowMins)
		case "error_rate":
			metricValue, err = s.repo.CountErrorEventsInWindow(config.WindowMins)
		case "download_error_rate":
			metricValue, err = s.repo.CountDownloadErrorsInWindow(config.WindowMins)
		case "new_bug_rate":
			metricValue, err = s.repo.CountNewBugsInWindow(config.WindowMins)
		case "crash_group_spike":
			metricValue, err = s.repo.CountCrashGroupSpikeInWindow(config.WindowMins)
		case "download_error_rate_pct":
			metricValue, err = s.repo.DownloadErrorRatePercent(config.WindowMins)
		default:
			continue
		}

		if err != nil {
			logger.Log.Error().Err(err).Str("alert", config.Name).Msg("Failed to query metric")
			continue
		}

		if metricValue < config.Threshold {
			continue
		}

		// Threshold breached — send alert
		message := fmt.Sprintf(
			"[Svid Alert] %s\n%s: %d (threshold: %d) in last %d min",
			config.Name, config.MetricType, metricValue, config.Threshold, config.WindowMins,
		)

		var sendErr error
		switch config.Channel {
		case "telegram":
			sendErr = s.sendTelegram(config.Destination, message)
		case "email":
			sendErr = s.sendEmail(config.Destination, config.Name, message)
		}

		// Log the alert
		alertLog := &model.AlertLog{
			AlertConfigID: config.ID,
			MetricValue:   metricValue,
			Message:       message,
			Channel:       config.Channel,
			Status:        "sent",
		}
		if sendErr != nil {
			alertLog.Status = "failed"
			alertLog.ErrorMessage = sendErr.Error()
			logger.Log.Error().Err(sendErr).Str("alert", config.Name).Msg("Failed to send alert")
		} else {
			logger.Log.Info().Str("alert", config.Name).Int("value", metricValue).Msg("Alert sent")
		}
		s.repo.CreateLog(alertLog)

		// Update last fired time
		now := time.Now()
		config.LastFiredAt = &now
		s.repo.UpdateConfig(&config)
	}
}

// sendTelegram sends a message via Telegram Bot API.
func (s *AlertService) sendTelegram(chatID, text string) error {
	if s.telegramToken == "" {
		return fmt.Errorf("telegram bot token not configured")
	}

	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", s.telegramToken)
	payload := map[string]string{
		"chat_id": chatID,
		"text":    text,
	}
	body, _ := json.Marshal(payload)

	resp, err := http.Post(url, "application/json", bytes.NewBuffer(body))
	if err != nil {
		return fmt.Errorf("telegram request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("telegram returned status %d", resp.StatusCode)
	}
	return nil
}

// sendEmail sends an alert email.
func (s *AlertService) sendEmail(to, subject, body string) error {
	if s.emailService == nil || !s.emailService.IsConfigured() {
		return fmt.Errorf("email service not configured")
	}
	return s.emailService.Send(to, "[Svid Alert] "+subject, "alert", map[string]string{
		"AlertName": subject,
		"Body":      body,
	})
}

// TestAlert sends a test notification to verify channel configuration.
func (s *AlertService) TestAlert(id uuid.UUID) error {
	config, err := s.repo.FindConfigByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrAlertConfigNotFound
		}
		return err
	}

	message := fmt.Sprintf("[Svid Test Alert] %s — this is a test notification.", config.Name)

	switch config.Channel {
	case "telegram":
		return s.sendTelegram(config.Destination, message)
	case "email":
		return s.sendEmail(config.Destination, "Test Alert: "+config.Name, message)
	default:
		return fmt.Errorf("unsupported channel: %s", config.Channel)
	}
}
