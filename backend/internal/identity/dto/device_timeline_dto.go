package dto

import "time"

// TimelineEvent represents a single event in a device's chronological history.
type TimelineEvent struct {
	Type        string `json:"type"`        // crash, bug_report, download_error, ticket, license, device_registered
	Timestamp   string `json:"timestamp"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Severity    string `json:"severity"` // critical, high, medium, low, info
	RelatedID   string `json:"related_id"`
	Metadata    string `json:"metadata,omitempty"`
}

// DeviceTimelineResponse wraps a paginated timeline.
type DeviceTimelineResponse struct {
	Events     []TimelineEvent `json:"events"`
	TotalCount int64           `json:"total_count"`
}

// timelineRow is an internal struct for scanning unified timeline queries.
type TimelineRow struct {
	Type        string
	Timestamp   time.Time
	Title       string
	Description string
	Severity    string
	RelatedID   string
	Metadata    string
}
