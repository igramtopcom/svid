package handler

import (
	"crypto/subtle"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/product/dto"
	"github.com/snakeloader/backend/internal/product/service"
	"github.com/snakeloader/backend/internal/response"
)

// CIReleaseHandler handles automated release registration from CI pipeline.
type CIReleaseHandler struct {
	service *service.ProductService
	secret  string
}

func NewCIReleaseHandler(svc *service.ProductService, secret string) *CIReleaseHandler {
	return &CIReleaseHandler{service: svc, secret: secret}
}

// RegisterRelease creates or updates AppRelease records for each platform in a batch.
// Authenticated via X-CI-Secret header (shared secret between CI and backend).
func (h *CIReleaseHandler) RegisterRelease(c *gin.Context) {
	providedSecret := c.GetHeader("X-CI-Secret")
	if h.secret == "" || subtle.ConstantTimeCompare([]byte(providedSecret), []byte(h.secret)) != 1 {
		response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "Invalid CI secret")
		return
	}

	var req dto.CIReleaseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error())
		return
	}

	if len(req.Platforms) == 0 {
		response.Error(c, http.StatusBadRequest, "NO_PLATFORMS", "At least one platform is required")
		return
	}

	validPlatforms := map[string]bool{"macos": true, "windows": true, "linux": true, "android": true}
	for p := range req.Platforms {
		if !validPlatforms[p] {
			response.Error(c, http.StatusBadRequest, "INVALID_PLATFORM", "Platform must be macos, windows, linux, or android")
			return
		}
	}

	channel := req.Channel
	if channel == "" {
		channel = "stable"
	}

	brand := req.Brand
	if brand == "" {
		brand = "ssvid"
	}

	results, err := h.service.RegisterCIRelease(req.Version, channel, req.ReleaseNotes, brand, req.IsMandatory, req.Platforms)
	if err != nil {
		logger.Log.Error().Err(err).Str("version", req.Version).Msg("Failed to register CI release")
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to register release")
		return
	}

	logger.Log.Info().
		Str("version", req.Version).
		Int("platforms", len(req.Platforms)).
		Msg("CI release registered")

	response.Success(c, http.StatusOK, gin.H{
		"registered": len(results),
		"releases":   results,
	})
}
