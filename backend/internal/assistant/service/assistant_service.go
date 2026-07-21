package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/assistant/dto"
	"github.com/snakeloader/backend/internal/assistant/model"
	"github.com/snakeloader/backend/internal/assistant/repository"
	"github.com/snakeloader/backend/internal/pkg/gemini"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"gorm.io/gorm"
)

var (
	ErrSessionNotFound     = errors.New("chat session not found")
	ErrSessionClosed       = errors.New("chat session is closed")
	ErrKnowledgeNotFound   = errors.New("knowledge base entry not found")
	ErrSessionAccessDenied = errors.New("access denied to this session")
)

// FeedbackServiceInterface defines the contract for creating tickets from escalation.
// Uses interface to avoid circular dependency with feedback service.
type FeedbackServiceInterface interface {
	CreateTicketFromEscalation(deviceID uuid.UUID, subject string, aiSessionID uuid.UUID, conversationContext string) (*uuid.UUID, error)
}

type AssistantService struct {
	chatRepo      *repository.ChatRepository
	knowledgeRepo *repository.KnowledgeRepository
	geminiClient  *gemini.Client           // nil = use keyword fallback
	feedbackSvc   FeedbackServiceInterface // nil = skip escalation ticket creation
}

func NewAssistantService(
	chatRepo *repository.ChatRepository,
	knowledgeRepo *repository.KnowledgeRepository,
	geminiClient *gemini.Client,
	feedbackSvc FeedbackServiceInterface,
) *AssistantService {
	return &AssistantService{
		chatRepo:      chatRepo,
		knowledgeRepo: knowledgeRepo,
		geminiClient:  geminiClient,
		feedbackSvc:   feedbackSvc,
	}
}

// ==================== Chat Sessions ====================

func (s *AssistantService) CreateSession(deviceID uuid.UUID, req dto.CreateSessionRequest) (*dto.SessionResponse, error) {
	// Generate title from first message (truncate to 100 chars)
	title := req.Message
	if len(title) > 100 {
		title = title[:97] + "..."
	}

	session := &model.ChatSession{
		DeviceID: deviceID,
		Title:    title,
	}

	if err := s.chatRepo.CreateSession(session); err != nil {
		return nil, err
	}

	// Save user message
	userMsg := &model.ChatMessage{
		SessionID: session.ID,
		Role:      "user",
		Content:   req.Message,
	}
	if err := s.chatRepo.CreateMessage(userMsg); err != nil {
		return nil, err
	}

	// Generate AI response
	aiResponse, tokensUsed := s.generateResponse(session.ID, req.Message)
	assistantMsg := &model.ChatMessage{
		SessionID:  session.ID,
		Role:       "assistant",
		Content:    aiResponse,
		TokensUsed: tokensUsed,
	}
	if err := s.chatRepo.CreateMessage(assistantMsg); err != nil {
		return nil, err
	}

	// Reload with messages
	session, err := s.chatRepo.FindSessionByID(session.ID)
	if err != nil {
		return nil, err
	}

	resp := dto.SessionToResponse(session)
	return &resp, nil
}

func (s *AssistantService) GetSession(id uuid.UUID) (*dto.SessionResponse, error) {
	session, err := s.chatRepo.FindSessionByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrSessionNotFound
		}
		return nil, err
	}
	resp := dto.SessionToResponse(session)
	return &resp, nil
}

func (s *AssistantService) GetDeviceSession(id, deviceID uuid.UUID) (*dto.SessionResponse, error) {
	session, err := s.chatRepo.FindSessionByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrSessionNotFound
		}
		return nil, err
	}
	if session.DeviceID != deviceID {
		return nil, ErrSessionAccessDenied
	}
	resp := dto.SessionToResponse(session)
	return &resp, nil
}

func (s *AssistantService) ListDeviceSessions(deviceID uuid.UUID) ([]dto.SessionListResponse, error) {
	sessions, err := s.chatRepo.ListByDevice(deviceID)
	if err != nil {
		return nil, err
	}
	return dto.SessionsToListResponse(sessions), nil
}

func (s *AssistantService) ListSessions(page, perPage int, status, brand string) ([]dto.SessionListResponse, int64, error) {
	page, perPage = pagination.Normalize(page, perPage, 20)

	sessions, total, err := s.chatRepo.List(page, perPage, status, brand)
	if err != nil {
		return nil, 0, err
	}
	return dto.SessionsToListResponse(sessions), total, nil
}

func (s *AssistantService) SendMessage(sessionID, deviceID uuid.UUID, req dto.SendMessageRequest) (*dto.ChatResponse, error) {
	session, err := s.chatRepo.FindSessionByID(sessionID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrSessionNotFound
		}
		return nil, err
	}
	if session.DeviceID != deviceID {
		return nil, ErrSessionAccessDenied
	}
	if session.Status != "active" {
		return nil, ErrSessionClosed
	}

	// Save user message
	userMsg := &model.ChatMessage{
		SessionID: sessionID,
		Role:      "user",
		Content:   req.Message,
	}
	if err := s.chatRepo.CreateMessage(userMsg); err != nil {
		return nil, err
	}

	// Generate AI response
	aiResponse, tokensUsed := s.generateResponse(sessionID, req.Message)
	assistantMsg := &model.ChatMessage{
		SessionID:  sessionID,
		Role:       "assistant",
		Content:    aiResponse,
		TokensUsed: tokensUsed,
	}
	if err := s.chatRepo.CreateMessage(assistantMsg); err != nil {
		return nil, err
	}

	return &dto.ChatResponse{
		UserMessage:      dto.MessageToResponse(userMsg),
		AssistantMessage: dto.MessageToResponse(assistantMsg),
	}, nil
}

func (s *AssistantService) EscalateSession(sessionID, deviceID uuid.UUID, req dto.EscalateRequest) (*dto.EscalationResponse, error) {
	session, err := s.chatRepo.FindSessionByID(sessionID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrSessionNotFound
		}
		return nil, err
	}
	if session.DeviceID != deviceID {
		return nil, ErrSessionAccessDenied
	}

	session.Status = "escalated"
	if err := s.chatRepo.UpdateSession(session); err != nil {
		return nil, err
	}

	// Add system message about escalation
	sysMsg := &model.ChatMessage{
		SessionID: sessionID,
		Role:      "system",
		Content:   fmt.Sprintf("This conversation has been escalated to human support. Subject: %s", req.Subject),
	}
	if err := s.chatRepo.CreateMessage(sysMsg); err != nil {
		return nil, err
	}

	// Build conversation context for ticket
	var contextLines []string
	for _, msg := range session.Messages {
		contextLines = append(contextLines, fmt.Sprintf("[%s] %s", msg.Role, msg.Content))
	}
	conversationContext := strings.Join(contextLines, "\n\n")

	// Create support ticket via feedback service
	var ticketID *uuid.UUID
	if s.feedbackSvc != nil {
		ticketID, err = s.feedbackSvc.CreateTicketFromEscalation(
			deviceID, req.Subject, sessionID, conversationContext,
		)
		if err != nil {
			logger.Log.Warn().Err(err).Msg("Failed to create escalation ticket")
			// Non-fatal: session is still escalated
		}
	}

	// Reload
	session, err = s.chatRepo.FindSessionByID(sessionID)
	if err != nil {
		return nil, err
	}

	sessionResp := dto.SessionToResponse(session)
	resp := &dto.EscalationResponse{
		Session: sessionResp,
	}
	if ticketID != nil {
		resp.TicketID = ticketID.String()
	}
	return resp, nil
}

// ==================== Knowledge Base ====================

func (s *AssistantService) CreateKnowledge(req dto.CreateKnowledgeRequest) (*dto.KnowledgeResponse, error) {
	kb := &model.KnowledgeBase{
		Title:    req.Title,
		Content:  req.Content,
		Category: req.Category,
		Tags:     req.Tags,
		IsActive: req.IsActive,
	}

	if err := s.knowledgeRepo.Create(kb); err != nil {
		return nil, err
	}

	resp := dto.KnowledgeToResponse(kb)
	return &resp, nil
}

func (s *AssistantService) GetKnowledge(id uuid.UUID) (*dto.KnowledgeResponse, error) {
	kb, err := s.knowledgeRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrKnowledgeNotFound
		}
		return nil, err
	}
	resp := dto.KnowledgeToResponse(kb)
	return &resp, nil
}

func (s *AssistantService) ListKnowledge(page, perPage int, category string, activeOnly bool) ([]dto.KnowledgeResponse, int64, error) {
	page, perPage = pagination.Normalize(page, perPage, 20)

	entries, total, err := s.knowledgeRepo.List(page, perPage, category, activeOnly)
	if err != nil {
		return nil, 0, err
	}
	return dto.KnowledgesToResponse(entries), total, nil
}

func (s *AssistantService) UpdateKnowledge(id uuid.UUID, req dto.UpdateKnowledgeRequest) (*dto.KnowledgeResponse, error) {
	kb, err := s.knowledgeRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrKnowledgeNotFound
		}
		return nil, err
	}

	if req.Title != nil {
		kb.Title = *req.Title
	}
	if req.Content != nil {
		kb.Content = *req.Content
	}
	if req.Category != nil {
		kb.Category = *req.Category
	}
	if req.Tags != nil {
		kb.Tags = *req.Tags
	}
	if req.IsActive != nil {
		kb.IsActive = *req.IsActive
	}

	if err := s.knowledgeRepo.Update(kb); err != nil {
		return nil, err
	}

	resp := dto.KnowledgeToResponse(kb)
	return &resp, nil
}

func (s *AssistantService) DeleteKnowledge(id uuid.UUID) error {
	_, err := s.knowledgeRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrKnowledgeNotFound
		}
		return err
	}
	return s.knowledgeRepo.Delete(id)
}

// ==================== Stats ====================

func (s *AssistantService) GetAssistantStats(brand string) (map[string]interface{}, error) {
	totalSessions, _ := s.chatRepo.CountSessions(brand)
	activeSessions, _ := s.chatRepo.CountActiveSessions(brand)
	totalMessages, _ := s.chatRepo.CountMessages(brand)
	totalTokens, _ := s.chatRepo.TotalTokensUsed(brand)
	totalKB, _ := s.knowledgeRepo.CountAll()
	activeKB, _ := s.knowledgeRepo.CountActive()

	return map[string]interface{}{
		"sessions": map[string]int64{
			"total":  totalSessions,
			"active": activeSessions,
		},
		"messages": map[string]int64{
			"total": totalMessages,
		},
		"tokens_used": totalTokens,
		"knowledge_base": map[string]int64{
			"total":  totalKB,
			"active": activeKB,
		},
		"gemini_enabled": s.geminiClient != nil,
	}, nil
}

// ==================== AI Response Generation ====================

// generateResponse creates an AI response using Gemini API with keyword-based fallback.
func (s *AssistantService) generateResponse(sessionID uuid.UUID, userMessage string) (string, int) {
	// Try Gemini first
	if s.geminiClient != nil {
		resp, err := s.generateGeminiResponse(sessionID, userMessage)
		if err != nil {
			logger.Log.Warn().Err(err).Msg("Gemini API failed, falling back to keyword-based")
		} else {
			return resp.Content, resp.TokensUsed
		}
	}

	// Fallback to keyword-based
	response := s.generateKeywordResponse(userMessage)
	return response, estimateTokens(userMessage) + estimateTokens(response)
}

// generateGeminiResponse calls the Gemini API with full conversation context.
func (s *AssistantService) generateGeminiResponse(sessionID uuid.UUID, userMessage string) (*gemini.Response, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Build system prompt with knowledge base
	systemPrompt := s.buildSystemPrompt()

	// Get conversation history
	session, err := s.chatRepo.FindSessionByID(sessionID)
	if err != nil {
		return nil, err
	}

	var history []gemini.Message
	for _, msg := range session.Messages {
		history = append(history, gemini.Message{
			Role:    msg.Role,
			Content: msg.Content,
		})
	}

	return s.geminiClient.Chat(ctx, systemPrompt, history, userMessage)
}

// buildSystemPrompt creates the system prompt with knowledge base context.
func (s *AssistantService) buildSystemPrompt() string {
	var sb strings.Builder
	sb.WriteString("You are Svid AI support assistant for the Svid (SnakeLoader) desktop video downloader app. ")
	sb.WriteString("Help users with download issues, app setup, troubleshooting, and general questions. ")
	sb.WriteString("Be concise, helpful, and friendly. Keep responses under 500 words. ")
	sb.WriteString("If you cannot resolve the issue, suggest the user escalate to human support.\n\n")

	// Inject knowledge base entries as context
	entries, err := s.knowledgeRepo.ListActive()
	if err == nil && len(entries) > 0 {
		sb.WriteString("=== Knowledge Base (use this to answer questions) ===\n")
		for _, e := range entries {
			sb.WriteString(fmt.Sprintf("[%s] %s\n%s\n\n", e.Category, e.Title, e.Content))
		}
	}

	return sb.String()
}

// generateKeywordResponse is the fallback when Gemini is unavailable.
func (s *AssistantService) generateKeywordResponse(userMessage string) string {
	lowerMsg := strings.ToLower(userMessage)

	// Search knowledge base for relevant entries
	entries, _ := s.knowledgeRepo.Search(extractKeywords(userMessage))
	if len(entries) > 0 {
		var parts []string
		parts = append(parts, "Based on our knowledge base, here's what I found:\n")
		for _, e := range entries {
			parts = append(parts, fmt.Sprintf("**%s**\n%s", e.Title, e.Content))
		}
		parts = append(parts, "\nIs there anything else I can help you with?")
		return strings.Join(parts, "\n\n")
	}

	// Default responses based on common topics
	if containsAny(lowerMsg, []string{"download", "downloading", "save"}) {
		return "I can help with download issues. Here are some common solutions:\n\n1. Make sure you have a stable internet connection\n2. Check that the URL is valid and accessible\n3. Try restarting the app if downloads are stuck\n4. For large files, ensure you have enough disk space\n\nIf the issue persists, you can escalate this to our support team."
	}

	if containsAny(lowerMsg, []string{"crash", "error", "bug", "broken"}) {
		return "I'm sorry you're experiencing issues. Here's what you can try:\n\n1. Update to the latest version of the app\n2. Clear the app cache in Settings\n3. Restart the application\n4. If the crash persists, please submit a bug report with the crash details\n\nWould you like me to escalate this to our support team?"
	}

	if containsAny(lowerMsg, []string{"install", "setup", "configure"}) {
		return "For installation and setup help:\n\n1. Download the latest version from our website\n2. Follow the installation wizard\n3. Grant necessary permissions when prompted\n4. The app will auto-configure on first run\n\nIs there a specific step you need help with?"
	}

	if containsAny(lowerMsg, []string{"price", "plan", "subscription", "pro", "premium", "upgrade"}) {
		return "Here's information about our plans:\n\n- **Free**: Basic download features, limited concurrent downloads\n- **Pro**: Unlimited downloads, batch downloads, priority support\n\nYou can upgrade from the app settings. Would you like more details about any specific plan?"
	}

	return "Thank you for your message. I'm the Svid AI assistant. I can help with:\n\n- Download issues\n- App installation and setup\n- Troubleshooting errors\n- Plan and subscription questions\n\nCould you provide more details about what you need help with? If my answers aren't helpful enough, you can escalate this conversation to our human support team."
}

// extractKeywords returns a simplified search string from user message
func extractKeywords(msg string) string {
	stopWords := map[string]bool{
		"the": true, "a": true, "an": true, "is": true, "are": true,
		"was": true, "were": true, "be": true, "been": true, "being": true,
		"have": true, "has": true, "had": true, "do": true, "does": true,
		"did": true, "will": true, "would": true, "could": true, "should": true,
		"may": true, "might": true, "can": true, "i": true, "you": true,
		"we": true, "they": true, "it": true, "my": true, "your": true,
		"how": true, "what": true, "when": true, "where": true, "why": true,
		"to": true, "for": true, "with": true, "from": true, "in": true,
		"on": true, "at": true, "of": true, "not": true, "this": true,
		"that": true, "and": true, "or": true, "but": true, "if": true,
	}

	words := strings.Fields(strings.ToLower(msg))
	var keywords []string
	for _, w := range words {
		w = strings.Trim(w, ".,?!;:'\"")
		if len(w) > 2 && !stopWords[w] {
			keywords = append(keywords, w)
		}
	}

	if len(keywords) > 5 {
		keywords = keywords[:5]
	}

	return strings.Join(keywords, " ")
}

func containsAny(s string, terms []string) bool {
	for _, t := range terms {
		if strings.Contains(s, t) {
			return true
		}
	}
	return false
}

func estimateTokens(text string) int {
	return len(text) / 4
}
