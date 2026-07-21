package sse

import (
	"errors"
	"sync"

	"github.com/snakeloader/backend/internal/pkg/logger"
)

// MaxSubscribersPerTopic limits concurrent SSE connections per topic to prevent goroutine leaks.
const MaxSubscribersPerTopic = 10

// ErrTooManySubscribers is returned when a topic has reached its connection limit.
var ErrTooManySubscribers = errors.New("too many SSE subscribers for this topic")

// Event represents a server-sent event with a type and data payload.
type Event struct {
	Type string      `json:"type"`
	Data interface{} `json:"data"`
}

// Hub manages SSE subscriptions using topic-based pub/sub pattern.
// Thread-safe for concurrent access.
type Hub struct {
	mu          sync.RWMutex
	subscribers map[string]map[chan Event]struct{}
}

// NewHub creates a new SSE Hub.
func NewHub() *Hub {
	return &Hub{
		subscribers: make(map[string]map[chan Event]struct{}),
	}
}

// Subscribe registers a new subscriber for the given topic.
// Returns a buffered channel that receives events, or an error if the topic
// has reached its connection limit (MaxSubscribersPerTopic).
func (h *Hub) Subscribe(topic string) (chan Event, error) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if h.subscribers[topic] != nil && len(h.subscribers[topic]) >= MaxSubscribersPerTopic {
		logger.Log.Warn().Str("topic", topic).Int("limit", MaxSubscribersPerTopic).Msg("SSE subscriber limit reached")
		return nil, ErrTooManySubscribers
	}

	ch := make(chan Event, 10)
	if h.subscribers[topic] == nil {
		h.subscribers[topic] = make(map[chan Event]struct{})
	}
	h.subscribers[topic][ch] = struct{}{}

	logger.Log.Debug().Str("topic", topic).Msg("SSE client subscribed")
	return ch, nil
}

// Unsubscribe removes a subscriber from the given topic and closes its channel.
func (h *Hub) Unsubscribe(topic string, ch chan Event) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if subs, ok := h.subscribers[topic]; ok {
		delete(subs, ch)
		close(ch)
		if len(subs) == 0 {
			delete(h.subscribers, topic)
		}
	}

	logger.Log.Debug().Str("topic", topic).Msg("SSE client unsubscribed")
}

// Publish sends an event to all subscribers of the given topic.
// Non-blocking: drops events for slow clients.
func (h *Hub) Publish(topic string, event Event) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	if subs, ok := h.subscribers[topic]; ok {
		for ch := range subs {
			select {
			case ch <- event:
			default:
				logger.Log.Warn().Str("topic", topic).Msg("SSE client too slow, dropping event")
			}
		}
	}
}

// SubscriberCount returns the number of active subscribers for a topic.
func (h *Hub) SubscriberCount(topic string) int {
	h.mu.RLock()
	defer h.mu.RUnlock()

	if subs, ok := h.subscribers[topic]; ok {
		return len(subs)
	}
	return 0
}
