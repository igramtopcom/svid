package sse

import (
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/snakeloader/backend/internal/pkg/logger"
)

func init() {
	// Initialize logger to prevent nil dereference in Hub methods.
	logger.Init("debug")
}

func TestSubscribe_ReturnsChannelNormally(t *testing.T) {
	hub := NewHub()
	ch, err := hub.Subscribe("topic-a")
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if ch == nil {
		t.Fatal("expected non-nil channel")
	}
}

func TestSubscribe_ReturnsErrorAfterMaxSubscribers(t *testing.T) {
	hub := NewHub()
	topic := "limited-topic"
	channels := make([]chan Event, 0, MaxSubscribersPerTopic)

	// Subscribe up to the limit.
	for i := 0; i < MaxSubscribersPerTopic; i++ {
		ch, err := hub.Subscribe(topic)
		if err != nil {
			t.Fatalf("subscribe %d: unexpected error: %v", i, err)
		}
		channels = append(channels, ch)
	}

	// Next subscribe should fail.
	ch, err := hub.Subscribe(topic)
	if !errors.Is(err, ErrTooManySubscribers) {
		t.Fatalf("expected ErrTooManySubscribers, got %v", err)
	}
	if ch != nil {
		t.Fatal("expected nil channel on error")
	}
}

func TestUnsubscribe_FreesSlot(t *testing.T) {
	hub := NewHub()
	topic := "slot-topic"
	channels := make([]chan Event, 0, MaxSubscribersPerTopic)

	// Fill all slots.
	for i := 0; i < MaxSubscribersPerTopic; i++ {
		ch, err := hub.Subscribe(topic)
		if err != nil {
			t.Fatalf("subscribe %d: unexpected error: %v", i, err)
		}
		channels = append(channels, ch)
	}

	// Unsubscribe one.
	hub.Unsubscribe(topic, channels[0])

	// Now subscribing should succeed.
	ch, err := hub.Subscribe(topic)
	if err != nil {
		t.Fatalf("expected subscribe to succeed after unsubscribe, got %v", err)
	}
	if ch == nil {
		t.Fatal("expected non-nil channel")
	}
}

func TestSubscribe_IndependentTopicLimits(t *testing.T) {
	hub := NewHub()

	// Fill topic-a to the max.
	for i := 0; i < MaxSubscribersPerTopic; i++ {
		if _, err := hub.Subscribe("topic-a"); err != nil {
			t.Fatalf("topic-a subscribe %d: %v", i, err)
		}
	}

	// topic-b should still accept subscribers.
	ch, err := hub.Subscribe("topic-b")
	if err != nil {
		t.Fatalf("topic-b subscribe should succeed, got %v", err)
	}
	if ch == nil {
		t.Fatal("expected non-nil channel for topic-b")
	}
}

func TestSubscriberCount(t *testing.T) {
	hub := NewHub()
	topic := "count-topic"

	if count := hub.SubscriberCount(topic); count != 0 {
		t.Fatalf("expected 0 subscribers, got %d", count)
	}

	ch1, _ := hub.Subscribe(topic)
	ch2, _ := hub.Subscribe(topic)

	if count := hub.SubscriberCount(topic); count != 2 {
		t.Fatalf("expected 2 subscribers, got %d", count)
	}

	hub.Unsubscribe(topic, ch1)
	if count := hub.SubscriberCount(topic); count != 1 {
		t.Fatalf("expected 1 subscriber after unsubscribe, got %d", count)
	}

	hub.Unsubscribe(topic, ch2)
	if count := hub.SubscriberCount(topic); count != 0 {
		t.Fatalf("expected 0 subscribers after all unsubscribed, got %d", count)
	}
}

func TestPublish_DeliversEventsToSubscribers(t *testing.T) {
	hub := NewHub()
	topic := "pub-topic"

	ch1, _ := hub.Subscribe(topic)
	ch2, _ := hub.Subscribe(topic)

	event := Event{Type: "test", Data: "hello"}
	hub.Publish(topic, event)

	// Both subscribers should receive the event.
	select {
	case got := <-ch1:
		if got.Type != "test" || got.Data != "hello" {
			t.Fatalf("ch1: unexpected event: %+v", got)
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatal("ch1: timed out waiting for event")
	}

	select {
	case got := <-ch2:
		if got.Type != "test" || got.Data != "hello" {
			t.Fatalf("ch2: unexpected event: %+v", got)
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatal("ch2: timed out waiting for event")
	}
}

func TestPublish_DropsEventsForSlowClients(t *testing.T) {
	hub := NewHub()
	topic := "slow-topic"

	ch, _ := hub.Subscribe(topic)

	// Fill the channel buffer (buffer size is 10).
	for i := 0; i < 10; i++ {
		hub.Publish(topic, Event{Type: "fill", Data: i})
	}

	// Next publish should be dropped (non-blocking), not panic or block.
	done := make(chan struct{})
	go func() {
		hub.Publish(topic, Event{Type: "overflow", Data: "dropped"})
		close(done)
	}()

	select {
	case <-done:
		// Good - Publish returned without blocking.
	case <-time.After(1 * time.Second):
		t.Fatal("Publish blocked on full channel — expected non-blocking drop")
	}

	// The channel should have exactly 10 buffered items (the overflow was dropped).
	if len(ch) != 10 {
		t.Fatalf("expected 10 buffered events, got %d", len(ch))
	}
}

func TestPublish_NoSubscribers_DoesNotPanic(t *testing.T) {
	hub := NewHub()
	// Should not panic when publishing to a topic with no subscribers.
	hub.Publish("empty-topic", Event{Type: "test", Data: nil})
}

func TestHub_ConcurrentAccess(t *testing.T) {
	hub := NewHub()
	topic := "concurrent-topic"
	var wg sync.WaitGroup

	// Concurrent subscribes and publishes to verify thread safety.
	for i := 0; i < 5; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ch, err := hub.Subscribe(topic)
			if err != nil {
				return
			}
			hub.Publish(topic, Event{Type: "ping", Data: nil})
			hub.Unsubscribe(topic, ch)
		}()
	}

	wg.Wait()
}
