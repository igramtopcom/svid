package service

import (
	"testing"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/analytics/model"
)

func TestNormalizeEventType(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		want      string
		wantValid bool
	}{
		{
			name:      "keeps canonical event type",
			input:     "download_complete",
			want:      "download_complete",
			wantValid: true,
		},
		{
			name:      "trims and lowercases",
			input:     "  VIDEO_PLAY  ",
			want:      "video_play",
			wantValid: true,
		},
		{
			name:      "maps completed alias",
			input:     "download_completed",
			want:      "download_complete",
			wantValid: true,
		},
		{
			name:      "maps failed alias",
			input:     "download_failed",
			want:      "download_error",
			wantValid: true,
		},
		{
			name:      "maps legacy premium alias",
			input:     "premium_checkout_cancelled",
			want:      "premium_cancelled",
			wantValid: true,
		},
		{
			name:      "rejects blank event type",
			input:     "   ",
			want:      "",
			wantValid: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := NormalizeEventType(tc.input)
			if got != tc.want {
				t.Fatalf("expected normalized event type %q, got %q", tc.want, got)
			}
			if ok != tc.wantValid {
				t.Fatalf("expected valid=%v, got %v", tc.wantValid, ok)
			}
		})
	}
}

func TestIsKnownEventType(t *testing.T) {
	if !IsKnownEventType("download_complete") {
		t.Fatal("expected download_complete to remain in the known event registry")
	}
	if !IsKnownEventType("license_verify") {
		t.Fatal("expected license_verify to be accepted as production telemetry")
	}
	for _, eventType := range []string{
		"update_download_verified",
		"update_download_failed",
		"update_install_started",
		"update_install_handoff_started",
		"update_install_completed",
		"update_install_not_applied",
		"update_install_failed",
	} {
		if !IsKnownEventType(eventType) {
			t.Fatalf("expected %s to be accepted as production telemetry", eventType)
		}
	}
	if IsKnownEventType("download_completed") {
		t.Fatal("expected legacy alias to be normalized before registry checks")
	}
}

func TestStructuredDownloadErrorFromEvent(t *testing.T) {
	event := model.AnalyticsEvent{
		EventType: "download_error",
		EventData: `{"platform":"youtube","error":"Connection timed out while downloading","url":"https://example.com/watch?v=abc"}`,
	}

	dlErr, ok := structuredDownloadErrorFromEvent(uuid.New(), "windows", "1.6.2", event)
	if !ok {
		t.Fatal("expected analytics download_error event to bridge into structured telemetry")
	}
	if dlErr.Platform != "youtube" {
		t.Fatalf("expected platform youtube, got %q", dlErr.Platform)
	}
	if dlErr.ErrorCode != "networkTimeout" {
		t.Fatalf("expected error code networkTimeout, got %q", dlErr.ErrorCode)
	}
	if dlErr.ErrorPhase != "download" {
		t.Fatalf("expected error phase download, got %q", dlErr.ErrorPhase)
	}
	if dlErr.URL != "https://example.com/watch?v=abc" {
		t.Fatalf("expected URL to be preserved, got %q", dlErr.URL)
	}
	if dlErr.Metadata != event.EventData {
		t.Fatalf("expected raw event data to be preserved as metadata")
	}
}

func TestStructuredDownloadErrorFromEventPrefersExplicitFields(t *testing.T) {
	event := model.AnalyticsEvent{
		EventType: "download_error",
		EventData: `{"platform":"tiktok","error":"Could not copy Chrome cookie database. Please close Chrome.","error_code":"unknown","error_phase":"unknown"}`,
	}

	dlErr, ok := structuredDownloadErrorFromEvent(uuid.New(), "macos", "1.3.5", event)
	if !ok {
		t.Fatal("expected explicit structured analytics payload to bridge")
	}
	if dlErr.ErrorCode != "unknown" {
		t.Fatalf("expected explicit raw error code to win, got %q", dlErr.ErrorCode)
	}
	if dlErr.ErrorPhase != "unknown" {
		t.Fatalf("expected explicit raw phase to win, got %q", dlErr.ErrorPhase)
	}
	if dlErr.DiagnosticErrorCode != "cookieDbLocked" {
		t.Fatalf("expected diagnostic code cookieDbLocked, got %q", dlErr.DiagnosticErrorCode)
	}
	if dlErr.DiagnosticSignature != "cookie_db_locked" {
		t.Fatalf("expected diagnostic signature cookie_db_locked, got %q", dlErr.DiagnosticSignature)
	}
}

func TestStructuredDownloadErrorFromEventRejectsIncompletePayload(t *testing.T) {
	tests := []model.AnalyticsEvent{
		{EventType: "download_complete", EventData: `{"platform":"youtube","error":"timeout"}`},
		{EventType: "download_error", EventData: `{"platform":"youtube"}`},
		{EventType: "download_error", EventData: `{"error":"timeout"}`},
		{EventType: "download_error", EventData: `{invalid json`},
	}

	for _, event := range tests {
		if dlErr, ok := structuredDownloadErrorFromEvent(uuid.New(), "windows", "1.6.2", event); ok || dlErr != nil {
			t.Fatalf("expected event %+v to be ignored", event)
		}
	}
}

func TestClassifyDownloadErrorMessage(t *testing.T) {
	tests := []struct {
		name    string
		message string
		want    string
	}{
		{name: "http 429", message: "HTTP_429_TOO_MANY_REQUESTS: slow down", want: "rateLimited"},
		{name: "ssl", message: "HandshakeException: bad certificate", want: "sslError"},
		{name: "ffmpeg", message: "Postprocessing: ffmpeg error while merging formats", want: "ffmpegError"},
		{name: "unknown", message: "unexpected boom", want: "unknown"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := classifyDownloadErrorMessage(tc.message); got != tc.want {
				t.Fatalf("classifyDownloadErrorMessage(%q) = %q, want %q", tc.message, got, tc.want)
			}
		})
	}
}

func TestDiagnoseDownloadErrorKeepsRawCodeTelemetryOnly(t *testing.T) {
	diag := diagnoseDownloadError(
		"unknown",
		"unknown",
		"Could not copy Chrome cookie database. Please close Chrome.",
		"",
	)

	if diag.Code != "cookieDbLocked" {
		t.Fatalf("expected diagnostic code cookieDbLocked, got %q", diag.Code)
	}
	if diag.Phase != "extraction" {
		t.Fatalf("expected diagnostic phase extraction, got %q", diag.Phase)
	}
	if diag.Signature != "cookie_db_locked" {
		t.Fatalf("expected diagnostic signature cookie_db_locked, got %q", diag.Signature)
	}
}

func TestDiagnoseDownloadErrorSignatures(t *testing.T) {
	tests := []struct {
		name      string
		message   string
		metadata  string
		wantCode  string
		wantPhase string
		wantSig   string
	}{
		{
			name:      "fragment truncation",
			message:   "read 1048576 bytes, giving up after 3 retries",
			wantCode:  "networkTimeout",
			wantPhase: "download",
			wantSig:   "fragment_truncation",
		},
		{
			name:      "country unavailable",
			message:   "This video is not available in your country",
			wantCode:  "contentUnavailable",
			wantPhase: "extraction",
			wantSig:   "geo_or_unavailable",
		},
		{
			name:      "container mismatch",
			message:   "No audio stream found for WebM output, try MKV",
			wantCode:  "formatUnavailable",
			wantPhase: "conversion",
			wantSig:   "container_mismatch",
		},
		{
			name:      "circuit breaker cooldown",
			message:   "circuitBreakerOpen: extractor cooldown 34s",
			wantCode:  "circuitBreakerOpen",
			wantPhase: "download",
			wantSig:   "circuit_breaker_cooldown",
		},
		{
			name:      "ffmpeg missing",
			message:   "ffmpeg not found while postprocessing",
			wantCode:  "ffmpegError",
			wantPhase: "conversion",
			wantSig:   "ffmpeg_or_postprocess",
		},
		{
			name:      "metadata flag",
			message:   "Download failed",
			metadata:  `{"looks_like_format_unavailable":true}`,
			wantCode:  "formatUnavailable",
			wantPhase: "extraction",
			wantSig:   "format_unavailable",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			diag := diagnoseDownloadError("unknown", "unknown", tc.message, tc.metadata)
			if diag.Code != tc.wantCode {
				t.Fatalf("expected diagnostic code %q, got %q", tc.wantCode, diag.Code)
			}
			if diag.Phase != tc.wantPhase {
				t.Fatalf("expected diagnostic phase %q, got %q", tc.wantPhase, diag.Phase)
			}
			if diag.Signature != tc.wantSig {
				t.Fatalf("expected diagnostic signature %q, got %q", tc.wantSig, diag.Signature)
			}
		})
	}
}
