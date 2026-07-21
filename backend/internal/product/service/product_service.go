package service

import (
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"github.com/snakeloader/backend/internal/product/dto"
	"github.com/snakeloader/backend/internal/product/model"
	"github.com/snakeloader/backend/internal/product/repository"
	"gorm.io/gorm"
)

var (
	ErrFeatureFlagNotFound  = errors.New("feature flag not found")
	ErrRemoteConfigNotFound = errors.New("remote config not found")
	ErrAppReleaseNotFound   = errors.New("app release not found")
	ErrAnnouncementNotFound = errors.New("announcement not found")
	ErrDuplicateKey         = errors.New("duplicate key")
)

type ProductService struct {
	flagRepo    *repository.FeatureFlagRepository
	configRepo  *repository.RemoteConfigRepository
	releaseRepo *repository.AppReleaseRepository
	annRepo     *repository.AnnouncementRepository
}

func NewProductService(
	flagRepo *repository.FeatureFlagRepository,
	configRepo *repository.RemoteConfigRepository,
	releaseRepo *repository.AppReleaseRepository,
	annRepo *repository.AnnouncementRepository,
) *ProductService {
	return &ProductService{
		flagRepo:    flagRepo,
		configRepo:  configRepo,
		releaseRepo: releaseRepo,
		annRepo:     annRepo,
	}
}

// ==================== Feature Flags ====================

func (s *ProductService) CreateFeatureFlag(req dto.CreateFeatureFlagRequest) (*dto.FeatureFlagResponse, error) {
	flag := &model.FeatureFlag{
		Key:           req.Key,
		Name:          req.Name,
		Description:   req.Description,
		Enabled:       req.Enabled,
		Tiers:         req.Tiers,
		Platforms:     req.Platforms,
		MinAppVersion: req.MinAppVersion,
		Metadata:      req.Metadata,
	}

	if err := s.flagRepo.Create(flag); err != nil {
		if strings.Contains(err.Error(), "duplicate key") {
			return nil, ErrDuplicateKey
		}
		return nil, err
	}

	resp := dto.FeatureFlagToResponse(flag)
	return &resp, nil
}

func (s *ProductService) GetFeatureFlag(id uuid.UUID) (*dto.FeatureFlagResponse, error) {
	flag, err := s.flagRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrFeatureFlagNotFound
		}
		return nil, err
	}
	resp := dto.FeatureFlagToResponse(flag)
	return &resp, nil
}

func (s *ProductService) ListFeatureFlags() ([]dto.FeatureFlagResponse, error) {
	flags, err := s.flagRepo.List()
	if err != nil {
		return nil, err
	}
	return dto.FeatureFlagsToResponse(flags), nil
}

func (s *ProductService) UpdateFeatureFlag(id uuid.UUID, req dto.UpdateFeatureFlagRequest) (*dto.FeatureFlagResponse, error) {
	flag, err := s.flagRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrFeatureFlagNotFound
		}
		return nil, err
	}

	if req.Name != nil {
		flag.Name = *req.Name
	}
	if req.Description != nil {
		flag.Description = *req.Description
	}
	if req.Enabled != nil {
		flag.Enabled = *req.Enabled
	}
	if req.Tiers != nil {
		flag.Tiers = *req.Tiers
	}
	if req.Platforms != nil {
		flag.Platforms = *req.Platforms
	}
	if req.MinAppVersion != nil {
		flag.MinAppVersion = *req.MinAppVersion
	}
	if req.Metadata != nil {
		flag.Metadata = *req.Metadata
	}

	if err := s.flagRepo.Update(flag); err != nil {
		return nil, err
	}

	resp := dto.FeatureFlagToResponse(flag)
	return &resp, nil
}

func (s *ProductService) DeleteFeatureFlag(id uuid.UUID) error {
	_, err := s.flagRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrFeatureFlagNotFound
		}
		return err
	}
	return s.flagRepo.Delete(id)
}

// GetDeviceFlags returns enabled flags filtered by device tier and platform
func (s *ProductService) GetDeviceFlags(tier, platform string) ([]dto.DeviceFeatureFlagResponse, error) {
	flags, err := s.flagRepo.ListEnabled()
	if err != nil {
		return nil, err
	}

	var filtered []model.FeatureFlag
	for _, f := range flags {
		if matchesTier(f.Tiers, tier) && matchesPlatform(f.Platforms, platform) {
			filtered = append(filtered, f)
		}
	}

	return dto.FeatureFlagsToDeviceResponse(filtered), nil
}

// ==================== Remote Config ====================

func (s *ProductService) CreateRemoteConfig(req dto.CreateRemoteConfigRequest) (*dto.RemoteConfigResponse, error) {
	cfg := &model.RemoteConfig{
		Key:         req.Key,
		Value:       req.Value,
		ValueType:   req.ValueType,
		Description: req.Description,
	}

	if err := s.configRepo.Create(cfg); err != nil {
		if strings.Contains(err.Error(), "duplicate key") {
			return nil, ErrDuplicateKey
		}
		return nil, err
	}

	resp := dto.RemoteConfigToResponse(cfg)
	return &resp, nil
}

func (s *ProductService) GetRemoteConfig(id uuid.UUID) (*dto.RemoteConfigResponse, error) {
	cfg, err := s.configRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrRemoteConfigNotFound
		}
		return nil, err
	}
	resp := dto.RemoteConfigToResponse(cfg)
	return &resp, nil
}

func (s *ProductService) ListRemoteConfigs() ([]dto.RemoteConfigResponse, error) {
	configs, err := s.configRepo.List()
	if err != nil {
		return nil, err
	}
	return dto.RemoteConfigsToResponse(configs), nil
}

func (s *ProductService) UpdateRemoteConfig(id uuid.UUID, req dto.UpdateRemoteConfigRequest) (*dto.RemoteConfigResponse, error) {
	cfg, err := s.configRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrRemoteConfigNotFound
		}
		return nil, err
	}

	if req.Value != nil {
		cfg.Value = *req.Value
	}
	if req.ValueType != nil {
		cfg.ValueType = *req.ValueType
	}
	if req.Description != nil {
		cfg.Description = *req.Description
	}

	if err := s.configRepo.Update(cfg); err != nil {
		return nil, err
	}

	resp := dto.RemoteConfigToResponse(cfg)
	return &resp, nil
}

func (s *ProductService) DeleteRemoteConfig(id uuid.UUID) error {
	_, err := s.configRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrRemoteConfigNotFound
		}
		return err
	}
	return s.configRepo.Delete(id)
}

func (s *ProductService) GetDeviceConfig() ([]dto.DeviceRemoteConfigResponse, error) {
	configs, err := s.configRepo.List()
	if err != nil {
		return nil, err
	}
	return dto.RemoteConfigsToDeviceResponse(configs), nil
}

// ==================== App Releases ====================

func (s *ProductService) CreateAppRelease(req dto.CreateAppReleaseRequest) (*dto.AppReleaseResponse, error) {
	brand := req.Brand
	if brand == "" {
		brand = "svid"
	}
	release := &model.AppRelease{
		Version:      req.Version,
		Platform:     req.Platform,
		Channel:      req.Channel,
		Brand:        brand,
		ReleaseNotes: req.ReleaseNotes,
		DownloadURL:  req.DownloadURL,
		FileSize:     req.FileSize,
		Checksum:     req.Checksum,
		IsMandatory:  req.IsMandatory,
		IsActive:     req.IsActive,
	}

	if req.Publish {
		now := time.Now()
		release.PublishedAt = &now
	}

	if err := s.releaseRepo.Create(release); err != nil {
		return nil, err
	}

	resp := dto.AppReleaseToResponse(release)
	return &resp, nil
}

func (s *ProductService) GetAppRelease(id uuid.UUID) (*dto.AppReleaseResponse, error) {
	release, err := s.releaseRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrAppReleaseNotFound
		}
		return nil, err
	}
	resp := dto.AppReleaseToResponse(release)
	return &resp, nil
}

func (s *ProductService) ListAppReleases(page, perPage int, platform, channel string) ([]dto.AppReleaseResponse, int64, error) {
	page, perPage = pagination.Normalize(page, perPage, 20)

	releases, total, err := s.releaseRepo.List(page, perPage, platform, channel)
	if err != nil {
		return nil, 0, err
	}

	return dto.AppReleasesToResponse(releases), total, nil
}

func (s *ProductService) UpdateAppRelease(id uuid.UUID, req dto.UpdateAppReleaseRequest) (*dto.AppReleaseResponse, error) {
	release, err := s.releaseRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrAppReleaseNotFound
		}
		return nil, err
	}

	if req.ReleaseNotes != nil {
		release.ReleaseNotes = *req.ReleaseNotes
	}
	if req.DownloadURL != nil {
		release.DownloadURL = *req.DownloadURL
	}
	if req.FileSize != nil {
		release.FileSize = *req.FileSize
	}
	if req.Checksum != nil {
		release.Checksum = *req.Checksum
	}
	if req.IsMandatory != nil {
		release.IsMandatory = *req.IsMandatory
	}
	if req.IsActive != nil {
		release.IsActive = *req.IsActive
	}
	if req.Publish != nil && *req.Publish && release.PublishedAt == nil {
		now := time.Now()
		release.PublishedAt = &now
	}

	if err := s.releaseRepo.Update(release); err != nil {
		return nil, err
	}

	resp := dto.AppReleaseToResponse(release)
	return &resp, nil
}

func (s *ProductService) CheckForUpdate(platform, currentVersion, channel, brand string) (*dto.UpdateCheckResponse, error) {
	if channel == "" {
		channel = "stable"
	}
	if brand == "" {
		brand = "svid"
	}

	releases, err := s.releaseRepo.FindPublished(platform, channel, brand)
	if err != nil {
		return nil, err
	}

	// Find the release with the highest version
	var latest *model.AppRelease
	for i := range releases {
		if latest == nil || compareVersions(releases[i].Version, latest.Version) > 0 {
			latest = &releases[i]
		}
	}

	if latest == nil {
		return &dto.UpdateCheckResponse{
			UpdateAvailable: false,
			CurrentVersion:  currentVersion,
		}, nil
	}

	updateAvailable := compareVersions(latest.Version, currentVersion) > 0

	resp := &dto.UpdateCheckResponse{
		UpdateAvailable: updateAvailable,
		CurrentVersion:  currentVersion,
	}

	if updateAvailable {
		resp.LatestVersion = latest.Version
		resp.IsMandatory = latest.IsMandatory
		resp.ReleaseNotes = latest.ReleaseNotes
		resp.DownloadURL = latest.DownloadURL
		resp.FileSize = latest.FileSize
		resp.Checksum = latest.Checksum
		if latest.PublishedAt != nil {
			t := latest.PublishedAt.Format("2006-01-02T15:04:05Z07:00")
			resp.PublishedAt = &t
		}
	}

	return resp, nil
}

// RegisterCIRelease creates or updates AppRelease records from CI pipeline data.
// Deduplicates by (version, platform, channel) — safe for CI retries.
func (s *ProductService) RegisterCIRelease(version, channel, releaseNotes, brand string, isMandatory bool, platforms map[string]dto.CIReleasePlatformData) ([]dto.AppReleaseResponse, error) {
	if brand == "" {
		brand = "svid"
	}
	var results []dto.AppReleaseResponse

	for platform, data := range platforms {
		now := time.Now()

		existing, err := s.releaseRepo.FindByVersionPlatformChannelBrand(version, platform, channel, brand)
		if err == nil && existing != nil {
			existing.DownloadURL = data.DownloadURL
			existing.Checksum = data.Checksum
			existing.FileSize = data.FileSize
			existing.ReleaseNotes = releaseNotes
			existing.IsMandatory = isMandatory
			existing.IsActive = true
			if existing.PublishedAt == nil {
				existing.PublishedAt = &now
			}
			if err := s.releaseRepo.Update(existing); err != nil {
				return nil, err
			}
			results = append(results, dto.AppReleaseToResponse(existing))
			continue
		}

		release := &model.AppRelease{
			Version:      version,
			Platform:     platform,
			Channel:      channel,
			Brand:        brand,
			ReleaseNotes: releaseNotes,
			DownloadURL:  data.DownloadURL,
			FileSize:     data.FileSize,
			Checksum:     data.Checksum,
			IsMandatory:  isMandatory,
			IsActive:     true,
			PublishedAt:  &now,
		}
		if err := s.releaseRepo.Create(release); err != nil {
			return nil, err
		}
		results = append(results, dto.AppReleaseToResponse(release))
	}

	return results, nil
}

// ==================== Announcements ====================

func (s *ProductService) CreateAnnouncement(req dto.CreateAnnouncementRequest) (*dto.AnnouncementResponse, error) {
	ann := &model.Announcement{
		Title:           req.Title,
		Content:         req.Content,
		Type:            req.Type,
		TargetTiers:     req.TargetTiers,
		TargetPlatforms: req.TargetPlatforms,
		IsActive:        req.IsActive,
	}

	if req.StartsAt != nil {
		t, err := time.Parse(time.RFC3339, *req.StartsAt)
		if err == nil {
			ann.StartsAt = &t
		}
	}
	if req.ExpiresAt != nil {
		t, err := time.Parse(time.RFC3339, *req.ExpiresAt)
		if err == nil {
			ann.ExpiresAt = &t
		}
	}

	if err := s.annRepo.Create(ann); err != nil {
		return nil, err
	}

	resp := dto.AnnouncementToResponse(ann)
	return &resp, nil
}

func (s *ProductService) GetAnnouncement(id uuid.UUID) (*dto.AnnouncementResponse, error) {
	ann, err := s.annRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrAnnouncementNotFound
		}
		return nil, err
	}
	resp := dto.AnnouncementToResponse(ann)
	return &resp, nil
}

func (s *ProductService) ListAnnouncements(page, perPage int, annType string, activeOnly bool) ([]dto.AnnouncementResponse, int64, error) {
	page, perPage = pagination.Normalize(page, perPage, 20)

	announcements, total, err := s.annRepo.List(page, perPage, annType, activeOnly)
	if err != nil {
		return nil, 0, err
	}

	return dto.AnnouncementsToResponse(announcements), total, nil
}

func (s *ProductService) UpdateAnnouncement(id uuid.UUID, req dto.UpdateAnnouncementRequest) (*dto.AnnouncementResponse, error) {
	ann, err := s.annRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrAnnouncementNotFound
		}
		return nil, err
	}

	if req.Title != nil {
		ann.Title = *req.Title
	}
	if req.Content != nil {
		ann.Content = *req.Content
	}
	if req.Type != nil {
		ann.Type = *req.Type
	}
	if req.TargetTiers != nil {
		ann.TargetTiers = *req.TargetTiers
	}
	if req.TargetPlatforms != nil {
		ann.TargetPlatforms = *req.TargetPlatforms
	}
	if req.StartsAt != nil {
		t, err := time.Parse(time.RFC3339, *req.StartsAt)
		if err == nil {
			ann.StartsAt = &t
		}
	}
	if req.ExpiresAt != nil {
		t, err := time.Parse(time.RFC3339, *req.ExpiresAt)
		if err == nil {
			ann.ExpiresAt = &t
		}
	}
	if req.IsActive != nil {
		ann.IsActive = *req.IsActive
	}

	if err := s.annRepo.Update(ann); err != nil {
		return nil, err
	}

	resp := dto.AnnouncementToResponse(ann)
	return &resp, nil
}

func (s *ProductService) DeleteAnnouncement(id uuid.UUID) error {
	_, err := s.annRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrAnnouncementNotFound
		}
		return err
	}
	return s.annRepo.Delete(id)
}

// GetDeviceAnnouncements returns active announcements filtered by tier and platform
func (s *ProductService) GetDeviceAnnouncements(tier, platform string) ([]dto.DeviceAnnouncementResponse, error) {
	announcements, err := s.annRepo.ListActive()
	if err != nil {
		return nil, err
	}

	var filtered []model.Announcement
	for _, a := range announcements {
		if matchesTier(a.TargetTiers, tier) && matchesPlatform(a.TargetPlatforms, platform) {
			filtered = append(filtered, a)
		}
	}

	return dto.AnnouncementsToDeviceResponse(filtered), nil
}

// ==================== Stats ====================

func (s *ProductService) GetProductStats() (map[string]interface{}, error) {
	flagCount, _ := s.flagRepo.CountAll()
	flagEnabled, _ := s.flagRepo.CountEnabled()
	configCount, _ := s.configRepo.CountAll()
	releaseCount, _ := s.releaseRepo.CountAll()
	releaseActive, _ := s.releaseRepo.CountActive()
	annCount, _ := s.annRepo.CountAll()
	annActive, _ := s.annRepo.CountActive()

	return map[string]interface{}{
		"feature_flags": map[string]int64{
			"total":   flagCount,
			"enabled": flagEnabled,
		},
		"remote_configs": map[string]int64{
			"total": configCount,
		},
		"releases": map[string]int64{
			"total":  releaseCount,
			"active": releaseActive,
		},
		"announcements": map[string]int64{
			"total":  annCount,
			"active": annActive,
		},
	}, nil
}

// ==================== Helpers ====================

// matchesTier checks if the device tier is included in the JSON array of tiers.
// Empty tiers string means "all tiers".
func matchesTier(tiersJSON, deviceTier string) bool {
	if tiersJSON == "" || tiersJSON == "[]" {
		return true // no restriction
	}
	var tiers []string
	if err := json.Unmarshal([]byte(tiersJSON), &tiers); err != nil {
		return true // if parse fails, allow access
	}
	if len(tiers) == 0 {
		return true
	}
	for _, t := range tiers {
		if strings.EqualFold(t, deviceTier) {
			return true
		}
	}
	return false
}

// matchesPlatform checks if the device platform is included in the JSON array of platforms.
// Empty platforms string means "all platforms".
func matchesPlatform(platformsJSON, devicePlatform string) bool {
	if platformsJSON == "" || platformsJSON == "[]" {
		return true // no restriction
	}
	var platforms []string
	if err := json.Unmarshal([]byte(platformsJSON), &platforms); err != nil {
		return true // if parse fails, allow access
	}
	if len(platforms) == 0 {
		return true
	}
	for _, p := range platforms {
		if strings.EqualFold(p, devicePlatform) {
			return true
		}
	}
	return false
}

// compareVersions compares two semver strings (e.g., "1.2.3" vs "1.2.4").
// Returns >0 if a > b, <0 if a < b, 0 if equal.
func compareVersions(a, b string) int {
	aParts := strings.Split(a, ".")
	bParts := strings.Split(b, ".")

	maxLen := len(aParts)
	if len(bParts) > maxLen {
		maxLen = len(bParts)
	}

	for i := 0; i < maxLen; i++ {
		aVal := 0
		bVal := 0
		if i < len(aParts) {
			aVal = parseVersionPart(aParts[i])
		}
		if i < len(bParts) {
			bVal = parseVersionPart(bParts[i])
		}
		if aVal != bVal {
			return aVal - bVal
		}
	}
	return 0
}

func parseVersionPart(s string) int {
	val := 0
	for _, c := range s {
		if c >= '0' && c <= '9' {
			val = val*10 + int(c-'0')
		} else {
			break // stop at non-numeric (e.g., "1-beta")
		}
	}
	return val
}
