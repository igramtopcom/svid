package service

import (
	"strings"
	"testing"
)

func TestFormatTicketDiagnosticLog(t *testing.T) {
	t.Run("empty log is omitted", func(t *testing.T) {
		if got := formatTicketDiagnosticLog(" \n\t "); got != "" {
			t.Fatalf("expected empty diagnostic message, got %q", got)
		}
	})

	t.Run("non-empty log gets support-visible header", func(t *testing.T) {
		got := formatTicketDiagnosticLog("line 1\nline 2")
		if !strings.HasPrefix(got, "Diagnostic log tail:\n\n") {
			t.Fatalf("expected diagnostic header, got %q", got)
		}
		if !strings.Contains(got, "line 1\nline 2") {
			t.Fatalf("expected log content, got %q", got)
		}
	})

	t.Run("long log keeps the newest tail", func(t *testing.T) {
		raw := "OLD" + strings.Repeat("a", maxTicketDiagnosticLogChars+10) + "END"
		got := formatTicketDiagnosticLog(raw)
		if strings.Contains(got, "OLD") {
			t.Fatalf("expected oldest marker to be truncated")
		}
		if !strings.HasSuffix(got, "END") {
			t.Fatalf("expected newest tail to be preserved, got suffix %q", got[len(got)-10:])
		}
	})
}
