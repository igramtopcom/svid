// @title SSvid Backend API
// @version 1.0
// @description Backend API for SSvid (SnakeLoader) desktop video downloader application
// @termsOfService http://swagger.io/terms/

// @contact.name API Support
// @contact.email support@ssvid.com

// @license.name Private
// @license.url http://ssvid.com/license

// @host localhost:8080
// @BasePath /

// @securityDefinitions.apikey ApiKeyAuth
// @in header
// @name X-API-Key
// @description Device API Key (format: snk_...)

// @securityDefinitions.apikey BearerAuth
// @in header
// @name Authorization
// @description Admin JWT Token (format: Bearer {token})

package main

import (
	"context"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/google/uuid"

	alerthandler "github.com/snakeloader/backend/internal/alerts/handler"
	alertrepo "github.com/snakeloader/backend/internal/alerts/repository"
	alertsvc "github.com/snakeloader/backend/internal/alerts/service"
	analyticshandler "github.com/snakeloader/backend/internal/analytics/handler"
	analyticsrepo "github.com/snakeloader/backend/internal/analytics/repository"
	analyticssvc "github.com/snakeloader/backend/internal/analytics/service"
	assistanthandler "github.com/snakeloader/backend/internal/assistant/handler"
	assistantrepo "github.com/snakeloader/backend/internal/assistant/repository"
	assistantsvc "github.com/snakeloader/backend/internal/assistant/service"
	bughandler "github.com/snakeloader/backend/internal/bugs/handler"
	bugrepo "github.com/snakeloader/backend/internal/bugs/repository"
	bugsvc "github.com/snakeloader/backend/internal/bugs/service"
	"github.com/snakeloader/backend/internal/config"
	"github.com/snakeloader/backend/internal/database"
	"github.com/snakeloader/backend/internal/jobs"
	feedbackhandler "github.com/snakeloader/backend/internal/feedback/handler"
	feedbackrepo "github.com/snakeloader/backend/internal/feedback/repository"
	feedbacksvc "github.com/snakeloader/backend/internal/feedback/service"
	"github.com/snakeloader/backend/internal/identity/handler"
	"github.com/snakeloader/backend/internal/identity/repository"
	"github.com/snakeloader/backend/internal/identity/service"
	"github.com/snakeloader/backend/internal/middleware"
	"github.com/snakeloader/backend/internal/notifications"
	"github.com/snakeloader/backend/internal/pkg/email"
	"github.com/snakeloader/backend/internal/pkg/gemini"
	"github.com/snakeloader/backend/internal/pkg/jwt"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/pkg/sse"
	premiumhandler "github.com/snakeloader/backend/internal/premium/handler"
	premiumrepo "github.com/snakeloader/backend/internal/premium/repository"
	premiumsvc "github.com/snakeloader/backend/internal/premium/service"
	"github.com/stripe/stripe-go/v81"
	producthandler "github.com/snakeloader/backend/internal/product/handler"
	productrepo "github.com/snakeloader/backend/internal/product/repository"
	productsvc "github.com/snakeloader/backend/internal/product/service"
	"github.com/snakeloader/backend/internal/server"
)

// bugTriageAdapter wraps AutonomousAgent to implement bugsvc.BugTriager interface.
type bugTriageAdapter struct {
	agent *notifications.AutonomousAgent
}

func (a *bugTriageAdapter) AutoTriageBug(bugID uuid.UUID, title, description, steps, os, appVersion string) *bugsvc.BugTriageResult {
	result := a.agent.AutoTriageBug(bugID, title, description, steps, os, appVersion)
	if result == nil {
		return nil
	}
	return &bugsvc.BugTriageResult{
		Priority: result.Priority,
		Category: result.Category,
		Summary:  result.Summary,
	}
}

// ticketAutoResponderAdapter wraps AutonomousAgent to implement feedbacksvc.TicketAutoResponder interface.
type ticketAutoResponderAdapter struct {
	agent *notifications.AutonomousAgent
}

func (a *ticketAutoResponderAdapter) AutoRespondToTicket(ticketID uuid.UUID, subject, message, category string) *feedbacksvc.TicketAutoResponseResult {
	result := a.agent.AutoRespondToTicket(ticketID, subject, message, category)
	if result == nil {
		return nil
	}
	return &feedbacksvc.TicketAutoResponseResult{
		Response:       result.Response,
		Confidence:     result.Confidence,
		ShouldEscalate: result.ShouldEscalate,
	}
}

func main() {
	startTime := time.Now()

	// 1. Initialize logger (early, before config loads)
	logger.Init("debug")
	logger.Log.Info().Msg("Starting SnakeLoader Backend...")

	// 2. Load configuration
	cfg := config.Load()
	logger.Init(cfg.Server.GinMode)
	logger.Log.Info().Str("port", cfg.Server.Port).Str("mode", cfg.Server.GinMode).Msg("Configuration loaded")

	// 3. Connect to PostgreSQL
	db, err := database.NewPostgresDB(cfg.Database, cfg.Server.GinMode)
	if err != nil {
		logger.Log.Fatal().Err(err).Msg("Failed to connect to PostgreSQL")
	}

	// 4. Connect to Redis
	rdb, err := database.NewRedisClient(cfg.Redis)
	if err != nil {
		logger.Log.Warn().Err(err).Msg("Failed to connect to Redis, continuing without cache")
		rdb = nil
	}

	// 5. Run migrations
	if err := database.RunMigrations(db); err != nil {
		logger.Log.Fatal().Err(err).Msg("Failed to run migrations")
	}

	// 6. Seed default admin
	if err := database.SeedAdmin(db, cfg.Admin.Email, cfg.Admin.Password); err != nil {
		logger.Log.Warn().Err(err).Msg("Failed to seed admin")
	}

	// 7. Initialize repositories
	deviceRepo := repository.NewDeviceRepository(db)
	keyRepo := repository.NewApiKeyRepository(db)
	adminRepo := repository.NewAdminRepository(db)
	bugRepo := bugrepo.NewBugRepository(db)
	crashRepo := bugrepo.NewCrashRepository(db)
	crashGroupRepo := bugrepo.NewCrashGroupRepository(db)
	flagRepo := productrepo.NewFeatureFlagRepository(db)
	configRepo := productrepo.NewRemoteConfigRepository(db)
	releaseRepo := productrepo.NewAppReleaseRepository(db)
	annRepo := productrepo.NewAnnouncementRepository(db)
	ticketRepo := feedbackrepo.NewTicketRepository(db)
	featureRepo := feedbackrepo.NewFeatureRequestRepository(db)
	ratingRepo := feedbackrepo.NewRatingRepository(db)
	chatRepo := assistantrepo.NewChatRepository(db)
	knowledgeRepo := assistantrepo.NewKnowledgeRepository(db)
	analyticsRepo := analyticsrepo.NewAnalyticsRepository(db)
	dlErrorRepo := analyticsrepo.NewDownloadErrorRepository(db)
	licenseRepo := premiumrepo.NewLicenseRepository(db)
	txnRepo := premiumrepo.NewTransactionRepository(db)
	webhookEventRepo := premiumrepo.NewWebhookEventRepository(db)
	alertRepo := alertrepo.NewAlertRepository(db)
	auditLogRepo := repository.NewAuditLogRepository(db)

	// 8. Initialize Gemini client (optional)
	var geminiClient *gemini.Client
	if cfg.Gemini.APIKey != "" {
		gc, err := gemini.NewClient(cfg.Gemini.APIKey, cfg.Gemini.Model)
		if err != nil {
			logger.Log.Warn().Err(err).Msg("Failed to initialize Gemini client, AI will use keyword fallback")
		} else {
			geminiClient = gc
			defer gc.Close()
			logger.Log.Info().Str("model", cfg.Gemini.Model).Msg("Gemini AI client initialized")
		}
	} else {
		logger.Log.Info().Msg("Gemini API key not configured, AI will use keyword fallback")
	}

	// 9. Initialize SSE Hub
	sseHub := sse.NewHub()

	// 10. Initialize Stripe API key (once, globally)
	if cfg.Stripe.SecretKey != "" {
		stripe.Key = cfg.Stripe.SecretKey
		logger.Log.Info().Msg("Stripe API key configured")
	}

	// Initialize services
	jwtManager := jwt.NewManager(cfg.JWT.Secret, cfg.JWT.ExpiryHours)
	deviceService := service.NewDeviceService(deviceRepo, keyRepo, &cfg.APIKey)
	adminService := service.NewAdminService(adminRepo, jwtManager)
	bugService := bugsvc.NewBugService(bugRepo, crashRepo, crashGroupRepo)
	productService := productsvc.NewProductService(flagRepo, configRepo, releaseRepo, annRepo)
	feedbackService := feedbacksvc.NewFeedbackService(ticketRepo, featureRepo, ratingRepo, sseHub)
	assistantService := assistantsvc.NewAssistantService(chatRepo, knowledgeRepo, geminiClient, feedbackService)
	analyticsService := analyticssvc.NewAnalyticsService(analyticsRepo, dlErrorRepo)
	analyticsService.SetRedis(rdb)
	stripeSvc := premiumsvc.NewStripeService(&cfg.Stripe, db, licenseRepo, txnRepo, cfg.JWT.Secret)
	cryptoSvc := premiumsvc.NewCryptoService(&cfg.BTCPay, licenseRepo, txnRepo, cfg.JWT.Secret)
	invoiceRepo := premiumrepo.NewInvoiceRepository(db)
	premiumService := premiumsvc.NewPremiumService(licenseRepo, txnRepo, cfg.JWT.Secret, stripeSvc, cryptoSvc)
	premiumService.SetInvoiceRepo(invoiceRepo)
	stripeSvc.SetPremiumService(premiumService)  // break circular init for deduped license creation
	cryptoSvc.SetPremiumService(premiumService)  // break circular init for deduped crypto license creation

	// 10a. Initialize alert service
	alertService := alertsvc.NewAlertService(alertRepo, nil, cfg.Telegram.BotToken) // email set below

	// 10b. Initialize email service
	emailService := email.NewService(cfg.Email)
	if emailService.IsConfigured() {
		logger.Log.Info().Msg("Email service initialized (SMTP configured)")
	} else {
		logger.Log.Info().Msg("Email service in stub mode (SMTP not configured)")
	}
	// Wire email service into alert service (circular init order)
	alertService = alertsvc.NewAlertService(alertRepo, emailService, cfg.Telegram.BotToken)

	// 10c. Initialize Autonomous Operations System (S1 + S2)
	telegramNotifier := notifications.NewTelegramNotifier(cfg.Telegram.BotToken, cfg.Telegram.AdminChatID)
	kbAdapter := notifications.NewKBAdapter(knowledgeRepo)
	aiAgent := notifications.NewAutonomousAgent(geminiClient, telegramNotifier, kbAdapter)

	// Wire notifiers into services (post-construction to avoid circular deps)
	if rdb != nil {
		deviceService.SetRedis(rdb)
	}
	if telegramNotifier != nil {
		deviceService.SetNotifier(telegramNotifier)
		bugService.SetNotifier(telegramNotifier)
		feedbackService.SetNotifier(telegramNotifier)
	}

	if aiAgent != nil {
		bugService.SetTriager(&bugTriageAdapter{agent: aiAgent})
		feedbackService.SetAutoResponder(&ticketAutoResponderAdapter{agent: aiAgent})
	}

	// 11. Initialize handlers
	deviceHandler := handler.NewDeviceHandler(deviceService)
	adminAuthHandler := handler.NewAdminAuthHandler(adminService, rdb)
	adminDeviceHandler := handler.NewAdminDeviceHandler(deviceService)
	timelineService := service.NewDeviceTimelineService(db)
	adminDeviceHandler.SetTimelineService(timelineService)
	comprehensiveStatsService := service.NewComprehensiveStatsService(db)
	adminDeviceHandler.SetComprehensiveService(comprehensiveStatsService)
	activityFeedService := service.NewActivityFeedService(db)
	adminDeviceHandler.SetActivityFeedService(activityFeedService)
	topCustomersService := service.NewTopCustomersService(db)
	adminDeviceHandler.SetTopCustomersService(topCustomersService)
	adminDeviceHandler.SetAdminRepo(adminRepo)
	adminDeviceHandler.SetKeyRepo(keyRepo)
	adminDeviceHandler.SetDB(db)
	bugHandler := bughandler.NewBugHandler(bugService)
	adminBugHandler := bughandler.NewAdminBugHandler(bugService)
	productHandler := producthandler.NewProductHandler(productService)
	adminProductHandler := producthandler.NewAdminProductHandler(productService)
	var ciReleaseHandler *producthandler.CIReleaseHandler
	if cfg.CI.ReleaseSecret != "" {
		ciReleaseHandler = producthandler.NewCIReleaseHandler(productService, cfg.CI.ReleaseSecret)
		logger.Log.Info().Msg("CI release webhook enabled")
	}
	fbHandler := feedbackhandler.NewFeedbackHandler(feedbackService, sseHub)
	adminFbHandler := feedbackhandler.NewAdminFeedbackHandler(feedbackService, sseHub)
	aiHandler := assistanthandler.NewAssistantHandler(assistantService)
	adminAiHandler := assistanthandler.NewAdminAssistantHandler(assistantService)
	analyticsHandler := analyticshandler.NewAnalyticsHandler(analyticsService)
	adminAnalyticsHandler := analyticshandler.NewAdminAnalyticsHandler(analyticsService)
	premiumHandler := premiumhandler.NewPremiumHandler(premiumService, cfg.BTCPay.APIKey != "")
	// W1.2/W1.3 magic-link wiring. MagicLinkService needs the license repo,
	// email sender, Redis (for SETNX single-use + per-email rate limit), and
	// the magic-link URL config. We pass it via setter so the constructor
	// signature stays additive-only (legacy unit tests still compile).
	if rdb != nil && emailService != nil {
		magicLinkSvc := premiumsvc.NewMagicLinkService(
			licenseRepo,
			emailService,
			rdb,
			cfg.MagicLink,
			cfg.JWT.Secret,
		)
		premiumHandler.SetMagicLinkService(magicLinkSvc)
		logger.Log.Info().
			Str("base_ssvid", cfg.MagicLink.BaseURLSSvid).
			Str("base_vidcombo", cfg.MagicLink.BaseURLVidCombo).
			Int("ttl_min", cfg.MagicLink.TTLMinutes).
			Msg("Magic link service wired")
	} else {
		logger.Log.Warn().Msg("Magic link service NOT wired — Redis or email unavailable; web-restore-email / web-portal-email / redeem will return 503")
	}
	adminPremiumHandler := premiumhandler.NewAdminPremiumHandler(premiumService)
	adminPremiumHandler.SetWebhookEventRepo(webhookEventRepo)
	webhookHandler := premiumhandler.NewWebhookHandler(&cfg.Stripe, premiumService, webhookEventRepo, db)
	adminAlertHandler := alerthandler.NewAdminAlertHandler(alertService)
	adminAuditHandler := handler.NewAdminAuditHandler(auditLogRepo)

	// 12. Initialize middleware
	authMiddleware := middleware.NewAuthMiddleware(keyRepo, rdb)
	adminAuthMiddleware := middleware.NewAdminAuthMiddleware(jwtManager, adminRepo)
	deviceHandler.SetAuthMiddleware(authMiddleware)

	// Wire API key cache invalidation: when keys are revoked or device status changes,
	// the Redis auth cache is cleared so stale entries don't bypass auth checks.
	deviceService.SetCacheInvalidator(authMiddleware.InvalidateCache)

	// Always construct the RateLimiter, even when rdb is nil. The middleware
	// itself handles a nil Redis client: global middleware fails open (allows
	// the request) and strict middleware fails closed (returns 503). If we
	// skipped construction here, the strict middleware would never even attach
	// to /register / /web-checkout / /restore — defeating the whole point.
	rateLimiter := middleware.NewRateLimiter(rdb, cfg.RateLimit.Requests, cfg.RateLimit.WindowSeconds)
	if rdb == nil {
		logger.Log.Warn().Msg("Rate limiter constructed with nil Redis — strict endpoints will fail-CLOSED with 503 until Redis is reachable")
	}

	// 13. Create server
	engine := server.NewWithOptions(cfg.Server.GinMode, rateLimiter, cfg.Server.TrustedPlatform)

	// 14. Register routes
	server.RegisterRoutes(engine, server.RouterDeps{
		DB:                   db,
		DeviceHandler:        deviceHandler,
		AdminAuthHandler:     adminAuthHandler,
		AdminDeviceHandler:   adminDeviceHandler,
		BugHandler:           bugHandler,
		AdminBugHandler:      adminBugHandler,
		ProductHandler:       productHandler,
		AdminProductHandler:  adminProductHandler,
		CIReleaseHandler:     ciReleaseHandler,
		FeedbackHandler:       fbHandler,
		AdminFeedbackHandler:  adminFbHandler,
		AssistantHandler:       aiHandler,
		AdminAssistantHandler:  adminAiHandler,
		AnalyticsHandler:       analyticsHandler,
		AdminAnalyticsHandler:  adminAnalyticsHandler,
		PremiumHandler:         premiumHandler,
		AdminPremiumHandler:    adminPremiumHandler,
		WebhookHandler:         webhookHandler,
		AdminAlertHandler:      adminAlertHandler,
		AdminAuditHandler:      adminAuditHandler,
		AuditLogRepo:           auditLogRepo,
		AuthMiddleware:         authMiddleware,
		AdminAuthMW:            adminAuthMiddleware,
		RateLimiter:            rateLimiter,
		EnableSwagger:          cfg.Server.EnableSwagger,
	}, startTime)

	// 15. Start background job scheduler
	jobScheduler := jobs.NewScheduler(db, emailService, alertService, telegramNotifier)
	jobScheduler.Start()

	// 16. Start HTTP server with graceful shutdown.
	// ReadHeaderTimeout caps how long the server waits for the request line +
	// headers, defending against slow-loris (open socket, drip headers). Must
	// be tighter than ReadTimeout to actually fire before whole-request timeout.
	srv := &http.Server{
		Addr:              ":" + cfg.Server.Port,
		Handler:           engine,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    1 << 20, // 1 MB — generous but bounded
	}

	go func() {
		logger.Log.Info().Str("addr", srv.Addr).Msg("Server started")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Log.Fatal().Err(err).Msg("Server failed")
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Log.Info().Msg("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		logger.Log.Fatal().Err(err).Msg("Server forced to shutdown")
	}

	// Close database connection
	sqlDB, _ := db.DB()
	if sqlDB != nil {
		sqlDB.Close()
	}

	// Close Redis
	if rdb != nil {
		rdb.Close()
	}

	// Stop background jobs
	jobScheduler.Stop()

	logger.Log.Info().Msg("Server stopped")
}
