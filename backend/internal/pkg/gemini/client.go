package gemini

import (
	"context"
	"fmt"
	"strings"

	"github.com/google/generative-ai-go/genai"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"google.golang.org/api/option"
)

// Client wraps the Google Gemini generative AI client.
type Client struct {
	client *genai.Client
	model  string
}

// Message represents a single chat message with role and content.
type Message struct {
	Role    string // "user", "assistant", "system"
	Content string
}

// Response contains the AI-generated response and token usage.
type Response struct {
	Content    string
	TokensUsed int
}

// NewClient creates a new Gemini client. Returns error if API key is empty.
func NewClient(apiKey, model string) (*Client, error) {
	if apiKey == "" {
		return nil, fmt.Errorf("gemini API key not configured")
	}
	ctx := context.Background()
	client, err := genai.NewClient(ctx, option.WithAPIKey(apiKey))
	if err != nil {
		return nil, fmt.Errorf("failed to create Gemini client: %w", err)
	}
	if model == "" {
		model = "gemini-2.5-flash"
	}
	return &Client{client: client, model: model}, nil
}

// Chat sends a message to Gemini with conversation history and system prompt.
// Returns the AI response and token count.
func (c *Client) Chat(ctx context.Context, systemPrompt string, history []Message, userMessage string) (*Response, error) {
	model := c.client.GenerativeModel(c.model)

	// Set system instruction
	if systemPrompt != "" {
		model.SystemInstruction = &genai.Content{
			Parts: []genai.Part{genai.Text(systemPrompt)},
		}
	}

	// Configure generation
	temp := float32(0.7)
	model.Temperature = &temp
	topP := float32(0.9)
	model.TopP = &topP

	cs := model.StartChat()

	// Build history from prior messages (skip system messages)
	for _, msg := range history {
		var role string
		switch msg.Role {
		case "user":
			role = "user"
		case "assistant":
			role = "model"
		default:
			continue
		}
		cs.History = append(cs.History, &genai.Content{
			Parts: []genai.Part{genai.Text(msg.Content)},
			Role:  role,
		})
	}

	// Send user message
	resp, err := cs.SendMessage(ctx, genai.Text(userMessage))
	if err != nil {
		return nil, fmt.Errorf("gemini API error: %w", err)
	}

	// Extract text from response
	var sb strings.Builder
	for _, cand := range resp.Candidates {
		if cand.Content != nil {
			for _, part := range cand.Content.Parts {
				sb.WriteString(fmt.Sprintf("%v", part))
			}
		}
	}

	text := strings.TrimSpace(sb.String())
	if text == "" {
		return nil, fmt.Errorf("gemini returned empty response")
	}

	// Extract token usage
	tokensUsed := 0
	if resp.UsageMetadata != nil {
		tokensUsed = int(resp.UsageMetadata.TotalTokenCount)
	}

	logger.Log.Debug().
		Int("tokens", tokensUsed).
		Int("response_len", len(text)).
		Msg("Gemini response received")

	return &Response{Content: text, TokensUsed: tokensUsed}, nil
}

// Close cleans up the Gemini client resources.
func (c *Client) Close() {
	if c.client != nil {
		c.client.Close()
	}
}
