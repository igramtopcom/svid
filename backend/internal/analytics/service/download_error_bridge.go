package service

import (
	"encoding/json"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/analytics/model"
)

const downloadErrorDedupWindow = 2 * time.Minute

var validDownloadErrorPhases = map[string]struct{}{
	"extraction":   {},
	"download":     {},
	"conversion":   {},
	"merge":        {},
	"post_process": {},
	"unknown":      {},
}

var downloadErrorPhaseByCode = map[string]string{
	"videoNotFound":        "extraction",
	"geoRestricted":        "extraction",
	"loginRequired":        "extraction",
	"ageRestricted":        "extraction",
	"formatUnavailable":    "extraction",
	"rateLimited":          "extraction",
	"accessDenied":         "extraction",
	"contentUnavailable":   "extraction",
	"ytdlpBinaryMissing":   "extraction",
	"binaryNotAvailable":   "extraction",
	"jsRuntimeUnavailable": "extraction",
	"cookieDbLocked":       "extraction",
	"circuitBreakerOpen":   "download",
	"networkOffline":       "download",
	"networkTimeout":       "download",
	"serverError":          "download",
	"connectionRefused":    "download",
	"sslError":             "download",
	"ffmpegError":          "conversion",
	"diskFull":             "post_process",
	"permissionDenied":     "post_process",
	"pathNotFound":         "post_process",
	"unknown":              "unknown",
}

var downloadErrorSSLPatterns = []string{
	"certificate_verify_failed",
	"handshakeexception",
	"bad certificate",
	"tlsexception",
	"ssl error",
	"certificate has expired",
	"unable to get local issuer certificate",
}

var downloadErrorNetworkOfflinePatterns = []string{
	"socketexception",
	"networkexception",
	"no internet",
	"network is unreachable",
	"no address associated",
	"failed host lookup",
	"network error",
}

var downloadErrorTimeoutPatterns = []string{
	"timeoutexception",
	"timed out",
	"timeout",
	"connection timed out",
}

var downloadErrorConnectionRefusedPatterns = []string{
	"connection refused",
	"connection reset",
	"connection closed",
	"dns resolution",
	"dns lookup",
	"getaddrinfo",
	"econnrefused",
	"econnreset",
}

var downloadErrorRateLimitedPatterns = []string{
	"too many requests",
	"http error 429",
	"http_429",
	"status 429",
	"rate limit",
	"rate-limit",
	"throttl",
	"please wait a few minutes",
}

var downloadErrorLoginRequiredPatterns = []string{
	"login required",
	"sign in",
	"authentication",
	"private video",
	"members-only",
	"cookies are needed",
	"use cookies",
	"pass cookies",
	"premium",
	"requires payment",
	"requires a subscription",
	"subscriber only",
	"checkpoint required",
}

var downloadErrorGeoRestrictedPatterns = []string{
	"geo restrict",
	"geo-restrict",
	"not available in your country",
	"geographically restricted",
	"blocked in your",
}

var downloadErrorAgeRestrictedPatterns = []string{
	"age restrict",
	"age-restrict",
	"age gate",
	"age verification",
	"confirm your age",
}

var downloadErrorFormatUnavailablePatterns = []string{
	"requested format",
	"format not available",
	"format is not available",
	"no video formats found",
}

var downloadErrorContentUnavailablePatterns = []string{
	"copyright",
	"dmca",
	"terms of service",
	"community guidelines",
	"content is not available",
	"removed by the uploader",
	"taken down",
	"is unavailable",
	"has been removed",
	"drm protected",
	"drm",
	"terminated",
}

var downloadErrorVideoNotFoundPatterns = []string{
	"video unavailable",
	"not a valid url",
	"is not a valid url",
	"video not found",
	"page not found",
	"this video has been removed",
	"this video is no longer available",
	"unable to extract",
	"unsupported url",
	"content not found",
}

var downloadErrorYTDLPBinaryMissingPatterns = []string{
	"yt-dlp not found",
	"yt-dlp binary",
	"no such file or directory: yt-dlp",
	"cannot find yt-dlp",
}

var downloadErrorJSRuntimePatterns = []string{
	"n challenge solving failed",
	"signature solving failed",
	"external javascript runtime",
	"no usable javascript runtime",
	"could not find any usable javascript",
	"jsruntimeunavailable",
}

var downloadErrorCookieDbLockedPatterns = []string{
	"could not copy chrome cookie database",
	"could not copy edge cookie database",
	"could not copy brave cookie database",
	"could not copy vivaldi cookie database",
	"could not copy opera cookie database",
	"could not copy chromium cookie database",
	"could not copy firefox cookie database",
	"could not copy safari cookie database",
	"could not copy cookie database",
	"unsupported browser",
	"unable to load cookies from",
	"failed to decrypt with dpapi",
	"failed to decrypt cookie",
	"failed to decrypt cookies",
	"cryptunprotectdata",
	"cookies.sqlite",
	"cookie database",
}

var downloadErrorBinaryNotAvailablePatterns = []string{
	"exec format error",
	"bad cpu type",
	"cannot execute binary file",
}

var downloadErrorFFmpegErrorPatterns = []string{
	"postprocessor",
	"postprocessing",
	"ffmpeg not found",
	"ffmpeg error",
	"ffmpeg: error",
	"ffmpeg or avconv",
	"merging formats",
	"conversion failed",
}

var downloadErrorDiskFullPatterns = []string{
	"no space left",
	"disk full",
	"enospc",
	"not enough disk space",
	"not enough space",
}

var downloadErrorPermissionDeniedPatterns = []string{
	"permission denied",
	"eacces",
	"access denied",
	"operation not permitted",
}

var downloadErrorPathNotFoundPatterns = []string{
	"no such file or directory",
	"path not found",
	"directory does not exist",
	"directory not found",
}

type downloadErrorDiagnostic struct {
	Code      string
	Phase     string
	Signature string
}

func structuredDownloadErrorFromEvent(deviceID uuid.UUID, os, appVersion string, event model.AnalyticsEvent) (*model.DownloadError, bool) {
	if event.EventType != "download_error" || strings.TrimSpace(event.EventData) == "" {
		return nil, false
	}

	var payload map[string]interface{}
	if err := json.Unmarshal([]byte(event.EventData), &payload); err != nil {
		return nil, false
	}

	platform := nonEmptyString(
		stringValue(payload["platform"]),
	)
	errorMessage := nonEmptyString(
		stringValue(payload["error_message"]),
		stringValue(payload["error"]),
	)
	if platform == "" || errorMessage == "" {
		return nil, false
	}

	errorCode := nonEmptyString(
		stringValue(payload["error_code"]),
		classifyDownloadErrorMessage(errorMessage),
	)
	errorPhase := normalizeDownloadErrorPhase(
		stringValue(payload["error_phase"]),
		errorCode,
	)
	diagnostic := diagnoseDownloadError(errorCode, errorPhase, errorMessage, event.EventData)

	return &model.DownloadError{
		DeviceID:             deviceID,
		URL:                  stringValue(payload["url"]),
		Platform:             platform,
		ErrorCode:            errorCode,
		ErrorPhase:           errorPhase,
		ErrorMessage:         errorMessage,
		DiagnosticErrorCode:  diagnostic.Code,
		DiagnosticErrorPhase: diagnostic.Phase,
		DiagnosticSignature:  diagnostic.Signature,
		AppVersion:           appVersion,
		OS:                   os,
		Metadata:             event.EventData,
	}, true
}

func enrichDownloadErrorDiagnostics(dlErr *model.DownloadError) {
	if dlErr == nil || strings.TrimSpace(dlErr.DiagnosticErrorCode) != "" {
		return
	}
	diagnostic := diagnoseDownloadError(dlErr.ErrorCode, dlErr.ErrorPhase, dlErr.ErrorMessage, dlErr.Metadata)
	dlErr.DiagnosticErrorCode = diagnostic.Code
	dlErr.DiagnosticErrorPhase = diagnostic.Phase
	dlErr.DiagnosticSignature = diagnostic.Signature
}

func diagnoseDownloadError(rawCode, rawPhase, errorMessage, metadata string) downloadErrorDiagnostic {
	rawCode = strings.TrimSpace(rawCode)
	rawPhase = strings.TrimSpace(rawPhase)

	var meta map[string]interface{}
	if strings.TrimSpace(metadata) != "" {
		_ = json.Unmarshal([]byte(metadata), &meta)
	}

	searchText := strings.ToLower(strings.Join([]string{
		errorMessage,
		stringValue(meta["error_detail_excerpt"]),
		stringValue(meta["error"]),
		stringValue(meta["error_message"]),
		stringValue(meta["message"]),
		stringValue(meta["stderr"]),
		stringValue(meta["raw_error"]),
	}, "\n"))

	switch {
	case matchesCircuitBreakerCooldown(searchText):
		return diagnosticWithPhase("circuitBreakerOpen", "download", "circuit_breaker_cooldown")
	case boolValue(meta["looks_like_cookie_db_locked"]) || containsAny(searchText, downloadErrorCookieDbLockedPatterns):
		return diagnosticWithPhase("cookieDbLocked", "extraction", "cookie_db_locked")
	case boolValue(meta["looks_like_js_runtime_issue"]) || containsAny(searchText, downloadErrorJSRuntimePatterns):
		return diagnosticWithPhase("jsRuntimeUnavailable", "extraction", "js_runtime_unavailable")
	case matchesFragmentTruncation(searchText):
		return diagnosticWithPhase("networkTimeout", "download", "fragment_truncation")
	case matchesContainerMismatch(searchText):
		return diagnosticWithPhase("formatUnavailable", "conversion", "container_mismatch")
	case boolValue(meta["looks_like_format_unavailable"]) || containsAny(searchText, downloadErrorFormatUnavailablePatterns):
		return diagnosticWithPhase("formatUnavailable", "extraction", "format_unavailable")
	case matchesMergeFailure(searchText):
		return diagnosticWithPhase("ffmpegError", "merge", "merge_failed")
	case containsAny(searchText, downloadErrorFFmpegErrorPatterns):
		return diagnosticWithPhase("ffmpegError", "conversion", "ffmpeg_or_postprocess")
	case containsAny(searchText, downloadErrorGeoRestrictedPatterns) || matchesUnavailableContent(searchText):
		return diagnosticWithPhase("contentUnavailable", "extraction", "geo_or_unavailable")
	}

	classifiedCode := classifyDownloadErrorMessage(errorMessage)
	if classifiedCode != "" && classifiedCode != "unknown" {
		return diagnosticWithPhase(classifiedCode, normalizeDownloadErrorPhase(rawPhase, classifiedCode), "backend_message_classifier")
	}

	if rawCode != "" {
		return diagnosticWithPhase(rawCode, normalizeDownloadErrorPhase(rawPhase, rawCode), "raw_error_code")
	}
	return diagnosticWithPhase("unknown", normalizeDownloadErrorPhase(rawPhase, "unknown"), "unclassified")
}

func diagnosticWithPhase(code, phase, signature string) downloadErrorDiagnostic {
	return downloadErrorDiagnostic{
		Code:      code,
		Phase:     normalizeDownloadErrorPhase(phase, code),
		Signature: signature,
	}
}

func classifyDownloadErrorMessage(errorMessage string) string {
	if strings.HasPrefix(errorMessage, "HTTP_403_FORBIDDEN:") {
		return "accessDenied"
	}
	if strings.HasPrefix(errorMessage, "HTTP_410_GONE:") {
		return "videoNotFound"
	}
	if strings.HasPrefix(errorMessage, "HTTP_429_TOO_MANY_REQUESTS:") {
		return "rateLimited"
	}
	if strings.HasPrefix(errorMessage, "HTTP_404_NOT_FOUND:") {
		return "videoNotFound"
	}

	lower := strings.ToLower(errorMessage)

	switch {
	case containsAny(lower, downloadErrorSSLPatterns):
		return "sslError"
	case containsAny(lower, downloadErrorNetworkOfflinePatterns):
		return "networkOffline"
	case containsAny(lower, downloadErrorTimeoutPatterns):
		return "networkTimeout"
	case containsAny(lower, downloadErrorConnectionRefusedPatterns):
		return "connectionRefused"
	case matchesServerError(lower):
		return "serverError"
	case containsAny(lower, downloadErrorRateLimitedPatterns):
		return "rateLimited"
	case matchesAccessDenied(lower):
		return "accessDenied"
	case containsAny(lower, downloadErrorLoginRequiredPatterns):
		return "loginRequired"
	case containsAny(lower, downloadErrorGeoRestrictedPatterns):
		return "geoRestricted"
	case containsAny(lower, downloadErrorContentUnavailablePatterns):
		return "contentUnavailable"
	case containsAny(lower, downloadErrorAgeRestrictedPatterns):
		return "ageRestricted"
	case containsAny(lower, downloadErrorFormatUnavailablePatterns):
		return "formatUnavailable"
	case containsAny(lower, downloadErrorVideoNotFoundPatterns):
		return "videoNotFound"
	case containsAny(lower, downloadErrorYTDLPBinaryMissingPatterns):
		return "ytdlpBinaryMissing"
	case containsAny(lower, downloadErrorBinaryNotAvailablePatterns):
		return "binaryNotAvailable"
	case containsAny(lower, downloadErrorFFmpegErrorPatterns):
		return "ffmpegError"
	case containsAny(lower, downloadErrorDiskFullPatterns):
		return "diskFull"
	case containsAny(lower, downloadErrorPermissionDeniedPatterns):
		return "permissionDenied"
	case containsAny(lower, downloadErrorPathNotFoundPatterns):
		return "pathNotFound"
	default:
		return "unknown"
	}
}

func normalizeDownloadErrorPhase(rawPhase, errorCode string) string {
	normalized := strings.TrimSpace(rawPhase)
	if _, ok := validDownloadErrorPhases[normalized]; ok {
		return normalized
	}
	if phase, ok := downloadErrorPhaseByCode[errorCode]; ok {
		return phase
	}
	return "unknown"
}

func matchesFragmentTruncation(lower string) bool {
	hasRetryTail := strings.Contains(lower, "giving up after") && strings.Contains(lower, "retries")
	hasPartialRead := strings.Contains(lower, "read ") && strings.Contains(lower, "bytes")
	return hasRetryTail && (hasPartialRead || strings.Contains(lower, "fragment"))
}

func matchesCircuitBreakerCooldown(lower string) bool {
	hasBreaker := strings.Contains(lower, "circuitbreakeropen") ||
		strings.Contains(lower, "circuit breaker open") ||
		strings.Contains(lower, "breaker is open")
	return hasBreaker || (strings.Contains(lower, "circuit") && strings.Contains(lower, "cooldown"))
}

func matchesContainerMismatch(lower string) bool {
	if strings.Contains(lower, "try mkv") || strings.Contains(lower, "try .mkv") {
		return true
	}
	return strings.Contains(lower, "no audio") && (strings.Contains(lower, "webm") || strings.Contains(lower, "mkv"))
}

func matchesMergeFailure(lower string) bool {
	hasMerge := strings.Contains(lower, "merge") || strings.Contains(lower, "merging")
	hasFailure := strings.Contains(lower, "fail") || strings.Contains(lower, "error") || strings.Contains(lower, "unable")
	return hasMerge && hasFailure
}

func matchesUnavailableContent(lower string) bool {
	if strings.Contains(lower, "live event has ended") || strings.Contains(lower, "this live event has ended") {
		return true
	}
	if strings.Contains(lower, "not available") || strings.Contains(lower, "unavailable") {
		return strings.Contains(lower, "video") ||
			strings.Contains(lower, "content") ||
			strings.Contains(lower, "country") ||
			strings.Contains(lower, "region") ||
			strings.Contains(lower, "this ")
	}
	return false
}

func containsAny(lower string, patterns []string) bool {
	for _, pattern := range patterns {
		if strings.Contains(lower, pattern) {
			return true
		}
	}
	return false
}

func matchesServerError(lower string) bool {
	if strings.Contains(lower, "http error 500") || strings.Contains(lower, "status 500") || strings.Contains(lower, "error 500") {
		return true
	}
	if strings.Contains(lower, "502") || strings.Contains(lower, "503") || strings.Contains(lower, "504") {
		if strings.Contains(lower, "http") || strings.Contains(lower, "server") || strings.Contains(lower, "status") || strings.Contains(lower, "error") {
			return true
		}
	}
	if strings.Contains(lower, "internal server error") || strings.Contains(lower, "bad gateway") || strings.Contains(lower, "service unavailable") {
		return true
	}
	if strings.Contains(lower, "conflicting range") || strings.Contains(lower, "downloaded file is empty") || strings.Contains(lower, "requested range not satisfiable") {
		return true
	}
	return false
}

func matchesAccessDenied(lower string) bool {
	if strings.Contains(lower, "403") {
		if strings.Contains(lower, "http") || strings.Contains(lower, "forbidden") || strings.Contains(lower, "status") || strings.Contains(lower, "error") {
			return true
		}
	}
	return strings.Contains(lower, "http") && strings.Contains(lower, "forbidden")
}

func boolValue(value interface{}) bool {
	switch v := value.(type) {
	case bool:
		return v
	case string:
		return strings.EqualFold(strings.TrimSpace(v), "true")
	default:
		return false
	}
}

func stringValue(value interface{}) string {
	switch v := value.(type) {
	case string:
		return strings.TrimSpace(v)
	default:
		return ""
	}
}

func nonEmptyString(values ...string) string {
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			return trimmed
		}
	}
	return ""
}
