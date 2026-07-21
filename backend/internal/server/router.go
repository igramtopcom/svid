package server

import (
	"io"
	"io/fs"
	"net/http"
	"runtime"
	"time"

	"github.com/gin-gonic/gin"
	alerthandler "github.com/snakeloader/backend/internal/alerts/handler"
	analyticshandler "github.com/snakeloader/backend/internal/analytics/handler"
	assistanthandler "github.com/snakeloader/backend/internal/assistant/handler"
	bughandler "github.com/snakeloader/backend/internal/bugs/handler"
	"github.com/snakeloader/backend/internal/buildinfo"
	feedbackhandler "github.com/snakeloader/backend/internal/feedback/handler"
	"github.com/snakeloader/backend/internal/identity/handler"
	"github.com/snakeloader/backend/internal/identity/repository"
	"github.com/snakeloader/backend/internal/middleware"
	"github.com/snakeloader/backend/internal/pkg/logger"
	premiumhandler "github.com/snakeloader/backend/internal/premium/handler"
	producthandler "github.com/snakeloader/backend/internal/product/handler"
	"github.com/snakeloader/backend/internal/response"
	"github.com/snakeloader/backend/web"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
	"gorm.io/gorm"

	_ "github.com/snakeloader/backend/docs" // swagger docs
)

type RouterDeps struct {
	DB                    *gorm.DB
	DeviceHandler         *handler.DeviceHandler
	AdminAuthHandler      *handler.AdminAuthHandler
	AdminDeviceHandler    *handler.AdminDeviceHandler
	BugHandler            *bughandler.BugHandler
	AdminBugHandler       *bughandler.AdminBugHandler
	ProductHandler        *producthandler.ProductHandler
	AdminProductHandler   *producthandler.AdminProductHandler
	CIReleaseHandler      *producthandler.CIReleaseHandler
	FeedbackHandler       *feedbackhandler.FeedbackHandler
	AdminFeedbackHandler  *feedbackhandler.AdminFeedbackHandler
	AssistantHandler      *assistanthandler.AssistantHandler
	AdminAssistantHandler *assistanthandler.AdminAssistantHandler
	AnalyticsHandler      *analyticshandler.AnalyticsHandler
	AdminAnalyticsHandler *analyticshandler.AdminAnalyticsHandler
	PremiumHandler        *premiumhandler.PremiumHandler
	AdminPremiumHandler   *premiumhandler.AdminPremiumHandler
	WebhookHandler        *premiumhandler.WebhookHandler
	AdminAlertHandler     *alerthandler.AdminAlertHandler
	AdminAuditHandler     *handler.AdminAuditHandler
	AuditLogRepo          *repository.AuditLogRepository
	AuthMiddleware        *middleware.AuthMiddleware
	AdminAuthMW           *middleware.AdminAuthMiddleware
	RateLimiter           *middleware.RateLimiter
	EnableSwagger         bool
}

func RegisterRoutes(engine *gin.Engine, deps RouterDeps, startTime time.Time) {
	// Root
	engine.GET("/", func(c *gin.Context) {
		response.Success(c, http.StatusOK, gin.H{
			"name":    "SnakeLoader Backend API",
			"version": buildinfo.Version,
			"docs":    "/health",
		})
	})

	// Build/version metadata — exposes Git SHA + build time for deploy
	// verification. Public endpoint by design (no secrets, only build hash).
	engine.GET("/version", func(c *gin.Context) {
		response.Success(c, http.StatusOK, gin.H{
			"version":    buildinfo.Version,
			"git_sha":    buildinfo.GitSHA,
			"build_time": buildinfo.BuildTime,
			"go_version": runtime.Version(),
			"uptime":     time.Since(startTime).String(),
		})
	})

	// Liveness probe — minimal, no dependency checks
	engine.GET("/health/live", func(c *gin.Context) {
		response.Success(c, http.StatusOK, gin.H{"status": "alive"})
	})

	// Readiness probe — checks all dependencies
	engine.GET("/health/ready", func(c *gin.Context) {
		checks := gin.H{}
		ready := true

		// Check DB
		sqlDB, err := deps.DB.DB()
		if err != nil || sqlDB.Ping() != nil {
			checks["database"] = "disconnected"
			ready = false
		} else {
			checks["database"] = "connected"
		}

		if ready {
			response.Success(c, http.StatusOK, gin.H{"status": "ready", "checks": checks})
		} else {
			response.Error(c, http.StatusServiceUnavailable, "NOT_READY", "One or more dependencies are unavailable")
		}
	})

	// Full health check (backward compatible)
	engine.GET("/health", func(c *gin.Context) {
		dbStatus := "connected"
		var tableStats gin.H
		sqlDB, err := deps.DB.DB()
		if err != nil || sqlDB.Ping() != nil {
			dbStatus = "disconnected"
		} else {
			var rows []struct {
				Name  string `gorm:"column:name"`
				Count int64  `gorm:"column:count"`
			}
			deps.DB.Raw(`
				SELECT 'devices' as name, COUNT(*) as count FROM devices
				UNION ALL SELECT 'licenses', COUNT(*) FROM premium_licenses
				UNION ALL SELECT 'transactions', COUNT(*) FROM payment_transactions
				UNION ALL SELECT 'tickets', COUNT(*) FROM tickets
				UNION ALL SELECT 'bug_reports', COUNT(*) FROM bug_reports
			`).Scan(&rows)
			tableStats = gin.H{}
			for _, row := range rows {
				tableStats[row.Name] = row.Count
			}
		}

		var mem runtime.MemStats
		runtime.ReadMemStats(&mem)

		response.Success(c, http.StatusOK, gin.H{
			"status":   "healthy",
			"version":  buildinfo.Version,
			"git_sha":  buildinfo.GitSHA,
			"uptime":   time.Since(startTime).String(),
			"database": dbStatus,
			"tables":   tableStats,
			"runtime": gin.H{
				"goroutines": runtime.NumGoroutine(),
				"memory_mb":  mem.Alloc / 1024 / 1024,
				"gc_runs":    mem.NumGC,
			},
		})
	})

	// Metrics endpoint — intentionally kept at top level for k8s/monitoring access
	// Protected by IP-based access in production (reverse proxy layer)
	engine.GET("/metrics", func(c *gin.Context) {
		var mem runtime.MemStats
		runtime.ReadMemStats(&mem)
		response.Success(c, http.StatusOK, gin.H{
			"uptime_seconds": time.Since(startTime).Seconds(),
			"endpoints":      middleware.GlobalMetrics.Snapshot(),
			"runtime": gin.H{
				"goroutines": runtime.NumGoroutine(),
				"memory_mb":  mem.Alloc / 1024 / 1024,
				"gc_runs":    mem.NumGC,
			},
		})
	})

	// Internal CI endpoints (shared secret auth)
	if deps.CIReleaseHandler != nil {
		internal := engine.Group("/internal/ci")
		{
			internal.POST("/releases", deps.CIReleaseHandler.RegisterRelease)
		}
	}

	// Public API v1
	apiV1 := engine.Group("/api/v1")
	{
		devices := apiV1.Group("/devices")
		{
			if deps.RateLimiter != nil {
				devices.POST("/register",
					deps.RateLimiter.StrictMiddleware("register", 5, 60), // 5 req/min per IP — prevent bot spam
					deps.DeviceHandler.Register)
			} else {
				devices.POST("/register", deps.DeviceHandler.Register)
			}
		}

		if deps.RateLimiter != nil {
			apiV1.POST("/bootstrap/events",
				deps.RateLimiter.StrictMiddleware("bootstrap_events", 30, 60), // 30 req/min per IP
				deps.AnalyticsHandler.TrackBootstrapEvent)
		} else {
			apiV1.POST("/bootstrap/events", deps.AnalyticsHandler.TrackBootstrapEvent)
		}

		apiV1.GET("/premium/plans", deps.PremiumHandler.GetPricingPlans)

		// Update check — public (release metadata only, no sensitive data).
		// Auth-gated version caused MISSING_API_KEY crashes on VidCombo cold-start
		// when client raced update check ahead of device registration. Brand is
		// resolved from query param (client always sends it); device context is
		// optional fallback only.
		apiV1.GET("/updates/check", deps.ProductHandler.CheckUpdate)

		// Web payment endpoints — stricter rate limits (public, no auth)
		if deps.RateLimiter != nil {
			apiV1.POST("/premium/stripe/web-checkout",
				deps.RateLimiter.StrictMiddleware("web_checkout", 5, 60), // 5 req/min per IP
				deps.PremiumHandler.WebStripeCheckout)
			apiV1.GET("/premium/stripe/web-verify",
				deps.RateLimiter.StrictMiddleware("web_verify", 20, 60), // 20 req/min per IP
				deps.PremiumHandler.WebStripeVerify)
			apiV1.POST("/premium/web-restore",
				deps.RateLimiter.StrictMiddleware("web_restore", 5, 60), // 5 req/min per IP
				deps.PremiumHandler.WebRestoreLicense)
			apiV1.POST("/premium/web-portal",
				deps.RateLimiter.StrictMiddleware("web_portal", 3, 60), // 3 req/min per IP
				deps.PremiumHandler.WebPortalSession)
			// W1.2/W1.3 magic-link endpoints. Same strict per-IP limits as
			// their secret-returning predecessors; redeem also fails closed
			// when Redis is unavailable so single-use cannot be bypassed.
			apiV1.POST("/premium/web-restore-email",
				deps.RateLimiter.StrictMiddleware("web_restore_email", 5, 60),
				deps.PremiumHandler.WebRestoreMagicLink)
			apiV1.POST("/premium/web-portal-email",
				deps.RateLimiter.StrictMiddleware("web_portal_email", 3, 60),
				deps.PremiumHandler.WebPortalMagicLink)
			apiV1.POST("/premium/redeem",
				deps.RateLimiter.StrictMiddleware("redeem", 10, 60),
				deps.PremiumHandler.RedeemMagicLink)
		} else {
			apiV1.POST("/premium/stripe/web-checkout", deps.PremiumHandler.WebStripeCheckout)
			apiV1.GET("/premium/stripe/web-verify", deps.PremiumHandler.WebStripeVerify)
			apiV1.POST("/premium/web-restore", deps.PremiumHandler.WebRestoreLicense)
			apiV1.POST("/premium/web-portal", deps.PremiumHandler.WebPortalSession)
			apiV1.POST("/premium/web-restore-email", deps.PremiumHandler.WebRestoreMagicLink)
			apiV1.POST("/premium/web-portal-email", deps.PremiumHandler.WebPortalMagicLink)
			apiV1.POST("/premium/redeem", deps.PremiumHandler.RedeemMagicLink)
		}
	}

	// Webhooks (no auth — verified by signature)
	webhooks := engine.Group("/api/v1/webhooks")
	{
		webhooks.POST("/stripe", deps.WebhookHandler.StripeWebhook)
	}

	// Authenticated API v1
	authApiV1 := engine.Group("/api/v1")
	authApiV1.Use(deps.AuthMiddleware.RequireAPIKey())
	{
		devices := authApiV1.Group("/devices")
		{
			devices.POST("/heartbeat", deps.DeviceHandler.Heartbeat)
		}

		// Bug/Crash reporting (device auth)
		authApiV1.POST("/crashes", deps.BugHandler.SubmitCrash)
		authApiV1.POST("/bugs", deps.BugHandler.SubmitBug)
		authApiV1.GET("/bugs", deps.BugHandler.GetMyBugs)
		authApiV1.GET("/bugs/:id", deps.BugHandler.GetBugStatus)

		// Product control (device auth)
		config := authApiV1.Group("/config")
		{
			config.GET("/flags", deps.ProductHandler.GetFlags)
			config.GET("/remote", deps.ProductHandler.GetConfig)
		}
		authApiV1.GET("/announcements", deps.ProductHandler.GetAnnouncements)

		// Tickets (device auth)
		tickets := authApiV1.Group("/tickets")
		{
			tickets.POST("", deps.FeedbackHandler.CreateTicket)
			tickets.GET("", deps.FeedbackHandler.ListMyTickets)
			tickets.GET("/:id", deps.FeedbackHandler.GetMyTicket)
			tickets.POST("/:id/messages", deps.FeedbackHandler.ReplyToTicket)
			tickets.GET("/:id/stream", deps.FeedbackHandler.StreamTicket)
		}

		// Feature requests (device auth)
		features := authApiV1.Group("/features")
		{
			features.POST("", deps.FeedbackHandler.CreateFeatureRequest)
			features.GET("", deps.FeedbackHandler.ListFeatureRequests)
			features.POST("/:id/vote", deps.FeedbackHandler.VoteFeatureRequest)
		}

		// Ratings (device auth)
		authApiV1.POST("/ratings", deps.FeedbackHandler.SubmitRating)

		// Analytics (device auth)
		authApiV1.POST("/analytics/events", deps.AnalyticsHandler.TrackEvent)
		authApiV1.POST("/analytics/download-errors", deps.AnalyticsHandler.TrackDownloadError)

		// Premium (device auth)
		premium := authApiV1.Group("/premium")
		{
			premium.POST("/stripe/checkout", deps.PremiumHandler.StripeCheckout)
			premium.GET("/stripe/verify", deps.PremiumHandler.StripeVerify)
			premium.POST("/stripe/cancel", deps.PremiumHandler.StripeCancel)
			premium.POST("/stripe/portal", deps.PremiumHandler.StripePortal)
			premium.POST("/crypto/invoice", deps.PremiumHandler.CryptoInvoice)
			premium.GET("/crypto/status", deps.PremiumHandler.CryptoStatus)
			premium.GET("/licenses/verify", deps.PremiumHandler.LicenseVerify)  // Legacy — key in query param
			premium.POST("/licenses/verify", deps.PremiumHandler.LicenseVerify) // Preferred — key in header or body
			premium.GET("/transactions", deps.PremiumHandler.MyTransactions)
			premium.GET("/license", deps.PremiumHandler.LicenseInfo)
			premium.GET("/devices", deps.PremiumHandler.ListDevices)
			premium.DELETE("/devices/:deviceId", deps.PremiumHandler.RemoveDevice)
			if deps.RateLimiter != nil {
				premium.POST("/restore", deps.RateLimiter.StrictMiddleware("restore", 5, 60), deps.PremiumHandler.RestoreLicense)
			} else {
				premium.POST("/restore", deps.PremiumHandler.RestoreLicense)
			}
		}

		// AI Assistant (device auth)
		assistant := authApiV1.Group("/assistant/sessions")
		{
			assistant.POST("", deps.AssistantHandler.CreateSession)
			assistant.GET("", deps.AssistantHandler.ListSessions)
			assistant.GET("/:id", deps.AssistantHandler.GetSession)
			assistant.POST("/:id/messages", deps.AssistantHandler.SendMessage)
			assistant.POST("/:id/escalate", deps.AssistantHandler.Escalate)
		}
	}

	// Admin routes
	adminV1 := engine.Group("/admin/v1")
	{
		// Public admin routes
		auth := adminV1.Group("/auth")
		{
			auth.POST("/login", deps.AdminAuthHandler.Login)
		}

		// Protected admin routes
		protected := adminV1.Group("")
		protected.Use(deps.AdminAuthMW.RequireJWT())
		protected.Use(middleware.AuditLog(deps.AuditLogRepo))
		{
			devices := protected.Group("/devices")
			{
				devices.GET("", deps.AdminDeviceHandler.List)
				devices.GET("/:id", deps.AdminDeviceHandler.Get)
				devices.PATCH("/:id", deps.AdminDeviceHandler.Update)
				devices.GET("/:id/timeline", deps.AdminDeviceHandler.GetDeviceTimeline)
			}

			// Bug/Crash management (admin)
			bugs := protected.Group("/bugs")
			{
				bugs.GET("", deps.AdminBugHandler.ListBugs)
				bugs.GET("/stats", deps.AdminBugHandler.BugStats)
				bugs.GET("/:id", deps.AdminBugHandler.GetBug)
				bugs.PATCH("/:id", deps.AdminBugHandler.UpdateBug)
				bugs.GET("/:id/log", deps.AdminBugHandler.GetBugLog)
			}

			crashes := protected.Group("/crashes")
			{
				crashes.GET("", deps.AdminBugHandler.ListCrashes)
				crashes.GET("/:id", deps.AdminBugHandler.GetCrash)
				crashes.PATCH("/:id", deps.AdminBugHandler.UpdateCrash)
				crashes.GET("/:id/log", deps.AdminBugHandler.GetCrashLog)
			}

			crashGroups := protected.Group("/crash-groups")
			{
				crashGroups.GET("/stats", deps.AdminBugHandler.CrashGroupStats)
				crashGroups.GET("/merge-candidates", deps.AdminBugHandler.ListCrashGroupMergeCandidates)
				crashGroups.POST("/backfill-merge", deps.AdminBugHandler.BackfillCrashGroupMerges)
				crashGroups.POST("/merge", deps.AdminBugHandler.MergeCrashGroups)
				crashGroups.GET("", deps.AdminBugHandler.ListCrashGroups)
				crashGroups.GET("/:id", deps.AdminBugHandler.GetCrashGroup)
				crashGroups.PATCH("/:id", deps.AdminBugHandler.UpdateCrashGroup)
				crashGroups.GET("/:id/crashes", deps.AdminBugHandler.ListGroupCrashes)
			}

			// Feature flags (admin)
			flags := protected.Group("/flags")
			{
				flags.GET("", deps.AdminProductHandler.ListFlags)
				flags.POST("", deps.AdminProductHandler.CreateFlag)
				flags.GET("/:id", deps.AdminProductHandler.GetFlag)
				flags.PATCH("/:id", deps.AdminProductHandler.UpdateFlag)
				flags.DELETE("/:id", deps.AdminProductHandler.DeleteFlag)
			}

			// Remote config (admin)
			config := protected.Group("/config")
			{
				config.GET("", deps.AdminProductHandler.ListConfigs)
				config.POST("", deps.AdminProductHandler.CreateConfig)
				config.GET("/:id", deps.AdminProductHandler.GetConfig)
				config.PATCH("/:id", deps.AdminProductHandler.UpdateConfig)
				config.DELETE("/:id", deps.AdminProductHandler.DeleteConfig)
			}

			// App releases (admin)
			releases := protected.Group("/releases")
			{
				releases.GET("", deps.AdminProductHandler.ListReleases)
				releases.POST("", deps.AdminProductHandler.CreateRelease)
				releases.GET("/:id", deps.AdminProductHandler.GetRelease)
				releases.PATCH("/:id", deps.AdminProductHandler.UpdateRelease)
			}

			// Announcements (admin)
			announcements := protected.Group("/announcements")
			{
				announcements.GET("", deps.AdminProductHandler.ListAnnouncements)
				announcements.POST("", deps.AdminProductHandler.CreateAnnouncement)
				announcements.GET("/:id", deps.AdminProductHandler.GetAnnouncement)
				announcements.PATCH("/:id", deps.AdminProductHandler.UpdateAnnouncement)
				announcements.DELETE("/:id", deps.AdminProductHandler.DeleteAnnouncement)
			}

			// Product stats (admin)
			product := protected.Group("/product")
			{
				product.GET("/stats", deps.AdminProductHandler.ProductStats)
			}

			// Tickets (admin)
			adminTickets := protected.Group("/tickets")
			{
				adminTickets.GET("", deps.AdminFeedbackHandler.ListTickets)
				adminTickets.GET("/:id", deps.AdminFeedbackHandler.GetTicket)
				adminTickets.PATCH("/:id", deps.AdminFeedbackHandler.UpdateTicket)
				adminTickets.POST("/:id/messages", deps.AdminFeedbackHandler.AdminReply)
				adminTickets.GET("/:id/stream", deps.AdminFeedbackHandler.StreamTicket)
			}

			// Admin notifications (SSE)
			notifications := protected.Group("/notifications")
			{
				notifications.GET("/stream", deps.AdminFeedbackHandler.StreamNotifications)
			}

			// Feature requests (admin)
			adminFeatures := protected.Group("/features")
			{
				adminFeatures.GET("", deps.AdminFeedbackHandler.ListFeatureRequests)
				adminFeatures.GET("/:id", deps.AdminFeedbackHandler.GetFeatureRequest)
				adminFeatures.PATCH("/:id", deps.AdminFeedbackHandler.UpdateFeatureRequest)
			}

			// Ratings (admin)
			ratings := protected.Group("/ratings")
			{
				ratings.GET("", deps.AdminFeedbackHandler.ListRatings)
				ratings.GET("/stats", deps.AdminFeedbackHandler.RatingStats)
			}

			// AI Assistant (admin)
			adminAssistant := protected.Group("/assistant")
			{
				adminSessions := adminAssistant.Group("/sessions")
				{
					adminSessions.GET("", deps.AdminAssistantHandler.ListSessions)
					adminSessions.GET("/:id", deps.AdminAssistantHandler.GetSession)
				}

				knowledge := adminAssistant.Group("/knowledge")
				{
					knowledge.GET("", deps.AdminAssistantHandler.ListKnowledge)
					knowledge.POST("", deps.AdminAssistantHandler.CreateKnowledge)
					knowledge.GET("/:id", deps.AdminAssistantHandler.GetKnowledge)
					knowledge.PATCH("/:id", deps.AdminAssistantHandler.UpdateKnowledge)
					knowledge.DELETE("/:id", deps.AdminAssistantHandler.DeleteKnowledge)
				}

				adminAssistant.GET("/stats", deps.AdminAssistantHandler.AssistantStats)
			}

			// Feedback stats (admin)
			feedback := protected.Group("/feedback")
			{
				feedback.GET("/stats", deps.AdminFeedbackHandler.FeedbackStats)
			}

			// Analytics (admin)
			analytics := protected.Group("/analytics")
			{
				analytics.GET("/events", deps.AdminAnalyticsHandler.ListEvents)
				analytics.GET("/bootstrap-events", deps.AdminAnalyticsHandler.ListBootstrapEvents)
				analytics.GET("/stats", deps.AdminAnalyticsHandler.Overview)
				analytics.GET("/top-events", deps.AdminAnalyticsHandler.TopEvents)
				analytics.GET("/daily", deps.AdminAnalyticsHandler.DailyStats)
				analytics.GET("/downloads", deps.AdminAnalyticsHandler.DownloadStats)
				analytics.GET("/download-errors/stats", deps.AdminAnalyticsHandler.DownloadErrorStats)
				analytics.GET("/download-errors", deps.AdminAnalyticsHandler.ListDownloadErrors)
			}

			// Premium (admin)
			adminLicenses := protected.Group("/licenses")
			{
				adminLicenses.POST("", deps.AdminPremiumHandler.CreateLicense)
				// One-shot γ-ETL migration endpoint for VidCombo PHP legacy
				// records — preserves the 32-hex license_key verbatim so
				// users who bought via vidcombo.net can use in-app Restore.
				adminLicenses.POST("/import-legacy", deps.AdminPremiumHandler.ImportLegacyLicense)
				adminLicenses.GET("", deps.AdminPremiumHandler.ListLicenses)
				adminLicenses.GET("/:id", deps.AdminPremiumHandler.GetLicense)
				adminLicenses.PATCH("/:id", deps.AdminPremiumHandler.UpdateLicense)
				adminLicenses.GET("/:id/devices", deps.AdminPremiumHandler.ListDevices)
				adminLicenses.DELETE("/:id/devices/:deviceId", deps.AdminPremiumHandler.RemoveDevice)
			}

			adminTransactions := protected.Group("/transactions")
			{
				adminTransactions.GET("/stats", deps.AdminPremiumHandler.TransactionStats)
				adminTransactions.GET("", deps.AdminPremiumHandler.ListTransactionsEnhanced)
				adminTransactions.GET("/:id", deps.AdminPremiumHandler.GetTransaction)
				adminTransactions.POST("/:id/refund", deps.AdminPremiumHandler.RefundTransaction)
			}

			adminSubscriptions := protected.Group("/subscriptions")
			{
				adminSubscriptions.GET("/stats", deps.AdminPremiumHandler.SubscriptionStats)
				adminSubscriptions.GET("/mrr-trend", deps.AdminPremiumHandler.MRRTrend)
				adminSubscriptions.GET("", deps.AdminPremiumHandler.ListSubscriptions)
			}

			adminCustomers := protected.Group("/customers")
			{
				adminCustomers.GET("/stats", deps.AdminPremiumHandler.CustomerStats)
				adminCustomers.GET("", deps.AdminPremiumHandler.ListCustomers)
				adminCustomers.GET("/:email", deps.AdminPremiumHandler.GetCustomer)
			}

			// Invoices
			adminInvoices := protected.Group("/invoices")
			{
				adminInvoices.GET("/stats", deps.AdminPremiumHandler.InvoiceStats)
				adminInvoices.GET("", deps.AdminPremiumHandler.ListInvoices)
				adminInvoices.POST("/audit", deps.AdminPremiumHandler.AuditInvoices)
				adminInvoices.GET("/:id", deps.AdminPremiumHandler.GetInvoice)
			}

			// Finance
			finance := protected.Group("/finance")
			{
				finance.GET("/revenue", deps.AdminPremiumHandler.RevenueReport)
			}

			// Global search
			protected.GET("/search", deps.AdminPremiumHandler.GlobalSearch)

			adminPremium := protected.Group("/premium")
			{
				adminPremium.GET("/stats", deps.AdminPremiumHandler.PremiumStats)
			}

			// Alerts (admin)
			alerts := protected.Group("/alerts")
			{
				alerts.GET("", deps.AdminAlertHandler.ListConfigs)
				alerts.POST("", deps.AdminAlertHandler.CreateConfig)
				alerts.GET("/logs", deps.AdminAlertHandler.ListLogs)
				alerts.GET("/:id", deps.AdminAlertHandler.GetConfig)
				alerts.PATCH("/:id", deps.AdminAlertHandler.UpdateConfig)
				alerts.DELETE("/:id", deps.AdminAlertHandler.DeleteConfig)
				alerts.POST("/:id/test", deps.AdminAlertHandler.TestAlert)
			}

			dashboard := protected.Group("/dashboard")
			{
				dashboard.GET("/comprehensive", deps.AdminDeviceHandler.ComprehensiveStats)
				dashboard.GET("/brand-comparison", deps.AdminDeviceHandler.BrandComparison)
				dashboard.GET("/trends", deps.AdminDeviceHandler.DashboardTrends)
				dashboard.GET("/activity", deps.AdminDeviceHandler.DashboardActivity)
				dashboard.GET("/top-customers", deps.AdminDeviceHandler.DashboardTopCustomers)
			}

			// Audit logs
			if deps.AdminAuditHandler != nil {
				auditLogs := protected.Group("/audit-logs")
				{
					auditLogs.GET("", deps.AdminAuditHandler.ListAuditLogs)
				}
			}

			// Webhook events (admin view)
			webhookEvents := protected.Group("/webhook-events")
			{
				webhookEvents.GET("", deps.AdminPremiumHandler.ListWebhookEvents)
			}

			// System health
			system := protected.Group("/system")
			{
				system.GET("/health", deps.AdminDeviceHandler.SystemHealth)
			}

			// Admin user management
			admins := protected.Group("/admins")
			{
				admins.GET("", deps.AdminDeviceHandler.ListAdmins)
				admins.POST("", deps.AdminDeviceHandler.CreateAdmin)
				admins.PATCH("/:id", deps.AdminDeviceHandler.UpdateAdmin)
				admins.DELETE("/:id", deps.AdminDeviceHandler.DeleteAdmin)
			}

			// API key management (admin)
			apiKeys := protected.Group("/api-keys")
			{
				apiKeys.GET("/device/:deviceId", deps.AdminDeviceHandler.ListApiKeys)
				apiKeys.DELETE("/:id", deps.AdminDeviceHandler.RevokeApiKey)
			}
		}
	}

	// Swagger docs — opt-in via ENABLE_SWAGGER env (default off). Decoupled
	// from GIN_MODE so a production server accidentally running debug mode
	// doesn't auto-leak the API surface.
	if deps.EnableSwagger {
		engine.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))
	}

	// Serve embedded admin SPA at /dashboard-ui
	adminFS, err := web.AdminFS()
	if err != nil {
		logger.Log.Warn().Err(err).Msg("Admin dashboard not available (not built?)")
		return
	}
	spaHandler := newSPAHandler(adminFS)
	engine.GET("/dashboard-ui", spaHandler)
	engine.GET("/dashboard-ui/*filepath", spaHandler)
}

func newSPAHandler(fsys fs.FS) gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.Param("filepath")
		if path == "" || path == "/" {
			path = "index.html"
		} else {
			path = path[1:] // strip leading /
		}

		// Try to serve the file directly
		f, err := fsys.Open(path)
		if err == nil {
			defer f.Close()
			stat, _ := f.Stat()
			if stat != nil && !stat.IsDir() {
				http.ServeContent(c.Writer, c.Request, stat.Name(), stat.ModTime(), f.(io.ReadSeeker))
				return
			}
		}

		// SPA fallback: serve index.html
		f, err = fsys.Open("index.html")
		if err != nil {
			c.String(http.StatusNotFound, "Admin dashboard not found")
			return
		}
		defer f.Close()
		stat, _ := f.Stat()
		http.ServeContent(c.Writer, c.Request, "index.html", stat.ModTime(), f.(io.ReadSeeker))
	}
}
