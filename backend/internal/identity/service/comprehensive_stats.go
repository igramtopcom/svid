package service

import (
	"math"
	"sort"
	"strings"
	"time"

	"github.com/snakeloader/backend/internal/identity/dto"
	"github.com/snakeloader/backend/internal/pkg/timeutil"
	premiummodel "github.com/snakeloader/backend/internal/premium/model"
	"gorm.io/gorm"
)

// ComprehensiveStatsService provides a single-query aggregation of all dashboard metrics.
type ComprehensiveStatsService struct {
	db *gorm.DB
}

var dashboardBrandOrder = []string{"svid", "vidcombo"}

func NewComprehensiveStatsService(db *gorm.DB) *ComprehensiveStatsService {
	return &ComprehensiveStatsService{db: db}
}

// GetDashboardTrends returns period-over-period comparison for key metrics.
// current period = last `days` days, previous period = `days` before that.
func (s *ComprehensiveStatsService) GetDashboardTrends(days int, brand string) (*dto.DashboardTrendsResponse, error) {
	if days <= 0 {
		days = 7
	}
	if days > 365 {
		days = 365
	}

	now := time.Now().UTC()
	todayStart := timeutil.UTCStartOfDay(now)
	currentStart := todayStart.AddDate(0, 0, -days)
	previousStart := todayStart.AddDate(0, 0, -days*2)
	tomorrow := todayStart.AddDate(0, 0, 1)

	resp := &dto.DashboardTrendsResponse{Days: days}

	// Brand filter fragments
	var dAnd, didAnd, invAnd string
	if brand != "" {
		dAnd = " AND brand = ?"
		didAnd = " AND device_id IN (SELECT id FROM devices WHERE brand = ?)"
		invAnd = " AND brand = ?"
	}

	// Helper to run a count query for current and previous periods.
	trendCount := func(table, dateCol, extraWhere string, useBrand string) dto.TrendMetric {
		var current, previous int64

		// Current period: [currentStart, tomorrow)
		q := "SELECT COUNT(*) FROM " + table + " WHERE " + dateCol + " >= ? AND " + dateCol + " < ?" + extraWhere
		args := []interface{}{currentStart, tomorrow}
		if useBrand != "" && brand != "" {
			args = append(args, brand)
		}
		s.db.Raw(q, args...).Scan(&current)

		// Previous period: [previousStart, currentStart)
		q2 := "SELECT COUNT(*) FROM " + table + " WHERE " + dateCol + " >= ? AND " + dateCol + " < ?" + extraWhere
		args2 := []interface{}{previousStart, currentStart}
		if useBrand != "" && brand != "" {
			args2 = append(args2, brand)
		}
		s.db.Raw(q2, args2...).Scan(&previous)

		return makeTrend(current, previous)
	}

	// Helper for sum queries (revenue)
	trendSum := func(table, sumCol, dateCol, statusWhere, brandFrag string) dto.TrendMetric {
		var current, previous int64

		q := "SELECT COALESCE(SUM(" + sumCol + "), 0) FROM " + table + " WHERE " + statusWhere + " AND " + dateCol + " >= ? AND " + dateCol + " < ?" + brandFrag
		args := []interface{}{currentStart, tomorrow}
		if brandFrag != "" && brand != "" {
			args = append(args, brand)
		}
		s.db.Raw(q, args...).Scan(&current)

		q2 := "SELECT COALESCE(SUM(" + sumCol + "), 0) FROM " + table + " WHERE " + statusWhere + " AND " + dateCol + " >= ? AND " + dateCol + " < ?" + brandFrag
		args2 := []interface{}{previousStart, currentStart}
		if brandFrag != "" && brand != "" {
			args2 = append(args2, brand)
		}
		s.db.Raw(q2, args2...).Scan(&previous)

		return makeTrend(current, previous)
	}

	// 1. New devices
	resp.NewDevices = trendCount("devices", "created_at", dAnd, "d")

	// 2. Active devices (unique devices seen)
	{
		var current, previous int64
		q := "SELECT COUNT(*) FROM devices WHERE last_seen_at >= ? AND last_seen_at < ?" + dAnd
		args := []interface{}{currentStart, tomorrow}
		if brand != "" {
			args = append(args, brand)
		}
		s.db.Raw(q, args...).Scan(&current)

		q2 := "SELECT COUNT(*) FROM devices WHERE last_seen_at >= ? AND last_seen_at < ?" + dAnd
		args2 := []interface{}{previousStart, currentStart}
		if brand != "" {
			args2 = append(args2, brand)
		}
		s.db.Raw(q2, args2...).Scan(&previous)

		resp.ActiveDevices = makeTrend(current, previous)
	}

	// 3. Revenue (invoices)
	resp.RevenueCents = trendSum("invoices", "amount_paid_cents", "COALESCE(paid_at, created_at)", "status = 'paid'", invAnd)

	// 4. New bugs
	resp.NewBugs = trendCount("bug_reports", "created_at", didAnd, "did")

	// 5. New tickets
	resp.NewTickets = trendCount("tickets", "created_at", didAnd, "did")

	// 6. New crashes
	resp.NewCrashes = trendCount("crash_reports", "created_at", didAnd, "did")

	// 7. Downloads (analytics_events)
	{
		dlWhere := " AND event_type IN ('download_start','download_complete','download_error')"
		resp.Downloads = trendCount("analytics_events", "created_at", dlWhere+didAnd, "did")
	}

	// 8. Download errors
	resp.DownloadErrors = trendCount("download_errors", "created_at", didAnd, "did")

	// Daily series: new devices
	{
		var rows []struct {
			Date  string `gorm:"column:date"`
			Value int64  `gorm:"column:value"`
		}
		q := "SELECT DATE(created_at AT TIME ZONE 'UTC') as date, COUNT(*) as value FROM devices WHERE created_at >= ? AND created_at < ?" + dAnd + " GROUP BY DATE(created_at AT TIME ZONE 'UTC') ORDER BY date"
		args := []interface{}{currentStart, tomorrow}
		if brand != "" {
			args = append(args, brand)
		}
		s.db.Raw(q, args...).Scan(&rows)
		resp.DailyDevices = make([]dto.DailyPoint, len(rows))
		for i, r := range rows {
			resp.DailyDevices[i] = dto.DailyPoint{Date: r.Date, Value: r.Value}
		}
	}

	// Daily series: revenue
	{
		var rows []struct {
			Date  string `gorm:"column:date"`
			Value int64  `gorm:"column:value"`
		}
		q := "SELECT DATE(COALESCE(paid_at, created_at) AT TIME ZONE 'UTC') as date, COALESCE(SUM(amount_paid_cents), 0) as value FROM invoices WHERE status = 'paid' AND COALESCE(paid_at, created_at) >= ? AND COALESCE(paid_at, created_at) < ?" + invAnd + " GROUP BY DATE(COALESCE(paid_at, created_at) AT TIME ZONE 'UTC') ORDER BY date"
		args := []interface{}{currentStart, tomorrow}
		if brand != "" {
			args = append(args, brand)
		}
		s.db.Raw(q, args...).Scan(&rows)
		resp.DailyRevenue = make([]dto.DailyPoint, len(rows))
		for i, r := range rows {
			resp.DailyRevenue[i] = dto.DailyPoint{Date: r.Date, Value: r.Value}
		}
	}

	return resp, nil
}

// makeTrend calculates a TrendMetric from current and previous values.
func makeTrend(current, previous int64) dto.TrendMetric {
	t := dto.TrendMetric{Current: current, Previous: previous}
	if previous > 0 {
		t.ChangePct = float64(current-previous) / float64(previous) * 100
	} else if current > 0 {
		t.ChangePct = 100 // went from 0 to something = +100%
	}
	// Round to 1 decimal
	t.ChangePct = math.Round(t.ChangePct*10) / 10
	return t
}

// GetBrandComparison returns key KPIs for each brand side-by-side.
func (s *ComprehensiveStatsService) GetBrandComparison() (*dto.BrandComparisonResponse, error) {
	now := time.Now().UTC()
	todayStart, tomorrow := timeutil.UTCDayBounds(now)
	monthStart, nextMonth := timeutil.UTCMonthBounds(now)

	// 1. Device metrics per brand
	var deviceRows []struct {
		Brand       string `gorm:"column:brand"`
		Total       int64  `gorm:"column:total"`
		ActiveToday int64  `gorm:"column:active_today"`
		NewToday    int64  `gorm:"column:new_today"`
	}
	s.db.Raw(`SELECT brand, COUNT(*) as total,
		COUNT(*) FILTER (WHERE last_seen_at >= ? AND last_seen_at < ?) as active_today,
		COUNT(*) FILTER (WHERE created_at >= ? AND created_at < ?) as new_today
		FROM devices GROUP BY brand`, todayStart, tomorrow, todayStart, tomorrow).Scan(&deviceRows)

	// Build brand map
	brands := make(map[string]*dto.BrandSummary)
	for _, brandName := range dashboardBrandOrder {
		ensureBrandSummary(brands, brandName)
	}
	for _, r := range deviceRows {
		summary := ensureBrandSummary(brands, r.Brand)
		if summary == nil {
			continue
		}
		*summary = dto.BrandSummary{
			Brand:        summary.Brand,
			TotalDevices: r.Total,
			ActiveToday:  r.ActiveToday,
			NewToday:     r.NewToday,
		}
	}

	// 2. Revenue per brand (from invoices — direct brand column)
	var revenueRows []struct {
		Brand   string `gorm:"column:brand"`
		Revenue int64  `gorm:"column:revenue"`
	}
	s.db.Raw(`SELECT brand, COALESCE(SUM(amount_paid_cents), 0) as revenue
		FROM invoices WHERE status = 'paid' AND COALESCE(paid_at, created_at) >= ? AND COALESCE(paid_at, created_at) < ?
		GROUP BY brand`, monthStart, nextMonth).Scan(&revenueRows)
	for _, r := range revenueRows {
		if summary := ensureBrandSummary(brands, r.Brand); summary != nil {
			summary.RevenueMonth = r.Revenue
		}
	}

	// 3. Premium licenses per brand (direct brand column)
	var licenseRows []struct {
		Brand string `gorm:"column:brand"`
		Count int64  `gorm:"column:count"`
	}
	s.db.Raw(`SELECT brand, COUNT(*) as count FROM premium_licenses WHERE tier = 'premium' GROUP BY brand`).Scan(&licenseRows)
	for _, r := range licenseRows {
		if summary := ensureBrandSummary(brands, r.Brand); summary != nil {
			summary.PremiumLicenses = r.Count
		}
	}

	// 4. Open bugs per brand (via device_id FK)
	var bugRows []struct {
		Brand string `gorm:"column:brand"`
		Count int64  `gorm:"column:count"`
	}
	s.db.Raw(`SELECT d.brand, COUNT(*) as count FROM bug_reports b
		JOIN devices d ON d.id = b.device_id
		WHERE b.status IN ('new','triaging','in_progress')
		GROUP BY d.brand`).Scan(&bugRows)
	for _, r := range bugRows {
		if summary := ensureBrandSummary(brands, r.Brand); summary != nil {
			summary.OpenBugs = r.Count
		}
	}

	// 5. Open tickets per brand (via device_id FK)
	var ticketRows []struct {
		Brand string `gorm:"column:brand"`
		Count int64  `gorm:"column:count"`
	}
	s.db.Raw(`SELECT d.brand, COUNT(*) as count FROM tickets t
		JOIN devices d ON d.id = t.device_id
		WHERE t.status IN ('open','in_progress')
		GROUP BY d.brand`).Scan(&ticketRows)
	for _, r := range ticketRows {
		if summary := ensureBrandSummary(brands, r.Brand); summary != nil {
			summary.OpenTickets = r.Count
		}
	}

	// 6. Active crash groups per brand (via crash_reports FK)
	var cgRows []struct {
		Brand string `gorm:"column:brand"`
		Count int64  `gorm:"column:count"`
	}
	s.db.Raw(`SELECT d.brand, COUNT(DISTINCT cg.id) as count FROM crash_groups cg
		JOIN crash_reports cr ON cr.crash_group_id = cg.id
		JOIN devices d ON d.id = cr.device_id
		WHERE cg.status NOT IN ('resolved','wont_fix')
		GROUP BY d.brand`).Scan(&cgRows)
	for _, r := range cgRows {
		if summary := ensureBrandSummary(brands, r.Brand); summary != nil {
			summary.CrashGroups = r.Count
		}
	}

	// 7. Average rating per brand (via device_id FK)
	var ratingRows []struct {
		Brand   string  `gorm:"column:brand"`
		Average float64 `gorm:"column:average"`
	}
	s.db.Raw(`SELECT d.brand, AVG(r.rating) as average FROM app_ratings r
		JOIN devices d ON d.id = r.device_id
		GROUP BY d.brand`).Scan(&ratingRows)
	for _, r := range ratingRows {
		if summary := ensureBrandSummary(brands, r.Brand); summary != nil {
			summary.RatingAverage = r.Average
		}
	}

	// Assemble response
	return &dto.BrandComparisonResponse{Brands: orderedBrandSummaries(brands)}, nil
}

// GetComprehensiveStats returns all key admin dashboard metrics in one response.
// When brand is non-empty, all queries are filtered to devices matching that brand.
func (s *ComprehensiveStatsService) GetComprehensiveStats(brand string) (*dto.ComprehensiveStatsResponse, error) {
	stats := &dto.ComprehensiveStatsResponse{
		ByOS:                make(map[string]int64),
		ByVersion:           make(map[string]int64),
		ByTier:              make(map[string]int64),
		BugsByStatus:        make(map[string]int64),
		CrashGroupsByStatus: make(map[string]int64),
		TopErrorCodes:       make(map[string]int64),
	}

	now := time.Now().UTC()
	todayStart, tomorrow := timeutil.UTCDayBounds(now)
	monthStart, nextMonth := timeutil.UTCMonthBounds(now)

	// Brand filter fragments — empty strings when brand is "" (no filtering).
	var (
		dWhere string // devices: standalone WHERE clause
		dAnd   string // devices: appended AND clause
		didAnd string // tables with device_id FK
		cgAnd  string // crash_groups (via crash_reports.device_id)
		plAnd  string // premium_licenses (direct brand column)
		invAnd string // invoices (direct brand column)
	)
	if brand != "" {
		dWhere = " WHERE brand = ?"
		dAnd = " AND brand = ?"
		didAnd = " AND device_id IN (SELECT id FROM devices WHERE brand = ?)"
		cgAnd = " AND id IN (SELECT crash_group_id FROM crash_reports WHERE device_id IN (SELECT id FROM devices WHERE brand = ?))"
		plAnd = " AND brand = ?"
		invAnd = " AND brand = ?"
	}

	// Helper: execute a raw query, appending brand arg when filtering is active.
	exec := func(dest interface{}, query string, baseArgs ...interface{}) {
		args := append([]interface{}{}, baseArgs...)
		if brand != "" {
			args = append(args, brand)
		}
		s.db.Raw(query, args...).Scan(dest)
	}

	// ---- Devices ----
	exec(&stats.TotalDevices, "SELECT COUNT(*) FROM devices"+dWhere)
	exec(&stats.ActiveToday, "SELECT COUNT(*) FROM devices WHERE last_seen_at >= ? AND last_seen_at < ?"+dAnd, todayStart, tomorrow)
	exec(&stats.Active7d, "SELECT COUNT(*) FROM devices WHERE last_seen_at >= ?"+dAnd, now.AddDate(0, 0, -7))
	exec(&stats.NewToday, "SELECT COUNT(*) FROM devices WHERE created_at >= ? AND created_at < ?"+dAnd, todayStart, tomorrow)

	var osRows []struct {
		OS    string `gorm:"column:os"`
		Count int64  `gorm:"column:count"`
	}
	exec(&osRows, "SELECT os, COUNT(*) as count FROM devices"+dWhere+" GROUP BY os")
	for _, r := range osRows {
		stats.ByOS[r.OS] = r.Count
	}

	var verRows []struct {
		Version string `gorm:"column:app_version"`
		Count   int64  `gorm:"column:count"`
	}
	exec(&verRows, "SELECT app_version, COUNT(*) as count FROM devices"+dWhere+" GROUP BY app_version ORDER BY count DESC LIMIT 10")
	for _, r := range verRows {
		stats.ByVersion[r.Version] = r.Count
	}

	var tierRows []struct {
		Tier  string `gorm:"column:tier"`
		Count int64  `gorm:"column:count"`
	}
	tierQuery, tierArgs := buildTierDistributionQuery(now, brand)
	s.db.Raw(tierQuery, tierArgs...).Scan(&tierRows)
	for _, r := range tierRows {
		stats.ByTier[r.Tier] = r.Count
	}

	// ---- Bugs (device_id FK) ----
	exec(&stats.OpenBugs, "SELECT COUNT(*) FROM bug_reports WHERE status IN ('new','triaging','in_progress')"+didAnd)
	exec(&stats.NewBugsToday, "SELECT COUNT(*) FROM bug_reports WHERE created_at >= ? AND created_at < ?"+didAnd, todayStart, tomorrow)

	var bugStatusRows []struct {
		Status string `gorm:"column:status"`
		Count  int64  `gorm:"column:count"`
	}
	exec(&bugStatusRows, "SELECT status, COUNT(*) as count FROM bug_reports WHERE 1=1"+didAnd+" GROUP BY status")
	for _, r := range bugStatusRows {
		stats.BugsByStatus[r.Status] = r.Count
	}

	// ---- Crashes (device_id FK) ----
	exec(&stats.CrashesToday, "SELECT COUNT(*) FROM crash_reports WHERE created_at >= ? AND created_at < ?"+didAnd, todayStart, tomorrow)

	// ---- Crash Groups (via crash_reports.device_id) ----
	exec(&stats.CrashGroupsActive, "SELECT COUNT(*) FROM crash_groups WHERE status NOT IN ('resolved', 'wont_fix')"+cgAnd)
	exec(&stats.CrashGroupsTotal, "SELECT COUNT(*) FROM crash_groups WHERE 1=1"+cgAnd)
	exec(&stats.CrashGroupsCritical, "SELECT COUNT(*) FROM crash_groups WHERE severity = 'critical' AND status NOT IN ('resolved', 'wont_fix')"+cgAnd)

	var cgStatusRows []struct {
		Status string `gorm:"column:status"`
		Count  int64  `gorm:"column:count"`
	}
	exec(&cgStatusRows, "SELECT status, COUNT(*) as count FROM crash_groups WHERE 1=1"+cgAnd+" GROUP BY status")
	for _, r := range cgStatusRows {
		stats.CrashGroupsByStatus[r.Status] = r.Count
	}

	// ---- Download Errors (device_id FK) ----
	exec(&stats.DownloadErrorsToday, "SELECT COUNT(*) FROM download_errors WHERE created_at >= ? AND created_at < ?"+didAnd, todayStart, tomorrow)
	exec(&stats.DownloadErrorsTotal, "SELECT COUNT(*) FROM download_errors WHERE 1=1"+didAnd)

	var errCodeRows []struct {
		ErrorCode string `gorm:"column:error_code"`
		Count     int64  `gorm:"column:count"`
	}
	exec(&errCodeRows, "SELECT error_code, COUNT(*) as count FROM download_errors WHERE 1=1"+didAnd+" GROUP BY error_code ORDER BY count DESC LIMIT 5")
	for _, r := range errCodeRows {
		stats.TopErrorCodes[r.ErrorCode] = r.Count
	}

	// ---- Downloads (analytics_events, device_id FK) ----
	var totalDL, successDL int64
	exec(&totalDL, "SELECT COUNT(*) FROM analytics_events WHERE created_at >= ? AND created_at < ? AND event_type IN ('download_complete','download_error')"+didAnd, todayStart, tomorrow)
	exec(&successDL, "SELECT COUNT(*) FROM analytics_events WHERE created_at >= ? AND created_at < ? AND event_type = 'download_complete'"+didAnd, todayStart, tomorrow)
	if totalDL > 0 {
		stats.DownloadSuccessRate = int(successDL * 100 / totalDL)
	}
	exec(&stats.DownloadsToday, "SELECT COUNT(*) FROM analytics_events WHERE created_at >= ? AND created_at < ? AND event_type IN ('download_start','download_complete','download_error')"+didAnd, todayStart, tomorrow)

	// ---- Tickets (device_id FK) ----
	exec(&stats.OpenTickets, "SELECT COUNT(*) FROM tickets WHERE status IN ('open','in_progress')"+didAnd)
	exec(&stats.NewTicketsToday, "SELECT COUNT(*) FROM tickets WHERE created_at >= ? AND created_at < ?"+didAnd, todayStart, tomorrow)

	// ---- Ratings (device_id FK) ----
	exec(&stats.RatingAverage, "SELECT COALESCE(AVG(rating), 0) FROM app_ratings WHERE 1=1"+didAnd)
	exec(&stats.TotalRatings, "SELECT COUNT(*) FROM app_ratings WHERE 1=1"+didAnd)

	// ---- Revenue (invoices via premium_licenses.device_id) ----
	exec(&stats.RevenueTodayCents, "SELECT COALESCE(SUM(amount_paid_cents), 0) FROM invoices WHERE status = 'paid' AND COALESCE(paid_at, created_at) >= ? AND COALESCE(paid_at, created_at) < ?"+invAnd, todayStart, tomorrow)
	exec(&stats.RevenueMonthCents, "SELECT COALESCE(SUM(amount_paid_cents), 0) FROM invoices WHERE status = 'paid' AND COALESCE(paid_at, created_at) >= ? AND COALESCE(paid_at, created_at) < ?"+invAnd, monthStart, nextMonth)
	exec(&stats.PremiumLicenses, "SELECT COUNT(*) FROM premium_licenses WHERE tier = 'premium'"+plAnd)
	exec(&stats.ActiveLicenses, "SELECT COUNT(*) FROM premium_licenses WHERE "+premiummodel.ActivePremiumLicenseSQL("")+plAnd, now)

	return stats, nil
}

func buildTierDistributionQuery(activeAt time.Time, brand string) (string, []interface{}) {
	query := `SELECT
		CASE WHEN EXISTS (
			SELECT 1 FROM premium_licenses pl
			WHERE pl.device_id = d.id AND ` + premiummodel.ActivePremiumLicenseSQL("pl") + `
		) THEN 'premium' ELSE 'free' END as tier,
		COUNT(*) as count
	FROM devices d`

	args := []interface{}{activeAt}
	if brand != "" {
		query += " WHERE d.brand = ?"
		args = append(args, brand)
	}
	query += " GROUP BY tier"
	return query, args
}

func ensureBrandSummary(brands map[string]*dto.BrandSummary, brand string) *dto.BrandSummary {
	normalized := strings.TrimSpace(strings.ToLower(brand))
	if normalized == "" {
		return nil
	}
	if summary, ok := brands[normalized]; ok {
		return summary
	}
	summary := &dto.BrandSummary{Brand: normalized}
	brands[normalized] = summary
	return summary
}

func orderedBrandSummaries(brands map[string]*dto.BrandSummary) []dto.BrandSummary {
	result := make([]dto.BrandSummary, 0, len(brands))
	seen := make(map[string]struct{}, len(brands))

	for _, brand := range dashboardBrandOrder {
		if summary, ok := brands[brand]; ok {
			result = append(result, *summary)
			seen[brand] = struct{}{}
		}
	}

	extraBrands := make([]string, 0, len(brands))
	for brand := range brands {
		if _, ok := seen[brand]; ok {
			continue
		}
		extraBrands = append(extraBrands, brand)
	}
	sort.Strings(extraBrands)
	for _, brand := range extraBrands {
		result = append(result, *brands[brand])
	}

	return result
}
