package dto

type AdminLoginResponse struct {
	Token     string    `json:"token"`
	ExpiresAt string    `json:"expires_at"`
	Admin     AdminInfo `json:"admin"`
}

type AdminInfo struct {
	ID         string `json:"id"`
	Email      string `json:"email"`
	Name       string `json:"name"`
	BrandScope string `json:"brand_scope"` // "" = super admin, "ssvid", "vidcombo"
}

// BrandSummary holds key KPIs for a single brand in the comparison view.
type BrandSummary struct {
	Brand           string  `json:"brand"`
	TotalDevices    int64   `json:"total_devices"`
	ActiveToday     int64   `json:"active_today"`
	NewToday        int64   `json:"new_today"`
	RevenueMonth    int64   `json:"revenue_month_cents"`
	PremiumLicenses int64   `json:"premium_licenses"`
	OpenBugs        int64   `json:"open_bugs"`
	OpenTickets     int64   `json:"open_tickets"`
	CrashGroups     int64   `json:"crash_groups_active"`
	RatingAverage   float64 `json:"rating_average"`
}

// BrandComparisonResponse returns KPIs for all brands side-by-side.
type BrandComparisonResponse struct {
	Brands []BrandSummary `json:"brands"`
}

// ActivityFeedResponse wraps a list of recent system-wide events.
type ActivityFeedResponse struct {
	Events []TimelineEvent `json:"events"`
}

// TopCustomerSummary is a single row in the top customers leaderboard.
type TopCustomerSummary struct {
	ContactEmail    string `json:"contact_email"`
	LicenseCount    int64  `json:"license_count"`
	TotalSpentCents int64  `json:"total_spent_cents"`
	LastPurchase    string `json:"last_purchase"`
}

// TopCustomersResponse returns the top revenue customers.
type TopCustomersResponse struct {
	Customers []TopCustomerSummary `json:"customers"`
}

// TrendMetric holds current-period vs previous-period comparison for a single metric.
type TrendMetric struct {
	Current   int64   `json:"current"`
	Previous  int64   `json:"previous"`
	ChangePct float64 `json:"change_pct"` // percentage change; positive = growth, negative = decline
}

// DailyPoint is a single day's value in a time-series.
type DailyPoint struct {
	Date  string `json:"date"`  // YYYY-MM-DD
	Value int64  `json:"value"`
}

// DashboardTrendsResponse provides period-over-period comparison for key dashboard metrics.
type DashboardTrendsResponse struct {
	Days int `json:"days"` // period length

	NewDevices     TrendMetric `json:"new_devices"`
	ActiveDevices  TrendMetric `json:"active_devices"`
	RevenueCents   TrendMetric `json:"revenue_cents"`
	NewBugs        TrendMetric `json:"new_bugs"`
	NewTickets     TrendMetric `json:"new_tickets"`
	NewCrashes     TrendMetric `json:"new_crashes"`
	Downloads      TrendMetric `json:"downloads"`
	DownloadErrors TrendMetric `json:"download_errors"`

	// Daily series for sparklines
	DailyDevices []DailyPoint `json:"daily_devices"`
	DailyRevenue []DailyPoint `json:"daily_revenue"`
}

// ComprehensiveStatsResponse aggregates all key metrics for the admin dashboard in a single response.
type ComprehensiveStatsResponse struct {
	// Devices
	TotalDevices int64            `json:"total_devices"`
	ActiveToday  int64            `json:"active_today"`
	Active7d     int64            `json:"active_7d"`
	NewToday     int64            `json:"new_today"`
	ByOS         map[string]int64 `json:"by_os"`
	ByVersion    map[string]int64 `json:"by_version"`
	ByTier       map[string]int64 `json:"by_tier"`

	// Bugs
	OpenBugs     int64            `json:"open_bugs"`
	NewBugsToday int64            `json:"new_bugs_today"`
	BugsByStatus map[string]int64 `json:"bugs_by_status"`

	// Crashes
	CrashesToday int64 `json:"crashes_today"`

	// Crash Groups
	CrashGroupsActive   int64            `json:"crash_groups_active"`
	CrashGroupsTotal    int64            `json:"crash_groups_total"`
	CrashGroupsCritical int64            `json:"crash_groups_critical"`
	CrashGroupsByStatus map[string]int64 `json:"crash_groups_by_status"`

	// Download Errors
	DownloadErrorsToday int64            `json:"download_errors_today"`
	DownloadErrorsTotal int64            `json:"download_errors_total"`
	TopErrorCodes       map[string]int64 `json:"top_error_codes"`

	// Downloads
	DownloadSuccessRate int   `json:"download_success_rate"`
	DownloadsToday      int64 `json:"downloads_today"`

	// Tickets
	OpenTickets     int64 `json:"open_tickets"`
	NewTicketsToday int64 `json:"new_tickets_today"`

	// Ratings
	RatingAverage float64 `json:"rating_average"`
	TotalRatings  int64   `json:"total_ratings"`

	// Revenue
	RevenueTodayCents int64 `json:"revenue_today_cents"`
	RevenueMonthCents int64 `json:"revenue_month_cents"`
	PremiumLicenses   int64 `json:"premium_licenses"`
	ActiveLicenses    int64 `json:"active_licenses"`
}
