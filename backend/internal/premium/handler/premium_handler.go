package handler

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/middleware"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"github.com/snakeloader/backend/internal/pkg/validator"
	"github.com/snakeloader/backend/internal/premium/dto"
	"github.com/snakeloader/backend/internal/premium/service"
	"github.com/snakeloader/backend/internal/response"
	"gorm.io/gorm"
)

type PremiumHandler struct {
	service       *service.PremiumService
	cryptoEnabled bool
	magicLink     *service.MagicLinkService // nil when MagicLinkService isn't wired (legacy tests)
}

func NewPremiumHandler(svc *service.PremiumService, cryptoEnabled bool) *PremiumHandler {
	return &PremiumHandler{service: svc, cryptoEnabled: cryptoEnabled}
}

// SetMagicLinkService wires the W1.2/W1.3 magic-link issuer/redeemer. Optional
// dependency — when nil, the new magic-link endpoints return 503 to make
// misconfiguration loud instead of silently dropping the email send.
func (h *PremiumHandler) SetMagicLinkService(ml *service.MagicLinkService) {
	h.magicLink = ml
}

// GetPricingPlans godoc
// @Summary Get pricing plans
// @Description Get all available premium billing plans with pricing info (public, no auth required).
// @Description Pass ?brand=vidcombo to get VidCombo-specific plans; defaults to ssvid.
// @Tags Premium
// @Produce json
// @Param brand query string false "Brand name (ssvid or vidcombo)" default(ssvid)
// @Success 200 {object} response.Response{data=[]dto.PricingPlanResponse} "Pricing plans"
// @Router /api/v1/premium/plans [get]
func (h *PremiumHandler) GetPricingPlans(c *gin.Context) {
	brand := c.DefaultQuery("brand", "ssvid")

	// Also check device brand from middleware (authenticated requests)
	if brand == "ssvid" {
		if deviceBrand, exists := c.Get(middleware.DeviceBrandKey); exists {
			if b, ok := deviceBrand.(string); ok && b != "" {
				brand = b
			}
		}
	}

	type cycleInfo struct {
		cycle       string
		displayName string
		interval    string
	}

	var cycles []cycleInfo
	if brand == "vidcombo" {
		cycles = []cycleInfo{
			{"monthly", "Monthly", "month"},
			{"semiannual", "6 Months", "six_months"},
			{"yearly", "Yearly", "year"},
		}
	} else {
		cycles = []cycleInfo{
			{"monthly", "Monthly", "month"},
			{"yearly", "Yearly", "year"},
			{"lifetime", "Lifetime", "one_time"},
		}
	}

	plans := make([]dto.PricingPlanResponse, len(cycles))
	for i, cy := range cycles {
		plans[i] = dto.PricingPlanResponse{
			BillingCycle: cy.cycle,
			AmountCents:  service.AmountCentsForBillingCycle(cy.cycle, brand),
			Currency:     "usd",
			Interval:     cy.interval,
			MaxDevices:   service.MaxDevicesForPlan(cy.cycle),
			IsLifetime:   service.IsLifetimePlan(cy.cycle),
			DisplayName:  cy.displayName,
		}
	}

	response.Success(c, http.StatusOK, dto.PricingPlansResponse{
		Plans:         plans,
		CryptoEnabled: h.cryptoEnabled,
	})
}

// RemoveDevice godoc
// @Summary Remove a device from license
// @Description Remove a device registration to free up the 3-device limit
// @Tags Premium
// @Accept json
// @Produce json
// @Param deviceId path string true "Target device UUID to remove"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response "Device removed"
// @Failure 400 {object} response.Response "Invalid device ID"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "License or device not found"
// @Router /api/v1/premium/devices/{deviceId} [delete]
func (h *PremiumHandler) RemoveDevice(c *gin.Context) {
	currentDeviceID, exists := c.Get(middleware.DeviceIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "Device not authenticated")
		return
	}

	targetDeviceID, err := uuid.Parse(c.Param("deviceId"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_DEVICE_ID", "Invalid device ID format")
		return
	}

	err = h.service.RemoveDevice(currentDeviceID.(uuid.UUID), targetDeviceID)
	if err != nil {
		if errors.Is(err, service.ErrLicenseNotFound) {
			response.Error(c, http.StatusNotFound, "LICENSE_NOT_FOUND", "No active license found for this device")
			return
		}
		if errors.Is(err, service.ErrDeviceNotFound) {
			response.Error(c, http.StatusNotFound, "DEVICE_NOT_FOUND", "Device not found on this license")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to remove device")
		return
	}

	response.Success(c, http.StatusOK, gin.H{"success": true})
}

// WebStripeCheckout godoc
// @Summary Create web Stripe Checkout session
// @Description Create a Stripe Checkout session from the public website (no device auth required).
// @Description User receives a license key after payment and activates it in the app.
// @Tags Premium
// @Accept json
// @Produce json
// @Param request body dto.WebCheckoutRequest true "Checkout data"
// @Success 200 {object} response.Response{data=dto.CheckoutResponse} "Checkout session created"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 503 {object} response.Response "Payment not configured"
// @Router /api/v1/premium/stripe/web-checkout [post]
func (h *PremiumHandler) WebStripeCheckout(c *gin.Context) {
	var req dto.WebCheckoutRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	stripeSvc := h.service.GetStripeService()
	result, err := stripeSvc.CreateWebCheckoutSession(req)
	if err != nil {
		if errors.Is(err, service.ErrPaymentNotConfigured) {
			response.Error(c, http.StatusServiceUnavailable, "PAYMENT_NOT_CONFIGURED", "Stripe is not configured")
			return
		}
		if errors.Is(err, service.ErrInvalidBillingCycle) {
			response.Error(c, http.StatusBadRequest, "INVALID_BILLING_CYCLE", "Invalid billing cycle")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to create checkout session")
		return
	}

	response.Success(c, http.StatusOK, result)
}

// WebStripeVerify godoc
// @Summary Verify web Stripe payment
// @Description Check payment status and retrieve license key for a web checkout session (no device auth).
// @Tags Premium
// @Produce json
// @Param session_id query string true "Stripe session ID"
// @Success 200 {object} response.Response{data=dto.PaymentResultResponse} "Payment status"
// @Failure 400 {object} response.Response "Missing session ID"
// @Failure 404 {object} response.Response "Session not found"
// @Failure 503 {object} response.Response "Payment not configured"
// @Router /api/v1/premium/stripe/web-verify [get]
func (h *PremiumHandler) WebStripeVerify(c *gin.Context) {
	sessionID := c.Query("session_id")
	if sessionID == "" {
		response.Error(c, http.StatusBadRequest, "MISSING_SESSION_ID", "session_id query parameter is required")
		return
	}

	stripeSvc := h.service.GetStripeService()
	result, err := stripeSvc.WebVerifyPayment(sessionID)
	if err != nil {
		if errors.Is(err, service.ErrPaymentNotConfigured) {
			response.Error(c, http.StatusServiceUnavailable, "PAYMENT_NOT_CONFIGURED", "Stripe is not configured")
			return
		}
		response.Error(c, http.StatusNotFound, "SESSION_NOT_FOUND", "Checkout session not found")
		return
	}

	response.Success(c, http.StatusOK, result)
}

// StripeCheckout godoc
// @Summary Create Stripe Checkout session
// @Description Create a new Stripe Checkout session for premium subscription
// @Tags Premium
// @Accept json
// @Produce json
// @Param request body dto.CheckoutRequest true "Checkout data"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=dto.CheckoutResponse} "Checkout session created"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 409 {object} response.Response "Duplicate payment"
// @Failure 503 {object} response.Response "Payment not configured"
// @Router /api/v1/premium/stripe/checkout [post]
func (h *PremiumHandler) StripeCheckout(c *gin.Context) {
	deviceID, exists := c.Get(middleware.DeviceIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "Device not authenticated")
		return
	}

	// Resolve brand from authenticated device
	brand := "ssvid"
	if deviceBrand, ok := c.Get(middleware.DeviceBrandKey); ok {
		if b, ok := deviceBrand.(string); ok && b != "" {
			brand = b
		}
	}

	var req dto.CheckoutRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	stripeSvc := h.service.GetStripeService()
	result, err := stripeSvc.CreateCheckoutSession(deviceID.(uuid.UUID), req, brand)
	if err != nil {
		if errors.Is(err, service.ErrPaymentNotConfigured) {
			response.Error(c, http.StatusServiceUnavailable, "PAYMENT_NOT_CONFIGURED", "Stripe is not configured")
			return
		}
		if errors.Is(err, service.ErrDuplicatePayment) {
			response.Error(c, http.StatusConflict, "DUPLICATE_PAYMENT", "Payment with this idempotency key already exists")
			return
		}
		if errors.Is(err, service.ErrInvalidBillingCycle) {
			response.Error(c, http.StatusBadRequest, "INVALID_BILLING_CYCLE", "Invalid billing cycle")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to create checkout session")
		return
	}

	response.Success(c, http.StatusOK, result)
}

// StripeVerify godoc
// @Summary Verify Stripe payment status
// @Description Check the status of a Stripe Checkout session
// @Tags Premium
// @Accept json
// @Produce json
// @Param sessionId query string true "Stripe session ID"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=dto.PaymentResultResponse} "Payment status"
// @Failure 400 {object} response.Response "Missing session ID"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Session not found"
// @Failure 503 {object} response.Response "Payment not configured"
// @Router /api/v1/premium/stripe/verify [get]
func (h *PremiumHandler) StripeVerify(c *gin.Context) {
	deviceID, exists := c.Get(middleware.DeviceIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "Device not authenticated")
		return
	}

	sessionID := c.Query("sessionId")
	if sessionID == "" {
		response.Error(c, http.StatusBadRequest, "MISSING_SESSION_ID", "sessionId query parameter is required")
		return
	}

	stripeSvc := h.service.GetStripeService()
	result, err := stripeSvc.VerifyPayment(sessionID, deviceID.(uuid.UUID))
	if err != nil {
		if errors.Is(err, service.ErrPaymentNotConfigured) {
			response.Error(c, http.StatusServiceUnavailable, "PAYMENT_NOT_CONFIGURED", "Stripe is not configured")
			return
		}
		response.Error(c, http.StatusNotFound, "SESSION_NOT_FOUND", "Checkout session not found")
		return
	}

	response.Success(c, http.StatusOK, result)
}

// StripeCancel godoc
// @Summary Cancel Stripe subscription
// @Description Cancel auto-renewal for a Stripe subscription
// @Tags Premium
// @Accept json
// @Produce json
// @Param request body dto.CancelRequest true "Cancel data"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response "Subscription cancelled"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "License not found"
// @Failure 409 {object} response.Response "Already cancelled"
// @Failure 503 {object} response.Response "Payment not configured"
// @Router /api/v1/premium/stripe/cancel [post]
func (h *PremiumHandler) StripeCancel(c *gin.Context) {
	deviceID, exists := c.Get(middleware.DeviceIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "Device not authenticated")
		return
	}

	var req dto.CancelRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	stripeSvc := h.service.GetStripeService()
	err := stripeSvc.CancelSubscription(req.LicenseKey, deviceID.(uuid.UUID))
	if err != nil {
		if errors.Is(err, service.ErrPaymentNotConfigured) {
			response.Error(c, http.StatusServiceUnavailable, "PAYMENT_NOT_CONFIGURED", "Stripe is not configured")
			return
		}
		if errors.Is(err, service.ErrLicenseNotFound) {
			response.Error(c, http.StatusNotFound, "LICENSE_NOT_FOUND", "License not found")
			return
		}
		if errors.Is(err, service.ErrAlreadyCancelled) {
			response.Error(c, http.StatusConflict, "ALREADY_CANCELLED", "Subscription is already cancelled")
			return
		}
		response.Error(c, http.StatusInternalServerError, "STRIPE_ERROR", "Failed to cancel subscription")
		return
	}

	response.Success(c, http.StatusOK, gin.H{"success": true})
}

// StripePortal godoc
// @Summary Open Stripe Billing Portal
// @Description Create a Stripe Billing Portal session. The portal allows users to change
// @Description their plan, update payment method, view invoices, and cancel their subscription.
// @Tags Premium
// @Produce json
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=dto.PortalSessionResponse} "Portal URL"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "No Stripe customer (crypto/manual/PHP license)"
// @Failure 503 {object} response.Response "Stripe not configured"
// @Router /api/v1/premium/stripe/portal [post]
func (h *PremiumHandler) StripePortal(c *gin.Context) {
	deviceID, exists := c.Get(middleware.DeviceIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "Device not authenticated")
		return
	}

	brand := "ssvid"
	if deviceBrand, exists := c.Get(middleware.DeviceBrandKey); exists {
		if b, ok := deviceBrand.(string); ok && b != "" {
			brand = b
		}
	}

	stripeSvc := h.service.GetStripeService()
	resp, err := stripeSvc.CreatePortalSession(deviceID.(uuid.UUID), brand)
	if err != nil {
		if errors.Is(err, service.ErrPaymentNotConfigured) {
			response.Error(c, http.StatusServiceUnavailable, "PAYMENT_NOT_CONFIGURED", "Stripe is not configured")
			return
		}
		if errors.Is(err, service.ErrLicenseNotFound) {
			response.Error(c, http.StatusNotFound, "LICENSE_NOT_FOUND", "No active license found")
			return
		}
		if errors.Is(err, service.ErrNoStripeCustomer) {
			response.Error(c, http.StatusNotFound, "PORTAL_NOT_AVAILABLE", "Billing portal is not available for this license type")
			return
		}
		response.Error(c, http.StatusInternalServerError, "STRIPE_ERROR", "Failed to create portal session")
		return
	}

	response.Success(c, http.StatusOK, resp)
}

// CryptoInvoice godoc
// @Summary Create crypto invoice
// @Description Create a BTCPay crypto invoice for premium subscription
// @Tags Premium
// @Accept json
// @Produce json
// @Param request body dto.CryptoInvoiceRequest true "Invoice data"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=dto.CryptoInvoiceResponse} "Invoice created"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 409 {object} response.Response "Duplicate payment"
// @Failure 503 {object} response.Response "Payment not configured"
// @Router /api/v1/premium/crypto/invoice [post]
func (h *PremiumHandler) CryptoInvoice(c *gin.Context) {
	deviceID, exists := c.Get(middleware.DeviceIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "Device not authenticated")
		return
	}

	brand := "ssvid"
	if deviceBrand, exists := c.Get(middleware.DeviceBrandKey); exists {
		if b, ok := deviceBrand.(string); ok && b != "" {
			brand = b
		}
	}

	var req dto.CryptoInvoiceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	cryptoSvc := h.service.GetCryptoService()
	result, err := cryptoSvc.CreateInvoice(deviceID.(uuid.UUID), brand, req)
	if err != nil {
		if errors.Is(err, service.ErrCryptoNotConfigured) {
			response.Error(c, http.StatusServiceUnavailable, "PAYMENT_NOT_CONFIGURED", "Crypto payments are not configured")
			return
		}
		if errors.Is(err, service.ErrDuplicatePayment) {
			response.Error(c, http.StatusConflict, "DUPLICATE_PAYMENT", "Payment with this idempotency key already exists")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to create crypto invoice")
		return
	}

	response.Success(c, http.StatusOK, result)
}

// CryptoStatus godoc
// @Summary Check crypto payment status
// @Description Check the status of a BTCPay crypto invoice
// @Tags Premium
// @Accept json
// @Produce json
// @Param invoiceId query string true "BTCPay invoice ID"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=dto.PaymentResultResponse} "Invoice status"
// @Failure 400 {object} response.Response "Missing invoice ID"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Invoice not found"
// @Failure 503 {object} response.Response "Payment not configured"
// @Router /api/v1/premium/crypto/status [get]
func (h *PremiumHandler) CryptoStatus(c *gin.Context) {
	deviceID, exists := c.Get(middleware.DeviceIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "Device not authenticated")
		return
	}

	invoiceID := c.Query("invoiceId")
	if invoiceID == "" {
		response.Error(c, http.StatusBadRequest, "MISSING_INVOICE_ID", "invoiceId query parameter is required")
		return
	}

	cryptoSvc := h.service.GetCryptoService()
	result, err := cryptoSvc.CheckStatus(invoiceID, deviceID.(uuid.UUID))
	if err != nil {
		if errors.Is(err, service.ErrCryptoNotConfigured) {
			response.Error(c, http.StatusServiceUnavailable, "PAYMENT_NOT_CONFIGURED", "Crypto payments are not configured")
			return
		}
		response.Error(c, http.StatusNotFound, "INVOICE_NOT_FOUND", "Invoice not found")
		return
	}

	response.Success(c, http.StatusOK, result)
}

// LicenseVerify godoc
// @Summary Verify license key
// @Description Verify a license key and register device if within limit
// @Tags Premium
// @Accept json
// @Produce json
// @Param key query string true "License key (SSVID-XXXX-... or VIDCOMBO-XXXX-...)"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=dto.LicenseVerifyResponse} "License status"
// @Failure 400 {object} response.Response "Missing license key"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Invalid license key"
// @Failure 403 {object} response.Response "Device limit exceeded"
// @Failure 410 {object} response.Response "License expired"
// @Router /api/v1/premium/licenses/verify [get]
func (h *PremiumHandler) LicenseVerify(c *gin.Context) {
	deviceID, exists := c.Get(middleware.DeviceIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "Device not authenticated")
		return
	}

	// Accept key from header (preferred), body, or query param (deprecated — logged by proxies)
	key := c.GetHeader("X-License-Key")
	if key == "" {
		// Fallback: JSON body
		var body struct {
			Key string `json:"key"`
		}
		if err := c.ShouldBindJSON(&body); err == nil && body.Key != "" {
			key = body.Key
		}
	}
	if key == "" {
		// Legacy fallback: query param (backward-compatible with older clients)
		key = c.Query("key")
	}
	if key == "" {
		response.Error(c, http.StatusBadRequest, "MISSING_LICENSE_KEY", "License key is required (X-License-Key header or JSON body)")
		return
	}

	result, err := h.service.VerifyLicense(key, deviceID.(uuid.UUID))
	if err != nil {
		if errors.Is(err, service.ErrInvalidLicenseKey) {
			response.Error(c, http.StatusNotFound, "INVALID_LICENSE_KEY", "License key not found")
			return
		}
		if errors.Is(err, service.ErrDeviceLimitReached) {
			result.VerifiedAt = time.Now().UTC().Format(time.RFC3339)
			result.Reason = "device_limit_exceeded"
			response.Success(c, http.StatusForbidden, result)
			return
		}
		if errors.Is(err, service.ErrLicenseExpired) {
			result.VerifiedAt = time.Now().UTC().Format(time.RFC3339)
			result.Reason = "expired"
			response.Success(c, http.StatusOK, result)
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to verify license")
		return
	}

	// Set VerifiedAt for all successful verifications
	result.VerifiedAt = time.Now().UTC().Format(time.RFC3339)

	// If license is technically valid but tier is free or revoked
	if !result.IsValid && result.Tier == "free" {
		result.Reason = "revoked"
	}

	response.Success(c, http.StatusOK, result)
}

// MyTransactions godoc
// @Summary Get my transactions
// @Description Get paginated list of transactions for the authenticated device
// @Tags Premium
// @Accept json
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=response.PaginatedData} "Success"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal error"
// @Router /api/v1/premium/transactions [get]
func (h *PremiumHandler) MyTransactions(c *gin.Context) {
	deviceID, exists := c.Get(middleware.DeviceIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "Device not authenticated")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)

	txns, total, err := h.service.GetMyTransactions(deviceID.(uuid.UUID), page, perPage)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list transactions")
		return
	}

	response.Paginated(c, txns, total, page, perPage)
}

// LicenseInfo godoc
// @Summary Get license info
// @Description Get the active license information for the authenticated device
// @Tags Premium
// @Accept json
// @Produce json
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=dto.LicenseInfoResponse} "License info"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "No active license"
// @Failure 500 {object} response.Response "Internal error"
// @Router /api/v1/premium/license [get]
func (h *PremiumHandler) LicenseInfo(c *gin.Context) {
	deviceID, exists := c.Get(middleware.DeviceIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "Device not authenticated")
		return
	}

	info, err := h.service.GetLicenseInfo(deviceID.(uuid.UUID))
	if err != nil {
		if errors.Is(err, service.ErrLicenseNotFound) {
			response.Error(c, http.StatusNotFound, "LICENSE_NOT_FOUND", "No active license found for this device")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get license info")
		return
	}

	response.Success(c, http.StatusOK, info)
}

// ListDevices godoc
// @Summary List devices on license
// @Description Get all devices registered to the license associated with the authenticated device
// @Tags Premium
// @Accept json
// @Produce json
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=[]dto.LicenseDeviceResponse} "Device list"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "No active license"
// @Failure 500 {object} response.Response "Internal error"
// @Router /api/v1/premium/devices [get]
func (h *PremiumHandler) ListDevices(c *gin.Context) {
	deviceID, exists := c.Get(middleware.DeviceIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "Device not authenticated")
		return
	}

	devices, err := h.service.GetMyDevices(deviceID.(uuid.UUID))
	if err != nil {
		if errors.Is(err, service.ErrLicenseNotFound) {
			response.Error(c, http.StatusNotFound, "LICENSE_NOT_FOUND", "No active license found for this device")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list devices")
		return
	}

	response.Success(c, http.StatusOK, devices)
}

// RestoreLicense godoc
// @Summary Restore license by email
// @Description Find and return an active license key associated with the given email.
// @Description If device_id is provided, also verifies the device was registered on the license.
// @Tags Premium
// @Accept json
// @Produce json
// @Param request body dto.RestoreRequest true "Email (required) and device ID (optional)"
// @Security ApiKeyAuth
// @Success 200 {object} response.Response{data=dto.RestoreResponse} "License found"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 404 {object} response.Response "No active license found"
// @Failure 500 {object} response.Response "Internal error"
// @Router /api/v1/premium/restore [post]
func (h *PremiumHandler) RestoreLicense(c *gin.Context) {
	var req dto.RestoreRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	// W1.2/W1.3: device_id MUST come from the authenticated context, not the
	// request body. Without this gate, any valid API key could pass an empty
	// device_id and recover any license by email — a complete email-only
	// enumeration leak through an "authenticated" route. The middleware
	// always sets DeviceIDKey for X-API-Key requests; if not present the
	// route isn't actually authenticated and we return 401 below.
	deviceID := uuid.Nil
	if v, ok := c.Get(middleware.DeviceIDKey); ok {
		if parsed, parseOk := v.(uuid.UUID); parseOk {
			deviceID = parsed
		}
	}
	if deviceID == uuid.Nil {
		// No authenticated device → don't accept the body field as a
		// substitute. Return 401, NOT 404, to make middleware misconfig loud.
		response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "Device not authenticated")
		return
	}

	brand := ""
	if deviceBrand, ok := c.Get(middleware.DeviceBrandKey); ok {
		if b, bOk := deviceBrand.(string); bOk {
			brand = b
		}
	}

	result, err := h.service.RestoreLicense(service.NormalizeEmail(req.Email), brand, deviceID)
	if err != nil {
		if errors.Is(err, service.ErrLicenseNotFound) {
			response.Error(c, http.StatusNotFound, "LICENSE_NOT_FOUND", "No active license found for this email")
			return
		}
		if errors.Is(err, service.ErrDeviceLimitReached) {
			response.Error(c, http.StatusForbidden, "DEVICE_LIMIT_REACHED", "Device limit reached for this license")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to restore license")
		return
	}

	response.Success(c, http.StatusOK, result)
}

// WebRestoreLicense godoc
// @Summary Restore license by email (public, no auth) — magic-link issuance
// @Description W1.2/W1.3: this endpoint NO LONGER returns the license key
// @Description directly. It issues a single-use email magic link and always
// @Description responds {"sent": true}. The website must consume the magic
// @Description link (via /premium/redeem) to get the actual license key.
// @Description Alias of /premium/web-restore-email so existing landing-page
// @Description code paths get the secure flow without a URL change.
// @Tags Premium
// @Accept json
// @Produce json
// @Param request body dto.MagicLinkRequest true "Email"
// @Success 200 {object} response.Response "Issued"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 503 {object} response.Response "Magic link service not configured"
// @Router /api/v1/premium/web-restore [post]
func (h *PremiumHandler) WebRestoreLicense(c *gin.Context) {
	// Backward-compat alias: the OLD response shape returned {license_key, ...}.
	// Existing website JS that reads data.license_key will see undefined — by
	// design, since the endpoint must NOT leak the secret. Website is updated
	// to read data.sent and to fetch the key via /premium/redeem.
	h.issueMagicLink(c, service.ScopeRestore)
}

// WebRestoreMagicLink godoc
// @Summary Issue magic-link restore email (W1.2/W1.3, public, no auth)
// @Description Always responds {"sent": true} regardless of whether the email
// @Description matches an active license — enumeration resistance is non-negotiable
// @Description on this public route. The actual email send happens off the request
// @Description path so response timing doesn't leak whether the email matched.
// @Tags Premium
// @Accept json
// @Produce json
// @Param request body dto.MagicLinkRequest true "Email"
// @Success 200 {object} response.Response "Issued (always; do not infer existence)"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 503 {object} response.Response "Magic link service not configured"
// @Router /api/v1/premium/web-restore-email [post]
func (h *PremiumHandler) WebRestoreMagicLink(c *gin.Context) {
	h.issueMagicLink(c, service.ScopeRestore)
}

// WebPortalMagicLink godoc
// @Summary Issue magic-link portal email (W1.2/W1.3, public, no auth)
// @Description Same generic response shape as web-restore-email; the link in
// @Description the email opens a single-use Stripe Billing Portal session.
// @Tags Premium
// @Accept json
// @Produce json
// @Param request body dto.MagicLinkRequest true "Email"
// @Success 200 {object} response.Response "Issued"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 503 {object} response.Response "Magic link service not configured"
// @Router /api/v1/premium/web-portal-email [post]
func (h *PremiumHandler) WebPortalMagicLink(c *gin.Context) {
	h.issueMagicLink(c, service.ScopePortal)
}

func (h *PremiumHandler) issueMagicLink(c *gin.Context, scope service.MagicLinkScope) {
	if h.magicLink == nil {
		response.Error(c, http.StatusServiceUnavailable, "MAGIC_LINK_NOT_CONFIGURED", "Magic link service not available")
		return
	}
	var req dto.MagicLinkRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}
	// Fire-and-forget on a background goroutine so SMTP/Stripe latency does
	// NOT bleed into the response time. The handler must return the same
	// response in the same time whether or not an email matched a license.
	// Capture only primitive values into the goroutine; do not hold c.
	//
	// Important: use a fresh context.Background() with a bounded timeout —
	// `c.Request.Context()` is canceled the instant net/http finishes the
	// response, which is BEFORE this goroutine starts the lookup. Plumbing
	// the request context in would silently cancel every async send.
	go func(scope service.MagicLinkScope, email string) {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		var err error
		switch scope {
		case service.ScopeRestore:
			err = h.magicLink.IssueForRestore(ctx, email)
		case service.ScopePortal:
			err = h.magicLink.IssueForPortal(ctx, email)
		}
		if err != nil {
			// gorm.ErrRecordNotFound is the "email had no license" branch —
			// expected on bad guesses, log at debug. Everything else (Stripe
			// failure, SMTP failure, Redis fail-closed for rate-limit) is
			// operational and warrants warn.
			if errors.Is(err, gorm.ErrRecordNotFound) {
				logger.Log.Debug().Str("scope", string(scope)).Msg("magic link: email did not match any active license")
				return
			}
			logger.Log.Warn().Err(err).Str("scope", string(scope)).Msg("magic link issuance failed")
		}
	}(scope, req.Email)
	response.Success(c, http.StatusOK, map[string]bool{"sent": true})
}

// RedeemMagicLink godoc
// @Summary Redeem a magic-link token (W1.2/W1.3, public, no auth)
// @Description Single-use redemption. Token came from an email sent by
// @Description web-restore-email or web-portal-email. The website's landing
// @Description page reads the token from window.location.hash and POSTs here.
// @Tags Premium
// @Accept json
// @Produce json
// @Param request body dto.RedeemRequest true "Token + scope"
// @Success 200 {object} response.Response "License key (restore) or portal URL (portal)"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 410 {object} response.Response "Token already redeemed"
// @Failure 401 {object} response.Response "Token invalid / expired / wrong scope"
// @Failure 503 {object} response.Response "Redis not available — single-use cannot be enforced"
// @Router /api/v1/premium/redeem [post]
func (h *PremiumHandler) RedeemMagicLink(c *gin.Context) {
	if h.magicLink == nil {
		response.Error(c, http.StatusServiceUnavailable, "MAGIC_LINK_NOT_CONFIGURED", "Magic link service not available")
		return
	}
	var req dto.RedeemRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	scope := service.MagicLinkScope(req.Scope)
	var portalFactory func(uuid.UUID) (string, error)
	if scope == service.ScopePortal {
		portalFactory = func(licenseID uuid.UUID) (string, error) {
			stripeSvc := h.service.GetStripeService()
			session, err := stripeSvc.CreatePortalSessionForLicense(licenseID)
			if err != nil {
				return "", err
			}
			return session.URL, nil
		}
	}

	result, err := h.magicLink.Redeem(c.Request.Context(), req.Token, scope, portalFactory)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrMagicLinkAlreadyRedeemed):
			response.Error(c, http.StatusGone, "TOKEN_REDEEMED", "This magic link has already been used")
		case errors.Is(err, service.ErrMagicLinkNotConfigured):
			response.Error(c, http.StatusServiceUnavailable, "MAGIC_LINK_NOT_AVAILABLE", "Magic link redemption temporarily unavailable")
		case errors.Is(err, service.ErrMagicLinkInvalid):
			response.Error(c, http.StatusUnauthorized, "INVALID_TOKEN", "Magic link is invalid or expired")
		default:
			response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to redeem magic link")
		}
		return
	}

	if result.Scope == service.ScopeRestore {
		response.Success(c, http.StatusOK, map[string]string{
			"license_key":   result.LicenseKey,
			"billing_cycle": result.BillingCycle,
			"expires_at":    result.ExpiresAt,
		})
		return
	}
	response.Success(c, http.StatusOK, map[string]string{"url": result.PortalURL})
}

// WebPortalSession godoc
// @Summary Open Stripe Billing Portal by email (public, no auth)
// @Description Create a Stripe Billing Portal session using email lookup. For landing page use.
// @Tags Premium
// @Accept json
// @Produce json
// @Param request body dto.WebPortalRequest true "Email (required)"
// @Success 200 {object} response.Response{data=dto.PortalSessionResponse} "Portal URL"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 404 {object} response.Response "No active license or no Stripe customer"
// @Failure 429 {object} response.Response "Rate limit exceeded"
// @Failure 503 {object} response.Response "Stripe not configured"
// @Router /api/v1/premium/web-portal [post]
func (h *PremiumHandler) WebPortalSession(c *gin.Context) {
	// W1.2/W1.3 SECURITY FIX: the old behavior — return a Stripe Billing Portal
	// URL given just an email — let anyone with a customer's email manage their
	// subscription. Convert to magic-link alias so the portal URL is only
	// delivered to the address on file.
	h.issueMagicLink(c, service.ScopePortal)
}
