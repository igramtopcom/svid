package service

import (
	"errors"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/feedback/dto"
	"github.com/snakeloader/backend/internal/feedback/model"
	"github.com/snakeloader/backend/internal/feedback/repository"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"github.com/snakeloader/backend/internal/pkg/sse"
	"gorm.io/gorm"
)

var (
	ErrTicketNotFound         = errors.New("ticket not found")
	ErrFeatureRequestNotFound = errors.New("feature request not found")
	ErrAlreadyVoted           = errors.New("already voted for this feature request")
	ErrTicketAccessDenied     = errors.New("access denied to this ticket")
)

const maxTicketDiagnosticLogChars = 30000

// TicketNotifier is an optional hook for sending ticket event notifications.
type TicketNotifier interface {
	NotifyNewTicket(ticketID, subject, category, message string)
	NotifyNewRating(deviceID string, rating int, review, appVersion string)
	NotifyAIAutoResponse(ticketID, subject, confidence string)
	NotifyTicketEscalated(ticketID, subject, reason string)
}

// TicketAutoResponder is an optional AI auto-response hook.
type TicketAutoResponder interface {
	AutoRespondToTicket(ticketID uuid.UUID, subject, message, category string) *TicketAutoResponseResult
}

// TicketAutoResponseResult holds AI auto-response output.
type TicketAutoResponseResult struct {
	Response       string
	Confidence     string // "high", "medium", "low"
	ShouldEscalate bool
}

type FeedbackService struct {
	ticketRepo    *repository.TicketRepository
	featureRepo   *repository.FeatureRequestRepository
	ratingRepo    *repository.RatingRepository
	hub           *sse.Hub            // nil = no real-time events
	notifier      TicketNotifier      // nil = no notifications
	autoResponder TicketAutoResponder // nil = no AI auto-response
}

func NewFeedbackService(
	ticketRepo *repository.TicketRepository,
	featureRepo *repository.FeatureRequestRepository,
	ratingRepo *repository.RatingRepository,
	hub *sse.Hub,
) *FeedbackService {
	return &FeedbackService{
		ticketRepo:  ticketRepo,
		featureRepo: featureRepo,
		ratingRepo:  ratingRepo,
		hub:         hub,
	}
}

// SetNotifier wires the event notifier (called after construction to avoid circular deps).
func (s *FeedbackService) SetNotifier(n TicketNotifier) { s.notifier = n }

// SetAutoResponder wires the AI auto-response agent.
func (s *FeedbackService) SetAutoResponder(r TicketAutoResponder) { s.autoResponder = r }

// ==================== Tickets ====================

func (s *FeedbackService) CreateTicket(deviceID uuid.UUID, req dto.CreateTicketRequest) (*dto.TicketResponse, error) {
	ticket := &model.Ticket{
		DeviceID: deviceID,
		Subject:  req.Subject,
		Category: req.Category,
	}

	if err := s.ticketRepo.Create(ticket); err != nil {
		return nil, err
	}

	// Create the initial message
	msg := &model.TicketMessage{
		TicketID:   ticket.ID,
		SenderType: "device",
		SenderID:   deviceID,
		Content:    req.Message,
	}
	if err := s.ticketRepo.CreateMessage(msg); err != nil {
		return nil, err
	}

	if diagnosticLog := formatTicketDiagnosticLog(req.DiagnosticLog); diagnosticLog != "" {
		diagnosticMsg := &model.TicketMessage{
			TicketID:   ticket.ID,
			SenderType: "system",
			SenderID:   deviceID,
			Content:    diagnosticLog,
		}
		if err := s.ticketRepo.CreateMessage(diagnosticMsg); err != nil {
			logger.Log.Warn().Err(err).Str("ticket_id", ticket.ID.String()).Msg("Failed to attach ticket diagnostic log")
		}
	}

	// Reload with messages
	ticket, err := s.ticketRepo.FindByID(ticket.ID)
	if err != nil {
		return nil, err
	}

	resp := dto.TicketToResponse(ticket)

	// Notify admin about new ticket (SSE)
	s.publish("admin:notifications", sse.Event{
		Type: "new_ticket",
		Data: resp,
	})

	// S1.1: Telegram notification
	if s.notifier != nil {
		s.notifier.NotifyNewTicket(ticket.ID.String(), ticket.Subject, ticket.Category, req.Message)
	}

	// S2.1 + S2.3: AI auto-response with smart escalation
	if s.autoResponder != nil {
		go s.handleAutoResponse(ticket.ID, deviceID, ticket.Subject, req.Message, ticket.Category)
	}

	return &resp, nil
}

func formatTicketDiagnosticLog(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return ""
	}
	runes := []rune(trimmed)
	if len(runes) > maxTicketDiagnosticLogChars {
		trimmed = string(runes[len(runes)-maxTicketDiagnosticLogChars:])
	}
	return "Diagnostic log tail:\n\n" + trimmed
}

func (s *FeedbackService) GetTicket(id uuid.UUID) (*dto.TicketResponse, error) {
	ticket, err := s.ticketRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrTicketNotFound
		}
		return nil, err
	}
	resp := dto.TicketToResponse(ticket)
	return &resp, nil
}

func (s *FeedbackService) GetDeviceTicket(id, deviceID uuid.UUID) (*dto.TicketResponse, error) {
	ticket, err := s.ticketRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrTicketNotFound
		}
		return nil, err
	}
	if ticket.DeviceID != deviceID {
		return nil, ErrTicketAccessDenied
	}
	resp := dto.TicketToResponse(ticket)
	return &resp, nil
}

func (s *FeedbackService) ListDeviceTickets(deviceID uuid.UUID) ([]dto.TicketListResponse, error) {
	tickets, err := s.ticketRepo.ListByDevice(deviceID)
	if err != nil {
		return nil, err
	}
	return dto.TicketsToListResponse(tickets), nil
}

func (s *FeedbackService) ListTickets(page, perPage int, status, category, priority, brand, search, deviceID string) ([]dto.TicketListResponse, int64, error) {
	page, perPage = pagination.Normalize(page, perPage, 20)

	tickets, total, err := s.ticketRepo.List(page, perPage, status, category, priority, brand, search, deviceID)
	if err != nil {
		return nil, 0, err
	}
	return dto.TicketsToListResponse(tickets), total, nil
}

func (s *FeedbackService) UpdateTicket(id uuid.UUID, req dto.UpdateTicketRequest) (*dto.TicketResponse, error) {
	ticket, err := s.ticketRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrTicketNotFound
		}
		return nil, err
	}

	if req.Status != nil {
		ticket.Status = *req.Status
	}
	if req.Priority != nil {
		ticket.Priority = *req.Priority
	}

	if err := s.ticketRepo.Update(ticket); err != nil {
		return nil, err
	}

	resp := dto.TicketToResponse(ticket)
	return &resp, nil
}

func (s *FeedbackService) SendDeviceMessage(ticketID, deviceID uuid.UUID, req dto.SendMessageRequest) (*dto.MessageResponse, error) {
	ticket, err := s.ticketRepo.FindByID(ticketID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrTicketNotFound
		}
		return nil, err
	}
	if ticket.DeviceID != deviceID {
		return nil, ErrTicketAccessDenied
	}

	msg := &model.TicketMessage{
		TicketID:   ticketID,
		SenderType: "device",
		SenderID:   deviceID,
		Content:    req.Content,
	}
	if err := s.ticketRepo.CreateMessage(msg); err != nil {
		return nil, err
	}

	resp := dto.MessageToResponse(msg)

	// Notify ticket subscribers and admin
	topic := fmt.Sprintf("ticket:%s", ticketID.String())
	s.publish(topic, sse.Event{Type: "new_message", Data: resp})
	s.publish("admin:notifications", sse.Event{Type: "ticket_message", Data: map[string]interface{}{
		"ticket_id": ticketID.String(),
		"message":   resp,
	}})

	return &resp, nil
}

func (s *FeedbackService) SendAdminMessage(ticketID, adminID uuid.UUID, req dto.SendMessageRequest) (*dto.MessageResponse, error) {
	_, err := s.ticketRepo.FindByID(ticketID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrTicketNotFound
		}
		return nil, err
	}

	msg := &model.TicketMessage{
		TicketID:   ticketID,
		SenderType: "admin",
		SenderID:   adminID,
		Content:    req.Content,
	}
	if err := s.ticketRepo.CreateMessage(msg); err != nil {
		return nil, err
	}

	resp := dto.MessageToResponse(msg)

	// Notify ticket subscribers (device will receive admin reply)
	topic := fmt.Sprintf("ticket:%s", ticketID.String())
	s.publish(topic, sse.Event{Type: "new_message", Data: resp})

	return &resp, nil
}

// handleAutoResponse runs AI auto-response for a new ticket (S2.1 + S2.3 escalation matrix).
// HIGH confidence: AI responds, ticket stays open (resolved by AI).
// MEDIUM confidence: AI responds + notifies admin for review.
// LOW confidence: AI skips auto-response, escalates to admin immediately.
func (s *FeedbackService) handleAutoResponse(ticketID, deviceID uuid.UUID, subject, message, category string) {
	result := s.autoResponder.AutoRespondToTicket(ticketID, subject, message, category)
	if result == nil {
		return
	}

	// S2.3: Smart Escalation Matrix
	switch result.Confidence {
	case "high":
		// AI resolves: post response as ai_agent
		aiMsg := &model.TicketMessage{
			TicketID:   ticketID,
			SenderType: "ai_agent",
			SenderID:   uuid.Nil, // AI has no device/admin ID
			Content:    result.Response,
		}
		if err := s.ticketRepo.CreateMessage(aiMsg); err != nil {
			logger.Log.Warn().Err(err).Str("ticket_id", ticketID.String()).Msg("Failed to save AI auto-response")
			return
		}
		logger.Log.Info().Str("ticket_id", ticketID.String()).Str("confidence", "high").Msg("AI auto-responded to ticket")
		if s.notifier != nil {
			s.notifier.NotifyAIAutoResponse(ticketID.String(), subject, "high")
		}

	case "medium":
		// AI responds + flags for admin review
		aiMsg := &model.TicketMessage{
			TicketID:   ticketID,
			SenderType: "ai_agent",
			SenderID:   uuid.Nil,
			Content:    result.Response + "\n\n---\n_This is an automated AI response. A human agent will review your ticket shortly._",
		}
		if err := s.ticketRepo.CreateMessage(aiMsg); err != nil {
			logger.Log.Warn().Err(err).Str("ticket_id", ticketID.String()).Msg("Failed to save AI auto-response")
			return
		}
		logger.Log.Info().Str("ticket_id", ticketID.String()).Str("confidence", "medium").Msg("AI auto-responded (medium confidence), flagged for review")
		if s.notifier != nil {
			s.notifier.NotifyAIAutoResponse(ticketID.String(), subject, "medium")
		}

	case "low":
		// Escalate immediately — don't auto-respond, just notify admin
		logger.Log.Info().Str("ticket_id", ticketID.String()).Str("confidence", "low").Msg("AI confidence too low, escalating to admin")
		if s.notifier != nil {
			s.notifier.NotifyTicketEscalated(ticketID.String(), subject, "AI confidence too low for auto-response")
		}
	}

	// Publish SSE event for real-time dashboard update
	s.publish("admin:notifications", sse.Event{
		Type: "ai_auto_response",
		Data: map[string]interface{}{
			"ticket_id":  ticketID.String(),
			"confidence": result.Confidence,
		},
	})
}

// ==================== Feature Requests ====================

func (s *FeedbackService) CreateFeatureRequest(deviceID uuid.UUID, req dto.CreateFeatureRequestRequest) (*dto.FeatureRequestResponse, error) {
	fr := &model.FeatureRequest{
		DeviceID:    deviceID,
		Title:       req.Title,
		Description: req.Description,
	}

	if err := s.featureRepo.Create(fr); err != nil {
		return nil, err
	}

	resp := dto.FeatureRequestToResponse(fr)
	return &resp, nil
}

func (s *FeedbackService) GetFeatureRequest(id uuid.UUID) (*dto.FeatureRequestResponse, error) {
	fr, err := s.featureRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrFeatureRequestNotFound
		}
		return nil, err
	}
	resp := dto.FeatureRequestToResponse(fr)
	return &resp, nil
}

func (s *FeedbackService) ListFeatureRequests(page, perPage int, status, sortBy, brand, search string) ([]dto.FeatureRequestResponse, int64, error) {
	page, perPage = pagination.Normalize(page, perPage, 20)

	requests, total, err := s.featureRepo.List(page, perPage, status, sortBy, brand, search)
	if err != nil {
		return nil, 0, err
	}
	return dto.FeatureRequestsToResponse(requests), total, nil
}

func (s *FeedbackService) UpdateFeatureRequest(id uuid.UUID, req dto.UpdateFeatureRequestRequest) (*dto.FeatureRequestResponse, error) {
	fr, err := s.featureRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrFeatureRequestNotFound
		}
		return nil, err
	}

	if req.Status != nil {
		fr.Status = *req.Status
	}
	if req.AdminNotes != nil {
		fr.AdminNotes = *req.AdminNotes
	}

	if err := s.featureRepo.Update(fr); err != nil {
		return nil, err
	}

	resp := dto.FeatureRequestToResponse(fr)
	return &resp, nil
}

func (s *FeedbackService) VoteFeatureRequest(featureID, deviceID uuid.UUID) (*dto.VoteResponse, error) {
	fr, err := s.featureRepo.FindByID(featureID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrFeatureRequestNotFound
		}
		return nil, err
	}

	// Check if already voted
	_, err = s.featureRepo.FindVote(featureID, deviceID)
	if err == nil {
		return nil, ErrAlreadyVoted
	}

	vote := &model.FeatureVote{
		FeatureRequestID: featureID,
		DeviceID:         deviceID,
	}
	if err := s.featureRepo.CreateVote(vote); err != nil {
		// Handle unique constraint violation (TOCTOU race: concurrent vote)
		if strings.Contains(err.Error(), "duplicate key") || strings.Contains(err.Error(), "unique constraint") {
			return nil, ErrAlreadyVoted
		}
		return nil, err
	}

	if err := s.featureRepo.IncrementUpvotes(featureID); err != nil {
		return nil, err
	}

	return &dto.VoteResponse{
		FeatureRequestID: featureID.String(),
		Upvotes:          fr.Upvotes + 1,
		Voted:            true,
	}, nil
}

// ==================== Ratings ====================

func (s *FeedbackService) SubmitRating(deviceID uuid.UUID, req dto.SubmitRatingRequest) (*dto.RatingResponse, error) {
	rating := &model.AppRating{
		DeviceID:   deviceID,
		Rating:     req.Rating,
		Review:     req.Review,
		AppVersion: req.AppVersion,
	}

	if err := s.ratingRepo.Upsert(rating); err != nil {
		return nil, err
	}

	// Reload to get the actual saved record
	saved, err := s.ratingRepo.FindByDeviceID(deviceID)
	if err != nil {
		return nil, err
	}

	resp := dto.RatingToResponse(saved)

	// S1.1: Telegram notification for new rating
	if s.notifier != nil {
		s.notifier.NotifyNewRating(deviceID.String(), req.Rating, req.Review, req.AppVersion)
	}

	return &resp, nil
}

func (s *FeedbackService) ListRatings(page, perPage int, rating int, sort, brand string) ([]dto.RatingResponse, int64, error) {
	page, perPage = pagination.Normalize(page, perPage, 20)

	ratings, total, err := s.ratingRepo.List(page, perPage, rating, sort, brand)
	if err != nil {
		return nil, 0, err
	}
	return dto.RatingsToResponse(ratings), total, nil
}

func (s *FeedbackService) GetRatingStats(brand string) (*dto.RatingStatsResponse, error) {
	total, _ := s.ratingRepo.CountAll(brand)
	avg, _ := s.ratingRepo.AverageRating(brand)
	dist, _ := s.ratingRepo.Distribution(brand)

	return &dto.RatingStatsResponse{
		TotalRatings: total,
		Average:      avg,
		Distribution: dist,
	}, nil
}

// ==================== Escalation Bridge ====================

// CreateTicketFromEscalation creates a support ticket from an AI session escalation.
// Satisfies the FeedbackServiceInterface in the assistant module.
func (s *FeedbackService) CreateTicketFromEscalation(deviceID uuid.UUID, subject string, aiSessionID uuid.UUID, conversationContext string) (*uuid.UUID, error) {
	ticket := &model.Ticket{
		DeviceID:    deviceID,
		Subject:     subject,
		Category:    "technical",
		Priority:    "high",
		AISessionID: &aiSessionID,
	}

	if err := s.ticketRepo.Create(ticket); err != nil {
		return nil, err
	}

	// Add the AI conversation as the initial system message
	msg := &model.TicketMessage{
		TicketID:   ticket.ID,
		SenderType: "device",
		SenderID:   deviceID,
		Content:    fmt.Sprintf("[Escalated from AI Assistant]\n\n%s", conversationContext),
	}
	if err := s.ticketRepo.CreateMessage(msg); err != nil {
		return nil, err
	}

	// Notify admin about escalated ticket
	ticket, _ = s.ticketRepo.FindByID(ticket.ID)
	if ticket != nil {
		resp := dto.TicketToResponse(ticket)
		s.publish("admin:notifications", sse.Event{
			Type: "ticket_escalated",
			Data: resp,
		})
	}

	return &ticket.ID, nil
}

// publish sends an SSE event if the hub is configured.
func (s *FeedbackService) publish(topic string, event sse.Event) {
	if s.hub != nil {
		s.hub.Publish(topic, event)
	}
}

// ==================== Feedback Stats ====================

func (s *FeedbackService) GetFeedbackStats(brand string) (map[string]interface{}, error) {
	ticketTotal, _ := s.ticketRepo.CountAll(brand)
	ticketByStatus, _ := s.ticketRepo.CountByStatus(brand)
	ticketOpenToday, _ := s.ticketRepo.CountOpenToday(brand)

	featureTotal, _ := s.featureRepo.CountAll(brand)
	featureByStatus, _ := s.featureRepo.CountByStatus(brand)

	ratingTotal, _ := s.ratingRepo.CountAll(brand)
	ratingAvg, _ := s.ratingRepo.AverageRating(brand)

	return map[string]interface{}{
		"tickets": map[string]interface{}{
			"total":      ticketTotal,
			"by_status":  ticketByStatus,
			"open_today": ticketOpenToday,
		},
		"feature_requests": map[string]interface{}{
			"total":     featureTotal,
			"by_status": featureByStatus,
		},
		"ratings": map[string]interface{}{
			"total":   ratingTotal,
			"average": ratingAvg,
		},
	}, nil
}
