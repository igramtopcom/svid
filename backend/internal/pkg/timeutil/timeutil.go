package timeutil

import "time"

// UTCStartOfDay returns 00:00:00 for the given instant in UTC.
func UTCStartOfDay(now time.Time) time.Time {
	utc := now.UTC()
	return time.Date(utc.Year(), utc.Month(), utc.Day(), 0, 0, 0, 0, time.UTC)
}

// UTCDayBounds returns the inclusive/exclusive UTC window for the day of now.
func UTCDayBounds(now time.Time) (time.Time, time.Time) {
	start := UTCStartOfDay(now)
	return start, start.AddDate(0, 0, 1)
}

// UTCMonthBounds returns the inclusive/exclusive UTC window for the month of now.
func UTCMonthBounds(now time.Time) (time.Time, time.Time) {
	utc := now.UTC()
	start := time.Date(utc.Year(), utc.Month(), 1, 0, 0, 0, 0, time.UTC)
	return start, start.AddDate(0, 1, 0)
}
