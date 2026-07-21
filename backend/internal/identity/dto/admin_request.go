package dto

type AdminLoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=8"`
}

type UpdateDeviceRequest struct {
	Tier     *string `json:"tier,omitempty" binding:"omitempty,oneof=free pro"`
	IsActive *bool   `json:"is_active,omitempty"`
}
