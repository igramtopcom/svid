package notifications

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/snakeloader/backend/internal/pkg/logger"
)

// TelegramNotifier sends real-time event notifications to a Telegram chat.
// Part of Phase S1: Telegram Command Center.
type TelegramNotifier struct {
	botToken    string
	adminChatID string
	httpClient  *http.Client
	mu          sync.Mutex
	now         func() time.Time
	sendFunc    func(string)
	bursts      map[string]telegramBurstState
}

type telegramBurstState struct {
	lastSentAt time.Time
	suppressed int
}

var (
	telegramFileURIRegex     = regexp.MustCompile(`(?i)file:///[^\s"'()]+`)
	telegramWindowsPathRegex = regexp.MustCompile(`(?i)\b[a-z]:[\\/][^\s"'()]+`)
	telegramUnixPathRegex    = regexp.MustCompile(`(^|[\s"'(])(/(?:[^/\s"'()]+/)+[^/\s"'()]+)`)
)

const (
	deviceBurstWindow       = 15 * time.Minute
	registrationBurstWindow = 30 * time.Minute
	bugBurstWindow          = 30 * time.Minute
	crashBurstWindow        = 30 * time.Minute
	ratingBurstWindow       = 30 * time.Minute
	aiAutoResponseWindow    = 1 * time.Hour
)

// NewTelegramNotifier creates a notifier. Returns nil if bot token or chat ID is empty.
func NewTelegramNotifier(botToken, adminChatID string) *TelegramNotifier {
	if botToken == "" || adminChatID == "" {
		logger.Log.Info().Msg("Telegram notifier disabled (missing TELEGRAM_BOT_TOKEN or TELEGRAM_ADMIN_CHAT_ID)")
		return nil
	}
	logger.Log.Info().Msg("Telegram Command Center initialized")
	return &TelegramNotifier{
		botToken:    botToken,
		adminChatID: adminChatID,
		httpClient:  &http.Client{Timeout: 10 * time.Second},
		now:         time.Now,
		bursts:      make(map[string]telegramBurstState),
	}
}

// send posts a message to Telegram using MarkdownV2 parse mode.
func (t *TelegramNotifier) send(text string) {
	if t == nil {
		return
	}

	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", t.botToken)
	payload := map[string]string{
		"chat_id":    t.adminChatID,
		"text":       text,
		"parse_mode": "HTML",
	}
	body, _ := json.Marshal(payload)

	resp, err := t.httpClient.Post(url, "application/json", bytes.NewBuffer(body))
	if err != nil {
		logger.Log.Warn().Err(err).Msg("Telegram notification failed")
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		logger.Log.Warn().Int("status", resp.StatusCode).Msg("Telegram API returned non-200")
	}
}

func (t *TelegramNotifier) dispatch(text string) {
	if t == nil {
		return
	}
	if t.sendFunc != nil {
		t.sendFunc(text)
		return
	}
	go t.send(text)
}

func (t *TelegramNotifier) dispatchSync(text string) {
	if t == nil {
		return
	}
	if t.sendFunc != nil {
		t.sendFunc(text)
		return
	}
	t.send(text)
}

func (t *TelegramNotifier) currentTime() time.Time {
	if t == nil || t.now == nil {
		return time.Now()
	}
	return t.now()
}

func (t *TelegramNotifier) sendCollapsed(key string, window time.Duration, build func(suppressed int) string) {
	if t == nil {
		return
	}

	now := t.currentTime()
	var (
		shouldSend bool
		suppressed int
	)

	t.mu.Lock()
	if t.bursts == nil {
		t.bursts = make(map[string]telegramBurstState)
	}
	state := t.bursts[key]
	if state.lastSentAt.IsZero() || now.Sub(state.lastSentAt) >= window {
		shouldSend = true
		suppressed = state.suppressed
		state.lastSentAt = now
		state.suppressed = 0
	} else {
		state.suppressed++
	}
	t.bursts[key] = state
	t.mu.Unlock()

	if shouldSend {
		t.dispatch(build(suppressed))
	}
}

// ==================== S1.1: Event Notifications ====================

// NotifyNewDevice sends notification when a new device registers.
func (t *TelegramNotifier) NotifyNewDevice(deviceID, os, osVersion, appVersion, deviceName string) {
	name := deviceName
	if name == "" {
		name = "Unknown"
	}
	t.sendCollapsed("new_device", deviceBurstWindow, func(suppressed int) string {
		msg := fmt.Sprintf(
			"📱 <b>New Device Registered</b>\n\n"+
				"<b>Name:</b> %s\n"+
				"<b>OS:</b> %s %s\n"+
				"<b>App:</b> v%s\n"+
				"<b>ID:</b> <code>%s</code>%s",
			escapeHTML(name), escapeHTML(os), escapeHTML(osVersion),
			escapeHTML(appVersion), deviceID,
			suppressionSuffix(suppressed, deviceBurstWindow),
		)
		return msg
	})
}

// NotifyRegistrationAnomaly alerts when an IP registers too many devices in a short window.
func (t *TelegramNotifier) NotifyRegistrationAnomaly(ip string, count int64, latestHardwareID string) {
	t.sendCollapsed("registration_anomaly:"+strings.ToLower(strings.TrimSpace(ip)), registrationBurstWindow, func(suppressed int) string {
		return fmt.Sprintf(
			"🚨 <b>Registration Anomaly Detected</b>\n\n"+
				"<b>IP:</b> <code>%s</code>\n"+
				"<b>Registrations (1h):</b> %d\n"+
				"<b>Latest HW ID:</b> <code>%s</code>\n\n"+
				"⚠️ Possible bot spam or abuse — consider IP ban%s",
			escapeHTML(ip), count, escapeHTML(latestHardwareID),
			suppressionSuffix(suppressed, registrationBurstWindow),
		)
	})
}

// NotifyNewBug sends notification when a bug report is submitted.
func (t *TelegramNotifier) NotifyNewBug(bugID, title, os, appVersion, priority string) {
	emoji := priorityEmoji(priority)
	key := "bug:" + normalizeTelegramBurstKey(title) + ":" + strings.ToLower(strings.TrimSpace(os)) + ":" + strings.ToLower(strings.TrimSpace(appVersion))
	t.sendCollapsed(key, bugBurstWindow, func(suppressed int) string {
		return fmt.Sprintf(
			"🐛 <b>New Bug Report</b> %s\n\n"+
				"<b>Title:</b> %s\n"+
				"<b>Priority:</b> %s\n"+
				"<b>OS:</b> %s | <b>App:</b> v%s\n"+
				"<b>ID:</b> <code>%s</code>%s",
			emoji, escapeHTML(title), strings.ToUpper(priority),
			escapeHTML(os), escapeHTML(appVersion), bugID,
			suppressionSuffix(suppressed, bugBurstWindow),
		)
	})
}

// NotifyNewCrash sends notification when a crash report is submitted.
func (t *TelegramNotifier) NotifyNewCrash(crashID, errorMessage, severity, os, appVersion string) {
	emoji := severityEmoji(severity)
	// Truncate error message for readability
	errMsg := errorMessage
	if len(errMsg) > 200 {
		errMsg = errMsg[:197] + "..."
	}
	key := "crash:" + normalizeTelegramBurstKey(errorMessage) + ":" + strings.ToLower(strings.TrimSpace(os)) + ":" + strings.ToLower(strings.TrimSpace(appVersion)) + ":" + strings.ToLower(strings.TrimSpace(severity))
	t.sendCollapsed(key, crashBurstWindow, func(suppressed int) string {
		return fmt.Sprintf(
			"💥 <b>Crash Report</b> %s\n\n"+
				"<b>Severity:</b> %s\n"+
				"<b>Error:</b> %s\n"+
				"<b>OS:</b> %s | <b>App:</b> v%s\n"+
				"<b>ID:</b> <code>%s</code>%s",
			emoji, strings.ToUpper(severity),
			escapeHTML(errMsg), escapeHTML(os), escapeHTML(appVersion), crashID,
			suppressionSuffix(suppressed, crashBurstWindow),
		)
	})
}

// NotifyNewTicket sends notification when a support ticket is created.
func (t *TelegramNotifier) NotifyNewTicket(ticketID, subject, category, message string) {
	// Truncate message preview
	preview := message
	if len(preview) > 150 {
		preview = preview[:147] + "..."
	}
	msg := fmt.Sprintf(
		"🎫 <b>New Support Ticket</b>\n\n"+
			"<b>Subject:</b> %s\n"+
			"<b>Category:</b> %s\n"+
			"<b>Message:</b> %s\n"+
			"<b>ID:</b> <code>%s</code>",
		escapeHTML(subject), escapeHTML(category),
		escapeHTML(preview), ticketID,
	)
	t.dispatch(msg)
}

// NotifyNewRating sends notification when a user submits a rating.
func (t *TelegramNotifier) NotifyNewRating(deviceID string, rating int, review, appVersion string) {
	stars := strings.Repeat("⭐", rating)
	reviewText := "(no review)"
	if review != "" {
		if len(review) > 200 {
			review = review[:197] + "..."
		}
		reviewText = escapeHTML(review)
	}
	t.sendCollapsed("rating:"+strings.ToLower(strings.TrimSpace(appVersion)), ratingBurstWindow, func(suppressed int) string {
		return fmt.Sprintf(
			"⭐ <b>New Rating</b> %s\n\n"+
				"<b>Rating:</b> %s (%d/5)\n"+
				"<b>Review:</b> %s\n"+
				"<b>App:</b> v%s%s",
			stars, stars, rating, reviewText, escapeHTML(appVersion),
			suppressionSuffix(suppressed, ratingBurstWindow),
		)
	})
}

// NotifyPaymentCompleted sends notification when a payment is completed.
func (t *TelegramNotifier) NotifyPaymentCompleted(licenseKey, billingCycle, paymentMethod string, amountCents int64, currency string) {
	amount := fmt.Sprintf("%.2f %s", float64(amountCents)/100, strings.ToUpper(currency))
	msg := fmt.Sprintf(
		"💰 <b>Payment Completed</b>\n\n"+
			"<b>Amount:</b> %s\n"+
			"<b>Plan:</b> %s\n"+
			"<b>Method:</b> %s\n"+
			"<b>License:</b> <code>%s</code>",
		amount, escapeHTML(billingCycle),
		escapeHTML(paymentMethod), escapeHTML(maskKey(licenseKey)),
	)
	t.dispatch(msg)
}

// NotifyTicketEscalated sends notification when AI escalates a ticket.
func (t *TelegramNotifier) NotifyTicketEscalated(ticketID, subject, reason string) {
	msg := fmt.Sprintf(
		"🚨 <b>Ticket Escalated</b>\n\n"+
			"<b>Subject:</b> %s\n"+
			"<b>Reason:</b> %s\n"+
			"<b>ID:</b> <code>%s</code>\n\n"+
			"⚠️ Requires human attention",
		escapeHTML(subject), escapeHTML(reason), ticketID,
	)
	t.dispatch(msg)
}

// NotifyAIAutoResponse sends notification when AI auto-responds to a ticket.
func (t *TelegramNotifier) NotifyAIAutoResponse(ticketID, subject string, confidence string) {
	t.sendCollapsed("ai_auto_response:"+strings.ToLower(strings.TrimSpace(confidence)), aiAutoResponseWindow, func(suppressed int) string {
		return fmt.Sprintf(
			"🤖 <b>AI Auto-Response</b>\n\n"+
				"<b>Ticket:</b> %s\n"+
				"<b>Confidence:</b> %s\n"+
				"<b>ID:</b> <code>%s</code>%s",
			escapeHTML(subject), strings.ToUpper(confidence), ticketID,
			suppressionSuffix(suppressed, aiAutoResponseWindow),
		)
	})
}

// ==================== S1.2: Daily Digest ====================

// SendDailyDigest sends a morning summary of system stats.
func (t *TelegramNotifier) SendDailyDigest(stats DailyDigestStats) {
	if t == nil {
		return
	}

	date := t.currentTime().UTC().Format("2006-01-02")

	// Build top error codes string
	topErrors := "—"
	if len(stats.TopErrorCodes) > 0 {
		topErrors = strings.Join(stats.TopErrorCodes, ", ")
	}

	msg := fmt.Sprintf(
		"📊 <b>Svid Daily Digest — %s</b>\n\n"+
			"<b>Devices</b>\n"+
			"  Total: %d | New today: %d\n"+
			"  Active (7d): %d | Active (30d): %d\n\n"+
			"<b>Issues</b>\n"+
			"  Bugs open: %d | New today: %d\n"+
			"  Crashes today: %d\n"+
			"  Crash groups active: %d | New today: %d\n"+
			"  Tickets open: %d | New today: %d\n\n"+
			"<b>Downloads</b>\n"+
			"  Success rate: %d%%\n"+
			"  Total today: %d\n"+
			"  Download errors: %d\n"+
			"  Top errors: %s\n\n"+
			"<b>Ratings</b>\n"+
			"  Average: %.1f/5 | Total: %d\n\n"+
			"<b>Revenue</b>\n"+
			"  Today: $%.2f | Active licenses: %d%s",
		date,
		stats.TotalDevices, stats.NewDevicesToday,
		stats.ActiveDevices7d, stats.ActiveDevices30d,
		stats.OpenBugs, stats.NewBugsToday,
		stats.CrashesToday,
		stats.CrashGroupsActive, stats.CrashGroupsNewToday,
		stats.OpenTickets, stats.NewTicketsToday,
		stats.DownloadSuccessRate,
		stats.DownloadsToday,
		stats.DownloadErrorsToday,
		escapeHTML(topErrors),
		stats.RatingAverage, stats.TotalRatings,
		float64(stats.RevenueTodayCents)/100, stats.ActiveLicenses,
		telegramPremiumLicenseSuffix(stats.ActiveLicenses, stats.PremiumLicenses),
	)
	t.dispatchSync(msg)
}

// DailyDigestStats holds aggregated stats for the daily digest.
type DailyDigestStats struct {
	TotalDevices        int64
	NewDevicesToday     int64
	ActiveDevices7d     int64
	ActiveDevices30d    int64
	OpenBugs            int64
	NewBugsToday        int64
	CrashesToday        int64
	OpenTickets         int64
	NewTicketsToday     int64
	DownloadSuccessRate int
	DownloadsToday      int64
	RatingAverage       float64
	TotalRatings        int64
	RevenueTodayCents   int64
	ActiveLicenses      int64
	PremiumLicenses     int64
	// Phase 4: Enhanced monitoring
	CrashGroupsActive   int64
	CrashGroupsNewToday int64
	DownloadErrorsToday int64
	TopErrorCodes       []string // Top 3 error codes from download_errors
}

// ==================== Helpers ====================

func escapeHTML(s string) string {
	s = strings.ReplaceAll(s, "&", "&amp;")
	s = strings.ReplaceAll(s, "<", "&lt;")
	s = strings.ReplaceAll(s, ">", "&gt;")
	return s
}

func priorityEmoji(priority string) string {
	switch strings.ToLower(priority) {
	case "critical":
		return "🔴"
	case "high":
		return "🟠"
	case "medium":
		return "🟡"
	default:
		return "🟢"
	}
}

func severityEmoji(severity string) string {
	switch strings.ToLower(severity) {
	case "critical":
		return "🔴"
	case "high":
		return "🟠"
	case "medium":
		return "🟡"
	default:
		return "🟢"
	}
}

func maskKey(key string) string {
	if len(key) < 15 {
		return key
	}
	return key[:10] + "****" + key[len(key)-4:]
}

func normalizeTelegramBurstKey(value string) string {
	normalized := strings.TrimSpace(value)
	if normalized == "" {
		return "unknown"
	}
	if idx := strings.IndexByte(normalized, '\n'); idx >= 0 {
		normalized = normalized[:idx]
	}
	normalized = telegramFileURIRegex.ReplaceAllString(normalized, "file:///<path>")
	normalized = telegramWindowsPathRegex.ReplaceAllString(normalized, "<path>")
	normalized = telegramUnixPathRegex.ReplaceAllString(normalized, "${1}<path>")
	normalized = strings.ToLower(strings.Join(strings.Fields(normalized), " "))
	if len(normalized) > 160 {
		normalized = normalized[:160]
	}
	return normalized
}

func suppressionSuffix(suppressed int, window time.Duration) string {
	if suppressed <= 0 {
		return ""
	}
	return fmt.Sprintf("\n\n<i>%d similar event(s) suppressed in the last %s</i>", suppressed, formatSuppressionWindow(window))
}

func formatSuppressionWindow(window time.Duration) string {
	switch {
	case window%time.Hour == 0:
		return fmt.Sprintf("%dh", int(window/time.Hour))
	case window%time.Minute == 0:
		return fmt.Sprintf("%dm", int(window/time.Minute))
	default:
		return window.String()
	}
}

func telegramPremiumLicenseSuffix(activeLicenses, premiumLicenses int64) string {
	if premiumLicenses <= 0 || premiumLicenses == activeLicenses {
		return ""
	}
	return fmt.Sprintf(" | Premium total: %d", premiumLicenses)
}
