package timeutil

import (
	"testing"
	"time"
)

func TestUTCStartOfDay(t *testing.T) {
	input := time.Date(2026, 4, 22, 23, 45, 12, 0, time.FixedZone("UTC+7", 7*60*60))

	got := UTCStartOfDay(input)
	want := time.Date(2026, 4, 22, 0, 0, 0, 0, time.UTC)

	if !got.Equal(want) {
		t.Fatalf("UTCStartOfDay() = %v, want %v", got, want)
	}
	if got.Location() != time.UTC {
		t.Fatalf("UTCStartOfDay() location = %v, want UTC", got.Location())
	}
}

func TestUTCDayBounds(t *testing.T) {
	input := time.Date(2026, 12, 31, 23, 59, 59, 0, time.FixedZone("UTC-5", -5*60*60))

	start, end := UTCDayBounds(input)

	wantStart := time.Date(2027, 1, 1, 0, 0, 0, 0, time.UTC)
	wantEnd := time.Date(2027, 1, 2, 0, 0, 0, 0, time.UTC)

	if !start.Equal(wantStart) {
		t.Fatalf("UTCDayBounds() start = %v, want %v", start, wantStart)
	}
	if !end.Equal(wantEnd) {
		t.Fatalf("UTCDayBounds() end = %v, want %v", end, wantEnd)
	}
}

func TestUTCMonthBounds(t *testing.T) {
	input := time.Date(2026, 12, 31, 23, 59, 59, 0, time.FixedZone("UTC-5", -5*60*60))

	start, end := UTCMonthBounds(input)

	wantStart := time.Date(2027, 1, 1, 0, 0, 0, 0, time.UTC)
	wantEnd := time.Date(2027, 2, 1, 0, 0, 0, 0, time.UTC)

	if !start.Equal(wantStart) {
		t.Fatalf("UTCMonthBounds() start = %v, want %v", start, wantStart)
	}
	if !end.Equal(wantEnd) {
		t.Fatalf("UTCMonthBounds() end = %v, want %v", end, wantEnd)
	}
}
