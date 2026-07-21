package service

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/config"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/premium/dto"
	"github.com/snakeloader/backend/internal/premium/model"
	"github.com/snakeloader/backend/internal/premium/repository"
	"gorm.io/gorm"
)

const (
	CryptoInvoiceExpiry = 15 * time.Minute
	BTCConfirmations    = 1
	LTCConfirmations    = 3
	XMRConfirmations    = 10
	btcpayTimeout       = 15 * time.Second
)

var (
	ErrCryptoNotConfigured = errors.New("crypto payment not configured")
)

type CryptoService struct {
	cfg            *config.BTCPayConfig
	licenseRepo    *repository.LicenseRepository
	txnRepo        *repository.TransactionRepository
	jwtSecret      string
	httpClient     *http.Client
	premiumService *PremiumService // back-reference, set after construction to break circular init
}

func NewCryptoService(
	cfg *config.BTCPayConfig,
	licenseRepo *repository.LicenseRepository,
	txnRepo *repository.TransactionRepository,
	jwtSecret string,
) *CryptoService {
	return &CryptoService{
		cfg:         cfg,
		licenseRepo: licenseRepo,
		txnRepo:     txnRepo,
		jwtSecret:   jwtSecret,
		httpClient: &http.Client{
			Timeout: btcpayTimeout,
		},
	}
}

// SetPremiumService sets the back-reference to PremiumService.
// Called after both services are constructed to break circular init.
func (s *CryptoService) SetPremiumService(ps *PremiumService) {
	s.premiumService = ps
}

// IsConfigured returns true if BTCPay keys are set.
func (s *CryptoService) IsConfigured() bool {
	return s.cfg.ServerURL != "" && s.cfg.APIKey != ""
}

// btcPayInvoiceRequest is the BTCPay Server create invoice request body.
type btcPayInvoiceRequest struct {
	Amount   string            `json:"amount"`
	Currency string            `json:"currency"`
	Metadata map[string]string `json:"metadata,omitempty"`
	Checkout *btcPayCheckout   `json:"checkout,omitempty"`
}

type btcPayCheckout struct {
	SpeedPolicy    string   `json:"speedPolicy,omitempty"`
	ExpirationMin  int      `json:"expirationMinutes,omitempty"`
	PaymentMethods []string `json:"paymentMethods,omitempty"`
}

// btcPayInvoiceResponse is the BTCPay Server invoice response.
type btcPayInvoiceResponse struct {
	ID             string `json:"id"`
	Status         string `json:"status"`
	Amount         string `json:"amount"`
	Currency       string `json:"currency"`
	CheckoutLink   string `json:"checkoutLink"`
	CreatedTime    int64  `json:"createdTime"`
	ExpirationTime int64  `json:"expirationTime"`
}

// CreateInvoice creates a BTCPay crypto invoice.
func (s *CryptoService) CreateInvoice(deviceID uuid.UUID, brand string, req dto.CryptoInvoiceRequest) (*dto.CryptoInvoiceResponse, error) {
	if !s.IsConfigured() {
		return nil, ErrCryptoNotConfigured
	}
	if brand == "" {
		brand = "ssvid"
	}

	// Check for duplicate idempotency key
	existing, err := s.txnRepo.FindByIdempotencyKey(req.IdempotencyKey)
	if err == nil && existing != nil {
		return nil, ErrDuplicatePayment
	}

	// Calculate amount in USD for BTCPay (it handles conversion)
	amountCents := AmountCentsForBillingCycle(req.BillingCycle, brand)
	amountUSD := fmt.Sprintf("%.2f", float64(amountCents)/100)

	// Determine payment method filter for BTCPay
	paymentMethods := cryptoPaymentMethod(req.Currency)

	// Call BTCPay Server API
	invoiceReq := btcPayInvoiceRequest{
		Amount:   amountUSD,
		Currency: "USD",
		Metadata: map[string]string{
			"device_id":       deviceID.String(),
			"brand":           brand,
			"billing_cycle":   req.BillingCycle,
			"crypto_currency": req.Currency,
			"idempotency_key": req.IdempotencyKey,
		},
		Checkout: &btcPayCheckout{
			SpeedPolicy:    cryptoSpeedPolicy(req.Currency),
			ExpirationMin:  15,
			PaymentMethods: paymentMethods,
		},
	}

	btcPayResp, err := s.callBTCPayCreateInvoice(invoiceReq)
	if err != nil {
		logger.Log.Error().Err(err).Str("currency", req.Currency).Msg("BTCPay invoice creation failed")
		return nil, fmt.Errorf("btcpay error: %w", err)
	}

	invoiceID := btcPayResp.ID
	expiresAt := time.Unix(btcPayResp.ExpirationTime, 0)

	// Record pending transaction
	txn := &model.PaymentTransaction{
		DeviceID:        deviceID,
		Brand:           brand,
		IdempotencyKey:  req.IdempotencyKey,
		PaymentMethod:   "crypto",
		BillingCycle:    req.BillingCycle,
		AmountCents:     amountCents,
		Currency:        req.Currency,
		Status:          "pending",
		CryptoInvoiceID: &invoiceID,
	}
	if err := s.txnRepo.Create(txn); err != nil {
		return nil, err
	}

	logger.Log.Info().
		Str("invoice_id", invoiceID).
		Str("device_id", deviceID.String()).
		Str("brand", brand).
		Str("currency", req.Currency).
		Str("billing_cycle", req.BillingCycle).
		Msg("Crypto invoice created")

	return &dto.CryptoInvoiceResponse{
		InvoiceID:     invoiceID,
		Currency:      req.Currency,
		Amount:        btcPayResp.Amount,
		Address:       btcPayResp.CheckoutLink,
		PaymentURI:    btcPayResp.CheckoutLink,
		Confirmations: 0,
		ExpiresAt:     expiresAt.Format(time.RFC3339),
		CreatedAt:     time.Now().Format(time.RFC3339),
	}, nil
}

// callBTCPayCreateInvoice makes the real HTTP call to BTCPay Server.
func (s *CryptoService) callBTCPayCreateInvoice(req btcPayInvoiceRequest) (*btcPayInvoiceResponse, error) {
	body, err := json.Marshal(req)
	if err != nil {
		return nil, err
	}

	url := fmt.Sprintf("%s/api/v1/stores/%s/invoices", s.cfg.ServerURL, s.cfg.StoreID)
	httpReq, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "token "+s.cfg.APIKey)

	resp, err := s.httpClient.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("BTCPay returned status %d: %s", resp.StatusCode, string(respBody))
	}

	var result btcPayInvoiceResponse
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, fmt.Errorf("failed to parse BTCPay response: %w", err)
	}

	return &result, nil
}

// CheckStatus checks the status of a crypto invoice.
func (s *CryptoService) CheckStatus(invoiceID string, deviceID uuid.UUID) (*dto.PaymentResultResponse, error) {
	if !s.IsConfigured() {
		return nil, ErrCryptoNotConfigured
	}

	txn, err := s.txnRepo.FindByCryptoInvoiceID(invoiceID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("invoice not found")
		}
		return nil, err
	}

	// Validate device ownership
	if txn.DeviceID != deviceID {
		return nil, errors.New("invoice not found")
	}

	// Query BTCPay for real-time invoice status
	btcPayResp, err := s.callBTCPayGetInvoice(invoiceID)
	if err != nil {
		logger.Log.Warn().Err(err).Str("invoice_id", invoiceID).Msg("Failed to fetch BTCPay invoice, using local status")
	} else {
		newStatus := mapBTCPayStatus(btcPayResp.Status)
		if newStatus != txn.Status {
			txn.Status = newStatus
			if newStatus == "completed" {
				now := time.Now()
				txn.CompletedAt = &now
			}
			_ = s.txnRepo.Update(txn)
		}
	}

	// Use the shared deduped method — prevents race from concurrent polls
	if txn.Status == "completed" {
		license, _, fErr := s.premiumService.FindOrCreateLicenseForCryptoInvoice(invoiceID, deviceID)
		if fErr != nil {
			logger.Log.Error().Err(fErr).Str("invoice_id", invoiceID).
				Msg("Failed to find/create license for crypto invoice")
		} else if license != nil {
			txn.LicenseID = &license.ID
		}
	}

	resp := &dto.PaymentResultResponse{
		Status:        txn.Status,
		TransactionID: txn.ID.String(),
		PaymentMethod: "crypto",
		BillingCycle:  txn.BillingCycle,
		CreatedAt:     txn.CreatedAt.Format(time.RFC3339),
	}

	// Populate ErrorMessage for expired/failed invoices
	switch txn.Status {
	case "cancelled":
		resp.ErrorMessage = "Invoice expired"
	case "failed":
		resp.ErrorMessage = "Invoice marked invalid"
	}

	// If completed, include license info
	if txn.Status == "completed" && txn.LicenseID != nil {
		license, err := s.licenseRepo.FindByID(*txn.LicenseID)
		if err == nil {
			resp.LicenseKey = license.LicenseKey
			resp.ExpiresAt = license.ExpiresAt.Format(time.RFC3339)
		}
	}

	return resp, nil
}

// callBTCPayGetInvoice fetches invoice status from BTCPay Server.
func (s *CryptoService) callBTCPayGetInvoice(invoiceID string) (*btcPayInvoiceResponse, error) {
	url := fmt.Sprintf("%s/api/v1/stores/%s/invoices/%s", s.cfg.ServerURL, s.cfg.StoreID, invoiceID)
	httpReq, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Authorization", "token "+s.cfg.APIKey)

	resp, err := s.httpClient.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("BTCPay returned status %d: %s", resp.StatusCode, string(respBody))
	}

	var result btcPayInvoiceResponse
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, fmt.Errorf("failed to parse BTCPay response: %w", err)
	}

	return &result, nil
}

// RequiredConfirmations returns the required confirmations for a currency.
func RequiredConfirmations(currency string) int {
	switch currency {
	case "BTC":
		return BTCConfirmations
	case "LTC":
		return LTCConfirmations
	case "XMR":
		return XMRConfirmations
	default:
		return 1
	}
}

// mapBTCPayStatus maps BTCPay invoice status to our status.
func mapBTCPayStatus(btcPayStatus string) string {
	switch btcPayStatus {
	case "New", "Processing":
		return "pending"
	case "Settled":
		return "completed"
	case "Expired":
		return "cancelled"
	case "Invalid":
		return "failed"
	default:
		return "pending"
	}
}

// cryptoPaymentMethod returns BTCPay payment method identifiers.
func cryptoPaymentMethod(currency string) []string {
	switch currency {
	case "BTC":
		return []string{"BTC-OnChain", "BTC-LightningNetwork"}
	case "LTC":
		return []string{"LTC-OnChain"}
	case "XMR":
		return []string{"XMR-OnChain"}
	default:
		return nil
	}
}

// cryptoSpeedPolicy returns the BTCPay speed policy based on confirmations needed.
func cryptoSpeedPolicy(currency string) string {
	switch currency {
	case "BTC":
		return "MediumSpeed" // 1 confirmation
	case "LTC":
		return "MediumSpeed" // 3 confirmations
	case "XMR":
		return "LowMediumSpeed" // 10 confirmations
	default:
		return "MediumSpeed"
	}
}

// Stub helpers retained for testing/development without BTCPay Server.

func cryptoStubAmount(currency, billingCycle, brand string) string {
	cents := AmountCentsForBillingCycle(billingCycle, brand)
	switch currency {
	case "BTC":
		return fmt.Sprintf("%.5f", float64(cents)/10000000)
	case "LTC":
		return fmt.Sprintf("%.4f", float64(cents)/10000)
	case "XMR":
		return fmt.Sprintf("%.4f", float64(cents)/15000)
	default:
		return "0"
	}
}

func cryptoStubAddress(currency string) string {
	switch currency {
	case "BTC":
		return "bc1qstub" + uuid.New().String()[:8]
	case "LTC":
		return "ltc1qstub" + uuid.New().String()[:8]
	case "XMR":
		return "4stub" + uuid.New().String()[:16]
	default:
		return "stub_address"
	}
}

func cryptoScheme(currency string) string {
	switch currency {
	case "BTC":
		return "bitcoin"
	case "LTC":
		return "litecoin"
	case "XMR":
		return "monero"
	default:
		return "crypto"
	}
}
