package dto

type RegisterDeviceRequest struct {
	HardwareID       string `json:"hardware_id" binding:"required,min=8,max=255"`
	LegacyHardwareID string `json:"legacy_hardware_id" binding:"max=255"` // Old fingerprint for migration
	Brand            string `json:"brand" binding:"omitempty,oneof=ssvid vidcombo"`
	OS               string `json:"os" binding:"required,oneof=macos windows linux"`
	OSVersion        string `json:"os_version" binding:"max=50"`
	AppVersion       string `json:"app_version" binding:"required,max=20"`
	DeviceName       string `json:"device_name" binding:"max=255"`
}

type HeartbeatRequest struct {
	AppVersion string `json:"app_version" binding:"required,max=20"`
	Brand      string `json:"brand" binding:"omitempty,oneof=ssvid vidcombo"`
	Tier       string `json:"tier" binding:"omitempty,oneof=free premium"`
}
