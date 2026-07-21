package service

import (
	"crypto/sha256"
	"fmt"
	"regexp"
	"strings"
)

var (
	addrRegex          = regexp.MustCompile(`0x[0-9a-fA-F]+`)
	lineNumRegex       = regexp.MustCompile(`:\d+(?::\d+)?([)\s+]|$)`)
	legacyLineNumRegex = regexp.MustCompile(`:\d+(\s|$|\+)`)
	goroutineRegex     = regexp.MustCompile(`goroutine \d+`)
	timestampRegex     = regexp.MustCompile(`\d{4}[-/]\d{2}[-/]\d{2}[T ]\d{2}:\d{2}:\d{2}`)
	threadRegex        = regexp.MustCompile(`\[thread \d+\]`)
	fileURIRegex       = regexp.MustCompile(`(?i)file:///[^\s"'()]+`)
	windowsPathRegex   = regexp.MustCompile(`(?i)\b[a-z]:[\\/][^\s"'()]+`)
	unixPathRegex      = regexp.MustCompile(`(^|[\s"'(])(/(?:[^/\s"'()]+/)+[^/\s"'()]+)`)
	uuidRegex          = regexp.MustCompile(`(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b`)
)

// canonicalizeCrashText removes volatile path/id fragments that commonly make
// equivalent runtime errors look distinct in production.
func canonicalizeCrashText(text string) string {
	text = fileURIRegex.ReplaceAllString(text, "file:///<path>")
	text = windowsPathRegex.ReplaceAllString(text, "<path>")
	text = unixPathRegex.ReplaceAllString(text, "${1}<path>")
	text = uuidRegex.ReplaceAllString(text, "<id>")
	text = addrRegex.ReplaceAllString(text, "0x...")
	return text
}

func normalizeErrorMessage(errorMessage string) string {
	msg := strings.TrimSpace(errorMessage)
	if msg == "" {
		return ""
	}
	if idx := strings.IndexByte(msg, '\n'); idx >= 0 {
		msg = msg[:idx]
	}
	msg = canonicalizeCrashText(msg)
	msg = strings.ToLower(strings.Join(strings.Fields(msg), " "))
	return msg
}

// normalizeStackTrace strips volatile elements from a stack trace to produce
// a stable string suitable for fingerprinting. Removes:
// - Memory addresses (0x7fff...)
// - Line numbers after colons (file.go:123 → file.go)
// - Timestamps and thread IDs
// - Goroutine IDs
// Keeps: function names, file paths, error types.
func normalizeStackTrace(stackTrace string) string {
	lines := strings.Split(stackTrace, "\n")
	var normalized []string

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		// Strip volatile parts
		line = canonicalizeCrashText(line)
		line = lineNumRegex.ReplaceAllString(line, ":N$1")
		line = goroutineRegex.ReplaceAllString(line, "goroutine N")
		line = timestampRegex.ReplaceAllString(line, "TIMESTAMP")
		line = threadRegex.ReplaceAllString(line, "[thread N]")

		// Collapse whitespace
		line = strings.Join(strings.Fields(line), " ")

		if line != "" {
			normalized = append(normalized, line)
		}
	}

	if len(normalized) > 8 {
		normalized = normalized[:8]
	}

	return strings.Join(normalized, "\n")
}

func normalizeLegacyStackTrace(stackTrace string) string {
	lines := strings.Split(stackTrace, "\n")
	var normalized []string

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		line = addrRegex.ReplaceAllString(line, "0x...")
		line = legacyLineNumRegex.ReplaceAllString(line, ":N ")
		line = goroutineRegex.ReplaceAllString(line, "goroutine N")
		line = timestampRegex.ReplaceAllString(line, "TIMESTAMP")
		line = threadRegex.ReplaceAllString(line, "[thread N]")
		line = strings.Join(strings.Fields(line), " ")

		if line != "" {
			normalized = append(normalized, line)
		}
	}

	return strings.Join(normalized, "\n")
}

// ComputeLegacyFingerprint preserves the original stack-only fingerprint for
// backward-compatible lookup against already-grouped production crashes.
func ComputeLegacyFingerprint(stackTrace string) string {
	normalized := normalizeLegacyStackTrace(stackTrace)
	hash := sha256.Sum256([]byte(normalized))
	return fmt.Sprintf("%x", hash)
}

// ComputeFingerprint produces a SHA-256 hex digest from normalized crash
// signal. It prefers canonicalized error_message plus a trimmed stack
// signature, which reduces over-splitting caused by volatile file paths,
// line numbers, and async/frame noise.
func ComputeFingerprint(errorMessage, stackTrace string) string {
	var parts []string

	if msg := normalizeErrorMessage(errorMessage); msg != "" {
		parts = append(parts, "msg:"+msg)
	}

	normalized := normalizeStackTrace(stackTrace)
	if normalized != "" {
		parts = append(parts, "stack:"+normalized)
	}

	if len(parts) == 0 {
		parts = append(parts, "unknown-crash")
	}

	hash := sha256.Sum256([]byte(strings.Join(parts, "\n")))
	return fmt.Sprintf("%x", hash)
}

func NormalizeCrashTitle(title string) string {
	return normalizeErrorMessage(title)
}

// ExtractTitle extracts a short, meaningful title from the error message
// or the first line of the stack trace.
func ExtractTitle(errorMessage, stackTrace string) string {
	// Prefer the error message if available
	if errorMessage != "" {
		title := errorMessage
		// Truncate at first newline
		if idx := strings.IndexByte(title, '\n'); idx > 0 {
			title = title[:idx]
		}
		// Cap length
		if len(title) > 200 {
			title = title[:197] + "..."
		}
		return title
	}

	// Fall back to first non-empty line of stack trace
	for _, line := range strings.Split(stackTrace, "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			if len(line) > 200 {
				line = line[:197] + "..."
			}
			return line
		}
	}

	return "Unknown crash"
}
