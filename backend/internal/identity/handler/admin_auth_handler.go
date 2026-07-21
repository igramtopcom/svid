package handler

import (
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"github.com/snakeloader/backend/internal/identity/dto"
	"github.com/snakeloader/backend/internal/identity/service"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/pkg/validator"
	"github.com/snakeloader/backend/internal/response"
)

type AdminAuthHandler struct {
	service *service.AdminService
	rdb     *redis.Client
}

func NewAdminAuthHandler(svc *service.AdminService, rdb *redis.Client) *AdminAuthHandler {
	return &AdminAuthHandler{service: svc, rdb: rdb}
}

// Login godoc
// @Summary Admin login
// @Description Authenticate admin user and return JWT token
// @Tags Admin Auth
// @Accept json
// @Produce json
// @Param request body dto.AdminLoginRequest true "Login credentials"
// @Success 200 {object} response.Response{data=dto.AdminLoginResponse} "Success"
// @Failure 400 {object} response.Response "Validation error"
// @Failure 401 {object} response.Response "Invalid credentials"
// @Failure 429 {object} response.Response "Too many attempts"
// @Failure 500 {object} response.Response "Internal error"
// @Router /admin/v1/auth/login [post]
func (h *AdminAuthHandler) Login(c *gin.Context) {
	var req dto.AdminLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ValidationError(c, validator.FormatValidationErrors(err))
		return
	}

	// Brute-force protection: check per-IP and per-email attempt counts
	if h.rdb != nil {
		ctx := c.Request.Context()

		// Per-IP rate limit (prevents distributed brute force across multiple emails)
		ipKey := fmt.Sprintf("admin_login_ip:%s", c.ClientIP())
		ipCount, err := h.rdb.Get(ctx, ipKey).Int()
		if err != nil && err != redis.Nil {
			logger.Log.Error().Err(err).Msg("Redis unavailable for rate limiting")
			response.Error(c, http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "Please try again later")
			return
		}
		if ipCount >= 20 {
			logger.Log.Warn().Str("ip", c.ClientIP()).Msg("Admin login blocked — too many attempts from IP")
			response.Error(c, http.StatusTooManyRequests, "IP_RATE_LIMITED", "Too many login attempts from this IP. Try again in 15 minutes.")
			return
		}

		// Per-email rate limit (prevents brute force on specific account)
		key := fmt.Sprintf("admin_login_attempts:%s", req.Email)
		count, err := h.rdb.Get(ctx, key).Int()
		if err != nil && err != redis.Nil {
			logger.Log.Error().Err(err).Msg("Redis unavailable for rate limiting")
			response.Error(c, http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "Please try again later")
			return
		}
		if count >= 5 {
			logger.Log.Warn().Str("email", req.Email).Msg("Admin login locked — too many attempts")
			response.Error(c, http.StatusTooManyRequests, "ACCOUNT_LOCKED", "Too many login attempts. Try again in 15 minutes.")
			return
		}
	}

	result, err := h.service.Login(req)
	if err != nil {
		// Track failed attempt (both per-email and per-IP)
		if h.rdb != nil {
			ctx := c.Request.Context()
			emailKey := fmt.Sprintf("admin_login_attempts:%s", req.Email)
			h.rdb.Incr(ctx, emailKey)
			h.rdb.Expire(ctx, emailKey, 15*time.Minute)

			ipKey := fmt.Sprintf("admin_login_ip:%s", c.ClientIP())
			h.rdb.Incr(ctx, ipKey)
			h.rdb.Expire(ctx, ipKey, 15*time.Minute)
		}

		if errors.Is(err, service.ErrInvalidCredentials) {
			response.Error(c, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Invalid email or password")
			return
		}
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to process login")
		return
	}

	// Clear attempt counters on success (both per-email and per-IP)
	if h.rdb != nil {
		ctx := c.Request.Context()
		key := fmt.Sprintf("admin_login_attempts:%s", req.Email)
		h.rdb.Del(ctx, key)
		ipKey := fmt.Sprintf("admin_login_ip:%s", c.ClientIP())
		h.rdb.Del(ctx, ipKey)
	}

	response.Success(c, http.StatusOK, result)
}
