package notifications

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/pkg/gemini"
	"github.com/snakeloader/backend/internal/pkg/logger"
)

// AutonomousAgent handles AI-powered auto-responses and auto-triage.
// Part of Phase S2: AI Agent Auto-Response.
type AutonomousAgent struct {
	geminiClient *gemini.Client
	notifier     *TelegramNotifier
	kbProvider   KnowledgeBaseProvider
}

// KnowledgeBaseProvider abstracts knowledge base access to avoid circular imports.
type KnowledgeBaseProvider interface {
	GetActiveKnowledge() ([]KnowledgeEntry, error)
}

// KnowledgeEntry is a simplified knowledge base entry.
type KnowledgeEntry struct {
	Category string
	Title    string
	Content  string
}

// TicketAutoResponse is the result of AI auto-responding to a ticket.
type TicketAutoResponse struct {
	Response   string
	Confidence string // "high", "medium", "low"
	ShouldEscalate bool
}

// BugTriageResult is the result of AI auto-triaging a bug report.
type BugTriageResult struct {
	Priority string // "critical", "high", "medium", "low"
	Category string // "crash", "ui", "download", "performance", "other"
	Summary  string // Brief AI analysis
}

// NewAutonomousAgent creates the AI agent. Returns nil if Gemini client is unavailable.
func NewAutonomousAgent(geminiClient *gemini.Client, notifier *TelegramNotifier, kbProvider KnowledgeBaseProvider) *AutonomousAgent {
	if geminiClient == nil {
		logger.Log.Info().Msg("Autonomous AI agent disabled (Gemini not configured)")
		return nil
	}
	logger.Log.Info().Msg("Autonomous AI agent initialized")
	return &AutonomousAgent{
		geminiClient: geminiClient,
		notifier:     notifier,
		kbProvider:   kbProvider,
	}
}

// ==================== S2.1: Ticket Auto-Response ====================

// AutoRespondToTicket generates an AI response for a new support ticket.
// Returns nil if the agent is disabled or AI fails (non-fatal).
func (a *AutonomousAgent) AutoRespondToTicket(ticketID uuid.UUID, subject, message, category string) *TicketAutoResponse {
	if a == nil {
		return nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	systemPrompt := a.buildTicketResponsePrompt()
	userPrompt := fmt.Sprintf(
		"New support ticket:\nSubject: %s\nCategory: %s\nMessage: %s\n\n"+
			"Respond with EXACTLY this format:\n"+
			"CONFIDENCE: [high/medium/low]\n"+
			"RESPONSE:\n[your helpful response to the user]",
		subject, category, message,
	)

	resp, err := a.geminiClient.Chat(ctx, systemPrompt, nil, userPrompt)
	if err != nil {
		logger.Log.Warn().Err(err).Str("ticket_id", ticketID.String()).Msg("AI auto-response failed")
		return nil
	}

	return parseTicketResponse(resp.Content)
}

func (a *AutonomousAgent) buildTicketResponsePrompt() string {
	var sb strings.Builder
	sb.WriteString("You are SSvid's autonomous AI support agent. Your job is to respond to support tickets 24/7.\n")
	sb.WriteString("SSvid is a desktop video downloader app that downloads from YouTube, TikTok, Instagram, and 1000+ sites.\n\n")
	sb.WriteString("Rules:\n")
	sb.WriteString("- Be concise, helpful, and professional. Max 300 words.\n")
	sb.WriteString("- If you can fully resolve the issue with clear steps, set CONFIDENCE: high\n")
	sb.WriteString("- If you can partially help but may need human follow-up, set CONFIDENCE: medium\n")
	sb.WriteString("- If the issue is unclear, complex, or about billing/account, set CONFIDENCE: low\n")
	sb.WriteString("- Never make up features or capabilities that don't exist.\n")
	sb.WriteString("- For billing/payment issues, always set CONFIDENCE: low (needs human).\n\n")

	// Inject knowledge base
	if a.kbProvider != nil {
		entries, err := a.kbProvider.GetActiveKnowledge()
		if err == nil && len(entries) > 0 {
			sb.WriteString("=== Knowledge Base ===\n")
			for _, e := range entries {
				sb.WriteString(fmt.Sprintf("[%s] %s\n%s\n\n", e.Category, e.Title, e.Content))
			}
		}
	}

	return sb.String()
}

func parseTicketResponse(aiOutput string) *TicketAutoResponse {
	result := &TicketAutoResponse{
		Confidence: "low",
	}

	lines := strings.Split(aiOutput, "\n")
	var responseLines []string
	inResponse := false

	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(strings.ToUpper(trimmed), "CONFIDENCE:") {
			conf := strings.TrimSpace(strings.TrimPrefix(strings.ToUpper(trimmed), "CONFIDENCE:"))
			conf = strings.ToLower(conf)
			if conf == "high" || conf == "medium" || conf == "low" {
				result.Confidence = conf
			}
			continue
		}
		if strings.HasPrefix(strings.ToUpper(trimmed), "RESPONSE:") {
			inResponse = true
			// Check if there's content on the same line
			after := strings.TrimSpace(strings.TrimPrefix(trimmed, "RESPONSE:"))
			if after == "" {
				after = strings.TrimSpace(strings.TrimPrefix(trimmed, "Response:"))
			}
			if after != "" {
				responseLines = append(responseLines, after)
			}
			continue
		}
		if inResponse {
			responseLines = append(responseLines, line)
		}
	}

	result.Response = strings.TrimSpace(strings.Join(responseLines, "\n"))
	if result.Response == "" {
		// Fallback: use the entire output as the response
		result.Response = strings.TrimSpace(aiOutput)
	}

	result.ShouldEscalate = result.Confidence == "low"
	return result
}

// ==================== S2.2: Bug Auto-Triage ====================

// AutoTriageBug analyzes a bug report and suggests priority and category.
// Returns nil if the agent is disabled or AI fails (non-fatal).
func (a *AutonomousAgent) AutoTriageBug(bugID uuid.UUID, title, description, steps, os, appVersion string) *BugTriageResult {
	if a == nil {
		return nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	systemPrompt := `You are SSvid's bug triage AI. Analyze bug reports and classify them.
SSvid is a desktop video downloader app (macOS, Windows, Linux).

Respond with EXACTLY this format:
PRIORITY: [critical/high/medium/low]
CATEGORY: [crash/ui/download/performance/other]
SUMMARY: [one-line analysis]

Priority guidelines:
- critical: App crashes, data loss, security issues, affects all users
- high: Core feature broken (downloads fail), blocks main workflow
- medium: Non-critical feature broken, workaround exists
- low: Cosmetic, minor UX issues, edge cases`

	userPrompt := fmt.Sprintf(
		"Bug Report:\nTitle: %s\nDescription: %s\nSteps to reproduce: %s\nOS: %s\nApp Version: %s",
		title, description, steps, os, appVersion,
	)

	resp, err := a.geminiClient.Chat(ctx, systemPrompt, nil, userPrompt)
	if err != nil {
		logger.Log.Warn().Err(err).Str("bug_id", bugID.String()).Msg("AI auto-triage failed")
		return nil
	}

	return parseBugTriageResponse(resp.Content)
}

func parseBugTriageResponse(aiOutput string) *BugTriageResult {
	result := &BugTriageResult{
		Priority: "medium",
		Category: "other",
	}

	for _, line := range strings.Split(aiOutput, "\n") {
		trimmed := strings.TrimSpace(line)
		upper := strings.ToUpper(trimmed)

		if strings.HasPrefix(upper, "PRIORITY:") {
			val := strings.ToLower(strings.TrimSpace(trimmed[9:]))
			if val == "critical" || val == "high" || val == "medium" || val == "low" {
				result.Priority = val
			}
		}
		if strings.HasPrefix(upper, "CATEGORY:") {
			val := strings.ToLower(strings.TrimSpace(trimmed[9:]))
			if val == "crash" || val == "ui" || val == "download" || val == "performance" || val == "other" {
				result.Category = val
			}
		}
		if strings.HasPrefix(upper, "SUMMARY:") {
			result.Summary = strings.TrimSpace(trimmed[8:])
		}
	}

	return result
}
