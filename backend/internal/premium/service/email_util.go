package service

import "strings"

// NormalizeEmail produces the canonical lower-cased + trimmed form used for
// lookup, signing, Redis keys, and rate-limit keys throughout the premium
// subsystem. Every site that persists contact_email or compares against an
// existing row MUST funnel through this helper — otherwise mixed-case rows
// become unreachable after the W1.2/W1.3 magic-link migration.
func NormalizeEmail(s string) string {
	return strings.ToLower(strings.TrimSpace(s))
}

// normalizeContactEmailPtr handles the *string variant used by DTOs (nil =
// "no email provided"). Returns nil unchanged so we don't lose the "absent"
// signal; an empty-after-normalization string also becomes nil.
func normalizeContactEmailPtr(p *string) *string {
	if p == nil {
		return nil
	}
	n := NormalizeEmail(*p)
	if n == "" {
		return nil
	}
	return &n
}
