package service

import (
	"errors"
	"time"

	"github.com/snakeloader/backend/internal/identity/dto"
	"github.com/snakeloader/backend/internal/identity/repository"
	"github.com/snakeloader/backend/internal/pkg/crypto"
	jwtpkg "github.com/snakeloader/backend/internal/pkg/jwt"
	"github.com/snakeloader/backend/internal/pkg/logger"
)

var (
	ErrInvalidCredentials = errors.New("invalid email or password")
)

type AdminService struct {
	adminRepo  *repository.AdminRepository
	jwtManager *jwtpkg.Manager
}

func NewAdminService(
	adminRepo *repository.AdminRepository,
	jwtManager *jwtpkg.Manager,
) *AdminService {
	return &AdminService{
		adminRepo:  adminRepo,
		jwtManager: jwtManager,
	}
}

// Login validates admin credentials and returns a JWT token.
func (s *AdminService) Login(req dto.AdminLoginRequest) (*dto.AdminLoginResponse, error) {
	admin, err := s.adminRepo.FindByEmail(req.Email)
	if err != nil {
		return nil, ErrInvalidCredentials
	}

	if !crypto.CheckPassword(req.Password, admin.PasswordHash) {
		return nil, ErrInvalidCredentials
	}

	token, expiresAt, err := s.jwtManager.Generate(admin.ID, admin.BrandScope)
	if err != nil {
		return nil, err
	}

	if err := s.adminRepo.UpdateLastLogin(admin.ID); err != nil {
		logger.Log.Warn().Err(err).Str("admin_id", admin.ID.String()).Msg("Failed to update admin last_login_at")
	}

	logger.Log.Info().Str("admin_id", admin.ID.String()).Msg("Admin logged in")

	return &dto.AdminLoginResponse{
		Token:     token,
		ExpiresAt: expiresAt.Format(time.RFC3339),
		Admin: dto.AdminInfo{
			ID:         admin.ID.String(),
			Email:      admin.Email,
			Name:       admin.Name,
			BrandScope: admin.BrandScope,
		},
	}, nil
}
