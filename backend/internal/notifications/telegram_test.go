package notifications

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

// ==================== Anomaly Notification ====================

func TestNotifyRegistrationAnomaly_MessageContent(t *testing.T) {
	var sent []string
	notifier := &TelegramNotifier{
		now:      func() time.Time { return time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC) },
		sendFunc: func(text string) { sent = append(sent, text) },
		bursts:   make(map[string]telegramBurstState),
	}

	notifier.NotifyRegistrationAnomaly("192.168.1.100", 11, "suspicious-hw-id")

	if len(sent) != 1 {
		t.Fatalf("expected 1 anomaly notification, got %d", len(sent))
	}
	if !strings.Contains(sent[0], "Registration Anomaly Detected") {
		t.Fatalf("expected anomaly title in notification, got %q", sent[0])
	}
	if !strings.Contains(sent[0], "192.168.1.100") || !strings.Contains(sent[0], "suspicious-hw-id") {
		t.Fatalf("expected IP and hardware id in notification, got %q", sent[0])
	}
}

func TestNotifyRegistrationAnomaly_NilNotifier(t *testing.T) {
	// A nil notifier should not panic (same as other Telegram methods).
	var notifier *TelegramNotifier
	// This should not panic
	notifier.send("test message") // send checks for nil
}

// ==================== Message Formatting ====================

func TestEscapeHTML_SpecialCharacters(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"hello", "hello"},
		{"a < b", "a &lt; b"},
		{"a > b", "a &gt; b"},
		{"a & b", "a &amp; b"},
		{"<script>alert('xss')</script>", "&lt;script&gt;alert('xss')&lt;/script&gt;"},
		{"Tom & Jerry > Cat & Mouse", "Tom &amp; Jerry &gt; Cat &amp; Mouse"},
		{"", ""},
	}

	for _, tt := range tests {
		got := escapeHTML(tt.input)
		if got != tt.expected {
			t.Errorf("escapeHTML(%q) = %q, want %q", tt.input, got, tt.expected)
		}
	}
}

func TestMaskKey_ShortKey(t *testing.T) {
	// Keys shorter than 15 chars should not be masked
	short := "SVID-1234"
	if maskKey(short) != short {
		t.Errorf("expected short key to be returned as-is, got %q", maskKey(short))
	}
}

func TestMaskKey_SvidKey(t *testing.T) {
	key := "SVID-abcd-ef01-2345-6789-abcd-ef01-2345-6789"
	masked := maskKey(key)
	// Should start with first 10 chars and end with last 4 chars
	if !strings.HasPrefix(masked, "SVID-abcd") {
		t.Errorf("masked SVID key should start with first 10 chars, got %q", masked)
	}
	if !strings.HasSuffix(masked, "6789") {
		t.Errorf("masked SVID key should end with last 4 chars, got %q", masked)
	}
	if !strings.Contains(masked, "****") {
		t.Errorf("masked SVID key should contain ****, got %q", masked)
	}
}

func TestMaskKey_VidComboKey(t *testing.T) {
	key := "VIDCOMBO-aaaa-bbbb-cccc-dddd-eeee-ffff-0000-1111"
	masked := maskKey(key)
	// Should start with first 10 chars ("VIDCOMBO-a") and end with last 4 chars
	if !strings.HasPrefix(masked, "VIDCOMBO-a") {
		t.Errorf("masked VIDCOMBO key should start with first 10 chars, got %q", masked)
	}
	if !strings.HasSuffix(masked, "1111") {
		t.Errorf("masked VIDCOMBO key should end with last 4 chars, got %q", masked)
	}
	if !strings.Contains(masked, "****") {
		t.Errorf("masked VIDCOMBO key should contain ****, got %q", masked)
	}
}

func TestPriorityEmoji(t *testing.T) {
	tests := []struct {
		priority string
		emoji    string
	}{
		{"critical", "🔴"},
		{"CRITICAL", "🔴"},
		{"high", "🟠"},
		{"medium", "🟡"},
		{"low", "🟢"},
		{"unknown", "🟢"},
	}

	for _, tt := range tests {
		got := priorityEmoji(tt.priority)
		if got != tt.emoji {
			t.Errorf("priorityEmoji(%q) = %q, want %q", tt.priority, got, tt.emoji)
		}
	}
}

func TestSeverityEmoji(t *testing.T) {
	tests := []struct {
		severity string
		emoji    string
	}{
		{"critical", "🔴"},
		{"high", "🟠"},
		{"medium", "🟡"},
		{"low", "🟢"},
	}

	for _, tt := range tests {
		got := severityEmoji(tt.severity)
		if got != tt.emoji {
			t.Errorf("severityEmoji(%q) = %q, want %q", tt.severity, got, tt.emoji)
		}
	}
}

// ==================== Daily Digest Formatting ====================

func TestSendDailyDigest_NilNotifier(t *testing.T) {
	// Nil notifier should not panic
	var notifier *TelegramNotifier
	notifier.SendDailyDigest(DailyDigestStats{})
}

func TestDailyDigestStats_Serialization(t *testing.T) {
	stats := DailyDigestStats{
		TotalDevices:        150,
		NewDevicesToday:     5,
		ActiveDevices7d:     42,
		ActiveDevices30d:    98,
		OpenBugs:            3,
		NewBugsToday:        1,
		CrashesToday:        0,
		OpenTickets:         2,
		NewTicketsToday:     0,
		DownloadSuccessRate: 97,
		DownloadsToday:      1234,
		RatingAverage:       4.5,
		TotalRatings:        28,
		RevenueTodayCents:   0,
		ActiveLicenses:      1,
		PremiumLicenses:     1,
		CrashGroupsActive:   5,
		CrashGroupsNewToday: 0,
		DownloadErrorsToday: 12,
		TopErrorCodes:       []string{"NETWORK_ERROR", "PARSE_FAILED"},
	}

	// Verify struct can be serialized (used by various reporting endpoints)
	data, err := json.Marshal(stats)
	if err != nil {
		t.Fatalf("failed to marshal DailyDigestStats: %v", err)
	}

	var decoded DailyDigestStats
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("failed to unmarshal DailyDigestStats: %v", err)
	}

	if decoded.TotalDevices != 150 {
		t.Errorf("TotalDevices: want 150, got %d", decoded.TotalDevices)
	}
	if decoded.DownloadSuccessRate != 97 {
		t.Errorf("DownloadSuccessRate: want 97, got %d", decoded.DownloadSuccessRate)
	}
	if len(decoded.TopErrorCodes) != 2 {
		t.Errorf("TopErrorCodes: want 2 items, got %d", len(decoded.TopErrorCodes))
	}
	if decoded.ActiveLicenses != 1 {
		t.Errorf("ActiveLicenses: want 1, got %d", decoded.ActiveLicenses)
	}
}

// ==================== Notifier Construction ====================

func TestNewTelegramNotifier_NilOnMissingConfig(t *testing.T) {
	tests := []struct {
		name    string
		token   string
		chatID  string
		wantNil bool
	}{
		{"both empty", "", "", true},
		{"token only", "bot123", "", true},
		{"chatID only", "", "12345", true},
		{"both present", "bot123", "12345", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			n := NewTelegramNotifier(tt.token, tt.chatID)
			if tt.wantNil && n != nil {
				t.Error("expected nil notifier")
			}
			if !tt.wantNil && n == nil {
				t.Error("expected non-nil notifier")
			}
		})
	}
}

func TestNotifyNewCrash_CollapsesBurstNotifications(t *testing.T) {
	base := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	var sent []string
	notifier := &TelegramNotifier{
		now:      func() time.Time { return base },
		sendFunc: func(text string) { sent = append(sent, text) },
		bursts:   make(map[string]telegramBurstState),
	}

	notifier.NotifyNewCrash("crash-1", "Invalid argument(s): No host specified in URI C:/Users/Alice/AppData/Local/legacy_thumbnails/14.jpg", "high", "windows", "1.6.2")
	notifier.NotifyNewCrash("crash-2", "Invalid argument(s): No host specified in URI C:/Users/Bob/AppData/Local/legacy_thumbnails/99.jpg", "high", "windows", "1.6.2")

	if len(sent) != 1 {
		t.Fatalf("expected 1 message during burst window, got %d", len(sent))
	}

	notifier.now = func() time.Time { return base.Add(crashBurstWindow + time.Minute) }
	notifier.NotifyNewCrash("crash-3", "Invalid argument(s): No host specified in URI C:/Users/Carol/AppData/Local/legacy_thumbnails/15.jpg", "high", "windows", "1.6.2")

	if len(sent) != 2 {
		t.Fatalf("expected second message after burst window, got %d", len(sent))
	}
	if !strings.Contains(sent[1], "1 similar event(s) suppressed") {
		t.Fatalf("expected suppression summary in second message, got %q", sent[1])
	}
}

func TestSendDailyDigest_UsesActiveLicensesAndPremiumSuffix(t *testing.T) {
	base := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	var sent []string
	notifier := &TelegramNotifier{
		now:      func() time.Time { return base },
		sendFunc: func(text string) { sent = append(sent, text) },
	}

	notifier.SendDailyDigest(DailyDigestStats{
		TotalDevices:        150,
		NewDevicesToday:     5,
		ActiveDevices7d:     42,
		ActiveDevices30d:    98,
		OpenBugs:            3,
		NewBugsToday:        1,
		CrashesToday:        0,
		OpenTickets:         2,
		NewTicketsToday:     0,
		DownloadSuccessRate: 97,
		DownloadsToday:      1234,
		RatingAverage:       4.5,
		TotalRatings:        28,
		RevenueTodayCents:   799,
		ActiveLicenses:      6,
		PremiumLicenses:     9,
		CrashGroupsActive:   5,
		CrashGroupsNewToday: 1,
		DownloadErrorsToday: 12,
		TopErrorCodes:       []string{"NETWORK_ERROR", "PARSE_FAILED"},
	})

	if len(sent) != 1 {
		t.Fatalf("expected 1 digest message, got %d", len(sent))
	}
	if !strings.Contains(sent[0], "Active licenses: 6 | Premium total: 9") {
		t.Fatalf("expected active/premium license summary, got %q", sent[0])
	}
	if !strings.Contains(sent[0], "Svid Daily Digest — 2026-04-22") {
		t.Fatalf("expected deterministic UTC date in digest, got %q", sent[0])
	}
}
