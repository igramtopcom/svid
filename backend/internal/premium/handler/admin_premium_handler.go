package handler

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/middleware"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"github.com/snakeloader/backend/internal/pkg/validator"
	"github.com/snakeloader/backend/internal/premium/dto"
	"github.com/snakeloader/backend/internal/premium/repository"
	"github.com/snakeloader/backend/internal/premium/service"
	"github.com/snakeloader/backend/internal/response"
)

type AdminPremiumHandler struct {
	service          *service.PremiumService
	financeService   adminPremiumFinanceProvider
	webhookEventRepo *repository.WebhookEventRepository
}

type adminPremiumFinanceProvider interface {
	GetRevenueReport(days int, brand string) (*dto.RevenueReportResponse, error)
	AuditInvoicesViaAdmin(confirmToken string) (*service.InvoiceAuditReport, error)
	GetMRRTrend(months int, brand string) ([]dto.MRRPoint, error)
}

func NewAdminPremiumHandler(svc *service.PremiumService) *AdminPremiumHandler {
	return &AdminPremiumHandler{
		service:        svc,
		financeService: svc,
	}
}

func (h *AdminPremiumHandler) SetWebhookEventRepo(repo *repository.WebhookEventRepository) {
	h.webhookEventRepo = repo
}

func (h *AdminPremiumHandler) SetFinanceService(provider adminPremiumFinanceProvider) {
	h.financeService = provider
}

// CreateLicense godoc
// @Summary Create manual license
// @Description Create a manual/comp license without payment (admin use)
// @Tags Admin - Premium
// @Accept json
// @Produce json
// @Param request body dto.AdminCreateLicenseRequest true "License data"
// @Security BearerAuth
// @Success 201 {object} response.Response{data=dto.LicenseResponse} "License created"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/licenses [post]
func (h *AdminPremiumHandler) CreateLicense(c *gin.Context) {
	var req dto.AdminCreateLicenseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	adminID, _ := c.Get(middleware.AdminIDKey)

	license, err := h.service.AdminCreateLicense(req, adminID.(uuid.UUID))
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to create license")
		return
	}

	response.Success(c, http.StatusCreated, license)
}

// ImportLegacyLicense godoc
// @Summary Import a legacy VidCombo PHP license
// @Description One-shot migration endpoint: imports a pre-existing PHP-issued
// @Description license key (32-hex) into Go DB so paid users from vidcombo.net
// @Description landing page can self-restore via in-app "Restore by Email".
// @Description Preserves license_key verbatim (no generation). Idempotent.
// @Tags Admin - Premium
// @Accept json
// @Produce json
// @Param request body dto.AdminImportLegacyLicenseRequest true "Legacy license"
// @Security BearerAuth
// @Success 201 {object} response.Response{data=dto.LicenseResponse} "Imported"
// @Success 200 {object} response.Response{data=dto.LicenseResponse} "Updated (idempotent)"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/licenses/import-legacy [post]
func (h *AdminPremiumHandler) ImportLegacyLicense(c *gin.Context) {
	var req dto.AdminImportLegacyLicenseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	adminID, _ := c.Get(middleware.AdminIDKey)

	license, err := h.service.AdminImportLegacyLicense(req, adminID.(uuid.UUID))
	if err != nil {
		// Map sentinel errors to clean HTTP responses; never leak raw
		// service / GORM internals through err.Error().
		switch {
		case errors.Is(err, service.ErrLegacyImportInvalidPlan):
			response.Error(c, http.StatusBadRequest, "INVALID_PLAN",
				"Unsupported legacy plan value")
		case errors.Is(err, service.ErrLegacyImportInvalidExpiresAt):
			response.Error(c, http.StatusBadRequest, "INVALID_EXPIRES_AT",
				"expires_at is missing or unreasonably in the past")
		case errors.Is(err, service.ErrLegacyImportInvalidStatus):
			response.Error(c, http.StatusBadRequest, "INVALID_STATUS",
				"status must be 'active' or 'trialing'")
		case errors.Is(err, service.ErrLegacyImportBrandMismatch):
			response.Error(c, http.StatusConflict, "BRAND_MISMATCH",
				"License key collides with a record of a different brand")
		case errors.Is(err, service.ErrLegacyImportRowRevoked):
			response.Error(c, http.StatusConflict, "ROW_REVOKED",
				"License has been revoked, refunded, or downgraded — refusing to resurrect")
		case errors.Is(err, service.ErrLegacyImportPaymentMethodMismatch):
			response.Error(c, http.StatusConflict, "PAYMENT_METHOD_MISMATCH",
				"License key collides with a record of a different payment method")
		default:
			// Genuinely unexpected — log internally, send generic to client.
			response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR",
				"Failed to import legacy license")
		}
		return
	}

	response.Success(c, http.StatusCreated, license)
}

// ListLicenses godoc
// @Summary List all licenses
// @Description Get paginated list of premium licenses
// @Tags Admin - Premium
// @Accept json
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param tier query string false "Filter by tier (free|premium)"
// @Param payment_method query string false "Filter by payment method (stripe|crypto)"
// @Param search query string false "Search by license key"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=response.PaginatedData} "Success"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/licenses [get]
func (h *AdminPremiumHandler) ListLicenses(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)
	tier := c.Query("tier")
	paymentMethod := c.Query("payment_method")
	search := c.Query("search")
	sortBy := c.Query("sort_by")
	sortDir := c.Query("sort_dir")
	brand := c.Query("brand")

	licenses, total, err := h.service.ListLicenses(page, perPage, tier, paymentMethod, search, sortBy, sortDir, brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list licenses")
		return
	}

	response.Paginated(c, licenses, total, page, perPage)
}

// GetLicense godoc
// @Summary Get license by ID
// @Description Get detailed information about a specific license
// @Tags Admin - Premium
// @Accept json
// @Produce json
// @Param id path string true "License UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.LicenseResponse} "Success"
// @Failure 400 {object} response.Response "Invalid ID"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "License not found"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/licenses/{id} [get]
func (h *AdminPremiumHandler) GetLicense(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid license ID format")
		return
	}

	license, err := h.service.GetLicense(id)
	if err != nil {
		if errors.Is(err, service.ErrLicenseNotFound) {
			response.Error(c, http.StatusNotFound, "LICENSE_NOT_FOUND", "License not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get license")
		return
	}

	response.Success(c, http.StatusOK, license)
}

// UpdateLicense godoc
// @Summary Update license
// @Description Update license tier, expiry, or auto-renew
// @Tags Admin - Premium
// @Accept json
// @Produce json
// @Param id path string true "License UUID"
// @Param request body dto.AdminUpdateLicenseRequest true "Update data"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.LicenseResponse} "Success"
// @Failure 400 {object} response.Response "Invalid ID or validation error"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "License not found"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/licenses/{id} [patch]
func (h *AdminPremiumHandler) UpdateLicense(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid license ID format")
		return
	}

	var req dto.AdminUpdateLicenseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	adminID, _ := c.Get(middleware.AdminIDKey)

	license, err := h.service.UpdateLicense(id, req, adminID.(uuid.UUID))
	if err != nil {
		if errors.Is(err, service.ErrLicenseNotFound) {
			response.Error(c, http.StatusNotFound, "LICENSE_NOT_FOUND", "License not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to update license")
		return
	}

	response.Success(c, http.StatusOK, license)
}

// ListDevices godoc
// @Summary List devices on a license
// @Description Get all devices registered to a specific license
// @Tags Admin - Premium
// @Accept json
// @Produce json
// @Param id path string true "License UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=[]dto.LicenseDeviceResponse} "Success"
// @Failure 400 {object} response.Response "Invalid ID"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "License not found"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/licenses/{id}/devices [get]
func (h *AdminPremiumHandler) ListDevices(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid license ID format")
		return
	}

	devices, err := h.service.AdminListDevices(id)
	if err != nil {
		if errors.Is(err, service.ErrLicenseNotFound) {
			response.Error(c, http.StatusNotFound, "LICENSE_NOT_FOUND", "License not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list devices")
		return
	}

	response.Success(c, http.StatusOK, devices)
}

// RemoveDevice godoc
// @Summary Remove device from license
// @Description Remove a device registration from a license (admin)
// @Tags Admin - Premium
// @Accept json
// @Produce json
// @Param id path string true "License UUID"
// @Param deviceId path string true "Device UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response "Device removed"
// @Failure 400 {object} response.Response "Invalid ID"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "License or device not found"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/licenses/{id}/devices/{deviceId} [delete]
func (h *AdminPremiumHandler) RemoveDevice(c *gin.Context) {
	licenseID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid license ID format")
		return
	}

	deviceID, err := uuid.Parse(c.Param("deviceId"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_DEVICE_ID", "Invalid device ID format")
		return
	}

	err = h.service.AdminRemoveDevice(licenseID, deviceID)
	if err != nil {
		if errors.Is(err, service.ErrLicenseNotFound) {
			response.Error(c, http.StatusNotFound, "LICENSE_NOT_FOUND", "License not found")
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

// ListTransactions godoc
// @Summary List payment transactions
// @Description Get paginated list of payment transactions
// @Tags Admin - Premium
// @Accept json
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param status query string false "Filter by status (pending|completed|failed|cancelled)"
// @Param payment_method query string false "Filter by payment method (stripe|crypto)"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=response.PaginatedData} "Success"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/transactions [get]
func (h *AdminPremiumHandler) ListTransactions(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)
	status := c.Query("status")
	paymentMethod := c.Query("payment_method")

	txns, total, err := h.service.ListTransactions(page, perPage, status, paymentMethod)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list transactions")
		return
	}

	response.Paginated(c, txns, total, page, perPage)
}

// RefundTransaction godoc
// @Summary Refund a transaction
// @Description Mark a completed transaction as refunded and optionally cancel the associated license
// @Tags Admin - Premium
// @Accept json
// @Produce json
// @Param id path string true "Transaction UUID"
// @Param request body dto.RefundRequest false "Refund options"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.TransactionResponse} "Transaction refunded"
// @Failure 400 {object} response.Response "Invalid ID or not refundable"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 404 {object} response.Response "Transaction not found"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/transactions/{id}/refund [post]
func (h *AdminPremiumHandler) RefundTransaction(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid transaction ID format")
		return
	}

	var req dto.RefundRequest
	// Body is optional; if no body is provided, cancelLicense defaults to false
	_ = c.ShouldBindJSON(&req)

	result, err := h.service.RefundTransaction(id, req.CancelLicense)
	if err != nil {
		if errors.Is(err, service.ErrTransactionNotFound) {
			response.Error(c, http.StatusNotFound, "TRANSACTION_NOT_FOUND", "Transaction not found")
			return
		}
		if errors.Is(err, service.ErrNotRefundable) {
			response.Error(c, http.StatusBadRequest, "NOT_REFUNDABLE", "Only completed transactions can be refunded")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to refund transaction")
		return
	}

	response.Success(c, http.StatusOK, result)
}

// PremiumStats godoc
// @Summary Get premium statistics
// @Description Get revenue, subscription, and churn statistics
// @Tags Admin - Premium
// @Accept json
// @Produce json
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.PremiumStatsResponse} "Success"
// @Failure 401 {object} response.Response "Unauthorized"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/premium/stats [get]
func (h *AdminPremiumHandler) PremiumStats(c *gin.Context) {
	brand := c.Query("brand")
	stats, err := h.service.GetPremiumStats(brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get premium stats")
		return
	}

	response.Success(c, http.StatusOK, stats)
}

// --- Business Dashboard Handlers ---

// GetTransaction godoc
// @Summary Get transaction by ID
// @Description Get detailed info about a specific transaction including linked license
// @Tags Admin - Transactions
// @Produce json
// @Param id path string true "Transaction UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.EnhancedTransactionResponse} "Success"
// @Router /admin/v1/transactions/{id} [get]
func (h *AdminPremiumHandler) GetTransaction(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid transaction ID format")
		return
	}

	txn, err := h.service.GetTransaction(id)
	if err != nil {
		if errors.Is(err, service.ErrTransactionNotFound) {
			response.Error(c, http.StatusNotFound, "TRANSACTION_NOT_FOUND", "Transaction not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get transaction")
		return
	}

	response.Success(c, http.StatusOK, txn)
}

// ListTransactionsEnhanced godoc
// @Summary List transactions with enhanced data
// @Description Get paginated transactions with linked license data, search, and date filters
// @Tags Admin - Transactions
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param status query string false "Filter by status"
// @Param payment_method query string false "Filter by payment method"
// @Param search query string false "Search by ID, email, or license key"
// @Param date_from query string false "Start date (RFC3339)"
// @Param date_to query string false "End date (RFC3339)"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=response.PaginatedData} "Success"
// @Router /admin/v1/transactions [get]
func (h *AdminPremiumHandler) ListTransactionsEnhanced(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)
	status := c.Query("status")
	paymentMethod := c.Query("payment_method")
	search := c.Query("search")
	dateFrom := c.Query("date_from")
	dateTo := c.Query("date_to")
	sortBy := c.Query("sort_by")
	sortDir := c.Query("sort_dir")
	brand := c.Query("brand")

	txns, total, err := h.service.ListTransactionsEnhanced(page, perPage, status, paymentMethod, search, dateFrom, dateTo, sortBy, sortDir, brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list transactions")
		return
	}

	response.Paginated(c, txns, total, page, perPage)
}

// TransactionStats godoc
// @Summary Get transaction statistics
// @Description Get aggregate transaction stats (total, revenue, by status)
// @Tags Admin - Transactions
// @Produce json
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.TransactionStatsResponse} "Success"
// @Router /admin/v1/transactions/stats [get]
func (h *AdminPremiumHandler) TransactionStats(c *gin.Context) {
	brand := c.Query("brand")
	stats, err := h.service.GetTransactionStats(brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get transaction stats")
		return
	}

	response.Success(c, http.StatusOK, stats)
}

// ListSubscriptions godoc
// @Summary List subscriptions
// @Description Get paginated subscription view of premium licenses
// @Tags Admin - Subscriptions
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param status query string false "Filter by status (active|cancelled|expired)"
// @Param search query string false "Search by license key or email"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=response.PaginatedData} "Success"
// @Router /admin/v1/subscriptions [get]
func (h *AdminPremiumHandler) ListSubscriptions(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)
	status := c.Query("status")
	search := c.Query("search")
	sortBy := c.Query("sort_by")
	sortDir := c.Query("sort_dir")
	brand := c.Query("brand")

	subs, total, err := h.service.ListSubscriptions(page, perPage, status, search, sortBy, sortDir, brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list subscriptions")
		return
	}

	response.Paginated(c, subs, total, page, perPage)
}

// SubscriptionStats godoc
// @Summary Get subscription statistics
// @Description Get aggregate subscription stats (active, cancelled, expired, MRR, churn)
// @Tags Admin - Subscriptions
// @Produce json
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.SubscriptionStatsResponse} "Success"
// @Router /admin/v1/subscriptions/stats [get]
func (h *AdminPremiumHandler) SubscriptionStats(c *gin.Context) {
	brand := c.Query("brand")
	stats, err := h.service.GetSubscriptionStats(brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get subscription stats")
		return
	}

	response.Success(c, http.StatusOK, stats)
}

// ListCustomers godoc
// @Summary List customers
// @Description Get paginated customer aggregates grouped by contact email
// @Tags Admin - Customers
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param search query string false "Search by email or Stripe ID"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=response.PaginatedData} "Success"
// @Router /admin/v1/customers [get]
func (h *AdminPremiumHandler) ListCustomers(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)
	search := c.Query("search")
	sortBy := c.Query("sort_by")
	sortDir := c.Query("sort_dir")
	brand := c.Query("brand")

	customers, total, err := h.service.ListCustomers(page, perPage, search, sortBy, sortDir, brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list customers")
		return
	}

	response.Paginated(c, customers, total, page, perPage)
}

// GetCustomer godoc
// @Summary Get customer by email
// @Description Get detailed customer info including licenses and transactions
// @Tags Admin - Customers
// @Produce json
// @Param email path string true "Customer email"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.CustomerDetailResponse} "Success"
// @Router /admin/v1/customers/{email} [get]
func (h *AdminPremiumHandler) GetCustomer(c *gin.Context) {
	email := c.Param("email")
	if email == "" {
		response.Error(c, http.StatusBadRequest, "INVALID_EMAIL", "Email is required")
		return
	}

	customer, err := h.service.GetCustomer(email)
	if err != nil {
		if errors.Is(err, service.ErrLicenseNotFound) {
			response.Error(c, http.StatusNotFound, "CUSTOMER_NOT_FOUND", "Customer not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get customer")
		return
	}

	response.Success(c, http.StatusOK, customer)
}

// CustomerStats godoc
// @Summary Get customer statistics
// @Description Get aggregate customer stats (total, revenue, avg revenue)
// @Tags Admin - Customers
// @Produce json
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.CustomerStatsResponse} "Success"
// @Router /admin/v1/customers/stats [get]
func (h *AdminPremiumHandler) CustomerStats(c *gin.Context) {
	brand := c.Query("brand")
	stats, err := h.service.GetCustomerStats(brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get customer stats")
		return
	}

	response.Success(c, http.StatusOK, stats)
}

// RevenueReport godoc
// @Summary Get revenue report
// @Description Get comprehensive revenue data with daily breakdown, by method, by cycle
// @Tags Admin - Finance
// @Produce json
// @Param days query int false "Number of days for daily breakdown" default(30)
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.RevenueReportResponse} "Success"
// @Router /admin/v1/finance/revenue [get]
func (h *AdminPremiumHandler) RevenueReport(c *gin.Context) {
	days, _ := strconv.Atoi(c.DefaultQuery("days", "30"))
	days = normalizePositiveQueryBound(days, 30, 365)
	brand := c.Query("brand")

	report, err := h.financeService.GetRevenueReport(days, brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get revenue report")
		return
	}

	response.Success(c, http.StatusOK, report)
}

// AuditInvoices godoc
// @Summary Audit invoices against Stripe and optionally purge foreign rows
// @Description Walks every row in the invoices table, fetches the live invoice
// @Description from Stripe, and classifies it as KEEP / FOREIGN / STRIPE_MISSING /
// @Description ERROR using the price-ID whitelist. Dry-run by default.
// @Description Pass `confirm_token=DELETE_FOREIGN_INVOICES` in the body to
// @Description actually delete FOREIGN rows in a single transaction.
// @Tags Admin - Premium
// @Accept json
// @Produce json
// @Security BearerAuth
// @Success 200 {object} response.Response "Audit report"
// @Router /admin/v1/premium/invoices/audit [post]
func (h *AdminPremiumHandler) AuditInvoices(c *gin.Context) {
	var req struct {
		ConfirmToken string `json:"confirm_token"`
	}
	// Body is optional — no body means dry-run.
	_ = c.ShouldBindJSON(&req)

	report, err := h.financeService.AuditInvoicesViaAdmin(req.ConfirmToken)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "AUDIT_FAILED", err.Error())
		return
	}

	response.Success(c, http.StatusOK, report)
}

// ListInvoices godoc
// @Summary List invoices
// @Description Get paginated list of invoices with optional filters
// @Tags Admin - Invoices
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Param status query string false "Filter by status (open|paid|void|uncollectible)"
// @Param search query string false "Search by email or stripe invoice ID"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=response.PaginatedData} "Success"
// @Router /admin/v1/invoices [get]
func (h *AdminPremiumHandler) ListInvoices(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	page, perPage = pagination.Normalize(page, perPage, 20)
	status := c.Query("status")
	search := c.Query("search")
	sortBy := c.Query("sort_by")
	sortDir := c.Query("sort_dir")
	brand := c.Query("brand")

	invoices, total, err := h.service.ListInvoices(page, perPage, status, search, sortBy, sortDir, brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list invoices")
		return
	}

	response.Paginated(c, invoices, total, page, perPage)
}

// InvoiceStats godoc
// @Summary Get invoice statistics
// @Description Get aggregate invoice stats (total, paid amount, by status)
// @Tags Admin - Invoices
// @Produce json
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.InvoiceStatsResponse} "Success"
// @Router /admin/v1/invoices/stats [get]
func (h *AdminPremiumHandler) InvoiceStats(c *gin.Context) {
	brand := c.Query("brand")
	stats, err := h.service.GetInvoiceStats(brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get invoice stats")
		return
	}

	response.Success(c, http.StatusOK, stats)
}

// GlobalSearch godoc
// @Summary Global search across business data
// @Description Search licenses, transactions, and customers
// @Tags Admin - Search
// @Produce json
// @Param q query string true "Search query"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.GlobalSearchResponse} "Success"
// @Router /admin/v1/search [get]
func (h *AdminPremiumHandler) GlobalSearch(c *gin.Context) {
	query := c.Query("q")
	if query == "" {
		response.Error(c, http.StatusBadRequest, "MISSING_QUERY", "Search query is required")
		return
	}

	results, err := h.service.GlobalSearch(query, 5)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Search failed")
		return
	}

	response.Success(c, http.StatusOK, results)
}

// ListWebhookEvents returns paginated Stripe webhook events for admin debugging.
func (h *AdminPremiumHandler) ListWebhookEvents(c *gin.Context) {
	if h.webhookEventRepo == nil {
		response.Error(c, http.StatusNotImplemented, "NOT_CONFIGURED", "Webhook events not available")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "30"))
	page, perPage = pagination.Normalize(page, perPage, 30)

	events, total, err := h.webhookEventRepo.List(
		page, perPage,
		c.Query("event_type"),
		c.Query("status"),
	)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list webhook events")
		return
	}

	type WebhookEventResponse struct {
		ID          uint   `json:"id"`
		EventID     string `json:"event_id"`
		EventType   string `json:"event_type"`
		Status      string `json:"status"`
		ProcessedAt string `json:"processed_at,omitempty"`
		CreatedAt   string `json:"created_at"`
	}

	items := make([]WebhookEventResponse, len(events))
	for i, e := range events {
		resp := WebhookEventResponse{
			ID:        e.ID,
			EventID:   e.EventID,
			EventType: e.EventType,
			Status:    e.Status,
			CreatedAt: e.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		}
		if e.ProcessedAt != nil {
			resp.ProcessedAt = e.ProcessedAt.Format("2006-01-02T15:04:05Z07:00")
		}
		items[i] = resp
	}

	response.Paginated(c, items, total, page, perPage)
}

// MRRTrend godoc
// @Summary Get MRR trend
// @Description Get monthly recurring revenue trend over the last N months
// @Tags Admin - Subscriptions
// @Produce json
// @Param months query int false "Number of months" default(12)
// @Security BearerAuth
// @Success 200 {object} response.Response{data=[]dto.MRRPoint} "Success"
// @Router /admin/v1/subscriptions/mrr-trend [get]
func (h *AdminPremiumHandler) MRRTrend(c *gin.Context) {
	months, _ := strconv.Atoi(c.DefaultQuery("months", "12"))
	months = normalizePositiveQueryBound(months, 12, 36)
	brand := c.Query("brand")

	trend, err := h.financeService.GetMRRTrend(months, brand)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get MRR trend")
		return
	}

	response.Success(c, http.StatusOK, trend)
}

// GetInvoice godoc
// @Summary Get invoice by ID
// @Description Get detailed information about a specific invoice
// @Tags Admin - Invoices
// @Produce json
// @Param id path string true "Invoice UUID"
// @Security BearerAuth
// @Success 200 {object} response.Response{data=dto.InvoiceResponse} "Success"
// @Failure 400 {object} response.Response "Invalid ID"
// @Failure 404 {object} response.Response "Invoice not found"
// @Router /admin/v1/invoices/{id} [get]
func (h *AdminPremiumHandler) GetInvoice(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_ID", "Invalid invoice ID format")
		return
	}

	invoice, err := h.service.GetInvoice(id)
	if err != nil {
		if err.Error() == "invoice not found" {
			response.Error(c, http.StatusNotFound, "INVOICE_NOT_FOUND", "Invoice not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to get invoice")
		return
	}

	response.Success(c, http.StatusOK, invoice)
}

func normalizePositiveQueryBound(value, fallback, max int) int {
	if value <= 0 {
		return fallback
	}
	if value > max {
		return max
	}
	return value
}
