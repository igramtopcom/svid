package dto

import (
	"testing"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/analytics/model"
)

func TestDownloadErrorToResponseUsesStoredDiagnosticOnly(t *testing.T) {
	err := &model.DownloadError{
		ID:           uuid.New(),
		DeviceID:     uuid.New(),
		Platform:     "youtube",
		ErrorCode:    "unknown",
		ErrorPhase:   "unknown",
		ErrorMessage: "Could not copy Chrome cookie database",
	}

	resp := DownloadErrorToResponse(err)

	if resp.DiagnosticErrorCode != "" {
		t.Fatalf("expected historical row without stored diagnostic to stay empty, got %q", resp.DiagnosticErrorCode)
	}
}

func TestDownloadErrorToResponseIncludesStoredDiagnostic(t *testing.T) {
	err := &model.DownloadError{
		ID:                   uuid.New(),
		DeviceID:             uuid.New(),
		Platform:             "youtube",
		ErrorCode:            "unknown",
		ErrorPhase:           "unknown",
		ErrorMessage:         "Could not copy Chrome cookie database",
		DiagnosticErrorCode:  "cookieDbLocked",
		DiagnosticErrorPhase: "extraction",
		DiagnosticSignature:  "cookie_db_locked",
	}

	resp := DownloadErrorToResponse(err)

	if resp.DiagnosticErrorCode != "cookieDbLocked" {
		t.Fatalf("expected stored diagnostic code to be preserved, got %q", resp.DiagnosticErrorCode)
	}
	if resp.DiagnosticSignature != "cookie_db_locked" {
		t.Fatalf("expected stored diagnostic signature to be preserved, got %q", resp.DiagnosticSignature)
	}
}
