package sse

import (
	"encoding/json"
	"fmt"
	"io"

	"github.com/gin-gonic/gin"
)

// StreamHandler sets up SSE headers and streams events from the hub for the given topic.
// Blocks until the client disconnects. Returns false if the subscriber limit was reached.
func StreamHandler(c *gin.Context, hub *Hub, topic string) bool {
	ch, err := hub.Subscribe(topic)
	if err != nil {
		return false
	}

	c.Header("Content-Type", "text/event-stream")
	c.Header("Cache-Control", "no-cache")
	c.Header("Connection", "keep-alive")
	c.Header("X-Accel-Buffering", "no")

	defer hub.Unsubscribe(topic, ch)

	// Send initial connection event
	writeSSE(c.Writer, "connected", fmt.Sprintf(`{"topic":"%s"}`, topic))
	c.Writer.Flush()

	clientGone := c.Request.Context().Done()

	for {
		select {
		case <-clientGone:
			return true
		case event, ok := <-ch:
			if !ok {
				return true
			}
			data, err := json.Marshal(event.Data)
			if err != nil {
				continue
			}
			writeSSE(c.Writer, event.Type, string(data))
			c.Writer.Flush()
		}
	}
}

// writeSSE writes a single SSE event in the standard format.
func writeSSE(w io.Writer, event, data string) {
	fmt.Fprintf(w, "event: %s\ndata: %s\n\n", event, data)
}
