// Common
export interface ApiResponse<T> {
  success: boolean
  data: T
  error?: { code: string; message: string; details?: string }
}

export interface PaginatedResponse<T> {
  success: boolean
  data: {
    items: T[]
    total: number
    page: number
    per_page: number
    total_pages: number
  }
}

// Auth
export interface LoginRequest {
  email: string
  password: string
}

export interface LoginResponse {
  token: string
  expires_at: string
  admin: AdminInfo
}

export interface AdminInfo {
  id: string
  email: string
  name: string
  brand_scope: string
}

// Devices
export interface Device {
  id: string
  hardware_id: string
  brand: string
  os: string
  os_version: string
  app_version: string
  device_name: string
  tier: string
  is_active: boolean
  created_at: string
  last_seen_at: string
}

// Bugs
export interface BugReport {
  id: string
  device_id: string
  title: string
  description: string
  priority: string
  status: string
  app_version: string
  os: string
  os_version: string
  steps: string
  admin_notes: string
  resolved_at: string
  created_at: string
  updated_at: string
  attachments?: BugAttachment[]
  has_diagnostics?: boolean
  device?: Device
}

export interface BugAttachment {
  id: string
  file_name: string
  file_url: string
  file_type: string
  file_size: number
}

export interface CrashReport {
  id: string
  device_id: string
  crash_group_id?: string
  error_message: string
  stack_trace: string
  app_version: string
  os: string
  os_version: string
  severity: string
  metadata: string
  admin_notes?: string
  created_at: string
  has_diagnostics?: boolean
  device?: Device
}

export interface BugStats {
  bugs: {
    total_bugs: number
    open_today: number
    by_status: Record<string, number>
  }
  crashes: {
    total_crashes: number
    crashes_today: number
    by_severity: Record<string, number>
  }
}

// Crash Groups
export interface CrashGroup {
  id: string
  fingerprint: string
  title: string
  status: string
  severity: string
  first_seen_at: string
  last_seen_at: string
  crash_count: number
  device_count: number
  versions: string
  platforms: string
  admin_notes: string
  assigned_to: string
  resolved_at?: string
  created_at: string
  updated_at: string
}

export interface CrashGroupStats {
  total_groups: number
  active_groups: number
  by_status: Record<string, number>
  by_severity: Record<string, number>
}

// Product Control
export interface FeatureFlag {
  id: string
  key: string
  name: string
  description: string
  enabled: boolean
  tiers: string
  platforms: string
  min_app_version: string
  metadata: string
  created_at: string
  updated_at: string
}

export interface RemoteConfig {
  id: string
  key: string
  value: string
  value_type: string
  description: string
  created_at: string
  updated_at: string
}

export interface AppRelease {
  id: string
  version: string
  platform: string
  channel: string
  release_notes: string
  download_url: string
  file_size: number
  checksum: string
  is_mandatory: boolean
  is_active: boolean
  published_at: string | null
  created_at: string
}

export interface Announcement {
  id: string
  title: string
  content: string
  type: string
  target_tiers: string
  target_platforms: string
  is_active: boolean
  starts_at: string
  expires_at: string
  created_at: string
  updated_at: string
}

export interface ProductStats {
  total_flags: number
  enabled_flags: number
  total_configs: number
  total_releases: number
  total_announcements: number
  active_announcements: number
}

// Feedback
export interface Ticket {
  id: string
  device_id: string
  subject: string
  category: string
  status: string
  priority: string
  ai_session_id?: string
  created_at: string
  updated_at: string
  messages?: TicketMessage[]
  device?: Device
}

export interface TicketMessage {
  id: string
  ticket_id: string
  sender_type: string
  sender_id: string
  content: string
  created_at: string
}

export interface FeatureRequest {
  id: string
  device_id: string
  title: string
  description: string
  status: string
  upvotes: number
  admin_response: string
  created_at: string
  updated_at: string
}

export interface AppRating {
  id: string
  device_id: string
  rating: number
  review: string
  app_version: string
  created_at: string
  updated_at: string
}

export interface RatingStats {
  total: number
  average: number
  distribution: Record<string, number>
}

export interface FeedbackStats {
  total_tickets: number
  open_tickets: number
  open_today: number
  total_feature_requests: number
  total_ratings: number
  average_rating: number
}

// Assistant
export interface ChatSession {
  id: string
  device_id: string
  title: string
  status: string
  created_at: string
  updated_at: string
  messages?: ChatMessage[]
}

export interface ChatMessage {
  id: string
  session_id: string
  role: string
  content: string
  tokens_used: number
  created_at: string
}

export interface KnowledgeBase {
  id: string
  title: string
  content: string
  category: string
  tags: string
  is_active: boolean
  created_at: string
  updated_at: string
}

export interface AssistantStats {
  total_sessions: number
  active_sessions: number
  escalated_sessions: number
  total_messages: number
  total_tokens: number
  total_knowledge: number
}

// Analytics
export interface AnalyticsEvent {
  id: string
  device_id: string
  event_type: string
  event_data: string
  app_version: string
  os: string
  created_at: string
}

export interface BootstrapEvent {
  id: string
  install_id: string
  brand: string
  os: string
  os_version?: string
  app_version: string
  stage: string
  status: string
  error_code?: string
  error_message?: string
  metadata?: string
  ip_address?: string
  user_agent?: string
  created_at: string
}

export interface AnalyticsOverview {
  total_events: number
  events_today: number
  active_devices_today: number
  by_os: Record<string, number>
  by_version: Record<string, number>
}

export interface TopEvent {
  event_type: string
  count: number
}

export interface DailyStatsEntry {
  date: string
  metric_name: string
  value: number
  dimensions?: string
}

// Diagnostic Logs
export interface DiagnosticLog {
  id: string
  report_type: string
  report_id: string
  content: string
  line_count: number
  size_bytes: number
  created_at: string
}

// Download Analytics
export interface DownloadStats {
  total_downloads: number
  success_count: number
  error_count: number
  success_rate: number
  by_platform: PlatformStats[]
  by_os: Record<string, number>
  daily_trend: DailyDownloadStats[]
}

export interface PlatformStats {
  platform: string
  total: number
  success: number
  errors: number
  success_rate: number
}

export interface DailyDownloadStats {
  date: string
  total: number
  success: number
  errors: number
}

// Alerts
export interface AlertConfig {
  id: string
  name: string
  metric_type: string
  threshold: number
  window_mins: number
  channel: string
  destination: string
  is_enabled: boolean
  cooldown_mins: number
  last_fired_at?: string
  created_at: string
  updated_at: string
}

export interface AlertLog {
  id: string
  alert_config_id: string
  metric_value: number
  message: string
  channel: string
  status: string
  error_message?: string
  created_at: string
}

// Premium / Licensing
export interface License {
  id: string
  device_id: string
  license_key: string
  tier: string
  billing_cycle: string
  payment_method: string
  contact_email?: string
  stripe_customer_id?: string
  stripe_subscription_id?: string
  is_auto_renew: boolean
  expires_at: string
  cancelled_at?: string
  created_at: string
  updated_at: string
}

export interface Transaction {
  id: string
  license_id?: string
  device_id: string
  idempotency_key: string
  payment_method: string
  billing_cycle: string
  amount_cents: number
  currency: string
  status: string
  stripe_session_id?: string
  crypto_invoice_id?: string
  error_message?: string
  completed_at?: string
  created_at: string
  updated_at: string
}

export interface EnhancedTransaction extends Transaction {
  contact_email?: string
  license_key?: string
}

export interface TransactionStats {
  total_transactions: number
  total_revenue_cents: number
  revenue_today_cents: number
  revenue_this_month_cents: number
  by_status: Record<string, number>
}

export interface PremiumStats {
  total_licenses: number
  active_licenses: number
  expired_licenses: number
  cancelled_count: number
  total_revenue_cents: number
  monthly_revenue_cents: number
  yearly_revenue_cents: number
  stripe_count: number
  crypto_count: number
  churn_rate: number
}

// Subscriptions
export interface Subscription extends License {
  status: string
  device_count: number
  max_devices: number
}

export interface SubscriptionStats {
  active_count: number
  cancelled_count: number
  expired_count: number
  total_count: number
  mrr_cents: number
  churn_rate: number
}

// Customers
export interface Customer {
  contact_email: string
  stripe_customer_id?: string
  license_count: number
  active_licenses: number
  total_spent_cents: number
  first_purchase: string
  last_purchase: string
}

export interface CustomerDetail extends Customer {
  licenses: License[]
  transactions: EnhancedTransaction[]
}

export interface CustomerStats {
  total_customers: number
  total_revenue_cents: number
  avg_revenue_cents: number
}

// Revenue Report
export interface RevenueReport {
  total_revenue_cents: number
  revenue_today_cents: number
  revenue_this_month_cents: number
  total_refunded_cents: number
  refund_count: number
  net_revenue_cents: number
  by_method: { payment_method: string; amount_cents: number; count: number }[]
  by_cycle: { billing_cycle: string; amount_cents: number; count: number }[]
  daily_revenue: { date: string; amount_cents: number; count: number }[]
}

// Invoices
export interface Invoice {
  id: string
  stripe_invoice_id: string
  license_id?: string
  contact_email: string
  status: string
  amount_due_cents: number
  amount_paid_cents: number
  currency: string
  billing_reason: string
  invoice_pdf_url?: string
  hosted_invoice_url?: string
  period_start?: string
  period_end?: string
  paid_at?: string
  created_at: string
  updated_at: string
}

export interface InvoiceStats {
  total_invoices: number
  total_paid_cents: number
  by_status: Record<string, number>
}

export interface MRRPoint {
  month: string
  amount_cents: number
  count: number
}

// Device Timeline
export interface TimelineEvent {
  type: string
  timestamp: string
  title: string
  description: string
  severity: string
  related_id: string
  metadata?: string
}

export interface DeviceTimelineResponse {
  events: TimelineEvent[]
  total_count: number
}

// Download Errors
export interface DownloadError {
  id: string
  device_id: string
  url: string
  platform: string
  error_code: string
  error_phase: string
  error_message: string
  diagnostic_error_code?: string
  diagnostic_error_phase?: string
  diagnostic_signature?: string
  app_version: string
  os: string
  os_version: string
  metadata: string
  created_at: string
}

export interface DownloadErrorStats {
  total_errors: number
  errors_today: number
  by_error_code: Record<string, number>
  by_diagnostic_error_code?: Record<string, number>
  diagnostic_rows: number
  diagnostic_coverage_pct: number
  diagnostic_mode: string
  by_phase: Record<string, number>
  by_platform: Record<string, number>
  daily_trend: { date: string; count: number }[]
  top_errors: { error_code: string; platform: string; count: number }[]
}

// Comprehensive Dashboard
export interface ComprehensiveStats {
  // Devices
  total_devices: number
  active_today: number
  active_7d: number
  new_today: number
  by_os: Record<string, number>
  by_version: Record<string, number>
  by_tier: Record<string, number>
  by_brand: Record<string, number>
  // Bugs
  open_bugs: number
  new_bugs_today: number
  bugs_by_status: Record<string, number>
  // Crashes
  crashes_today: number
  // Crash Groups
  crash_groups_active: number
  crash_groups_total: number
  crash_groups_critical: number
  crash_groups_by_status: Record<string, number>
  // Download Errors
  download_errors_today: number
  download_errors_total: number
  top_error_codes: Record<string, number>
  // Downloads
  download_success_rate: number
  downloads_today: number
  // Tickets
  open_tickets: number
  new_tickets_today: number
  // Ratings
  rating_average: number
  total_ratings: number
  // Revenue
  revenue_today_cents: number
  revenue_month_cents: number
  premium_licenses: number
  active_licenses: number
}

// Dashboard Trends (period-over-period comparison)
export interface TrendMetric {
  current: number
  previous: number
  change_pct: number
}

export interface DailyPoint {
  date: string
  value: number
}

export interface DashboardTrendsResponse {
  days: number
  new_devices: TrendMetric
  active_devices: TrendMetric
  revenue_cents: TrendMetric
  new_bugs: TrendMetric
  new_tickets: TrendMetric
  new_crashes: TrendMetric
  downloads: TrendMetric
  download_errors: TrendMetric
  daily_devices: DailyPoint[]
  daily_revenue: DailyPoint[]
}

// Brand Comparison
export interface BrandSummary {
  brand: string
  total_devices: number
  active_today: number
  new_today: number
  revenue_month_cents: number
  premium_licenses: number
  open_bugs: number
  open_tickets: number
  crash_groups_active: number
  rating_average: number
}

export interface BrandComparisonResponse {
  brands: BrandSummary[]
}

// Activity Feed (dashboard)
export interface ActivityFeedEvent {
  type: string
  timestamp: string
  title: string
  description: string
  severity: string
  related_id: string
  metadata: string
}

export interface ActivityFeedResponse {
  events: ActivityFeedEvent[]
}

// Top Customers (dashboard)
export interface TopCustomerSummary {
  contact_email: string
  license_count: number
  total_spent_cents: number
  last_purchase: string
}

export interface TopCustomersResponse {
  customers: TopCustomerSummary[]
}

// Global Search
export interface GlobalSearchResult {
  licenses: License[]
  transactions: EnhancedTransaction[]
  customers: Customer[]
}

// Audit Logs
export interface AuditLogEntry {
  id: string
  admin_id: string
  admin_email: string
  action: string
  resource_type: string
  resource_id: string
  path: string
  request_body?: string
  status_code: number
  ip_address: string
  created_at: string
}

// Webhook Events
export interface WebhookEvent {
  id: number
  event_id: string
  event_type: string
  status: string
  processed_at?: string
  created_at: string
}

// System Health
export interface SystemHealth {
  status: string
  timestamp: string
  go_version: string
  goroutines: number
  memory_mb: number
  sys_memory_mb: number
  gc_runs: number
  db_status: string
  db_pool_open: number
  db_pool_idle: number
}

// Admin User
export interface AdminUser {
  id: string
  email: string
  name: string
  brand_scope: string
  created_at: string
  last_login_at?: string
}

// API Key
export interface ApiKeyInfo {
  id: string
  device_id: string
  is_revoked: boolean
  is_valid: boolean
  created_at: string
  expires_at: string
}
