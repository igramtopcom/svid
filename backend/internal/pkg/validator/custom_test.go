package validator

import (
	"testing"

	"github.com/go-playground/validator/v10"
)

func TestRegister_LicenseKey(t *testing.T) {
	v := validator.New()
	if err := Register(v); err != nil {
		t.Fatalf("Register: %v", err)
	}

	type payload struct {
		Key string `validate:"required,license_key"`
	}

	tests := []struct {
		name string
		key  string
		ok   bool
	}{
		{"svid 44-char", "SVID-d96d-34d2-1c85-22d4-4f50-ca2e-446f-acda", true},
		{"vidcombo 48-char", "VIDCOMBO-2341-3433-856b-c760-d6fc-0481-d2b1-394d", true},
		{"empty", "", false},
		{"unknown prefix", "FOO-d96d-34d2-1c85-22d4-4f50-ca2e-446f-acda", false},
		{"missing dashes", "SVIDd96d34d21c8522d44f50ca2e446facda", false},
		{"uppercase hex rejected", "SVID-D96D-34D2-1C85-22D4-4F50-CA2E-446F-ACDA", false},
		{"too few groups", "SVID-d96d-34d2-1c85", false},
		{"too many groups", "SVID-d96d-34d2-1c85-22d4-4f50-ca2e-446f-acda-aaaa", false},
		{"non-hex group", "SVID-d96d-34d2-1c85-22d4-4f50-ca2e-446f-zzzz", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := v.Struct(payload{Key: tt.key})
			got := err == nil
			if got != tt.ok {
				t.Errorf("key=%q ok=%v want=%v err=%v", tt.key, got, tt.ok, err)
			}
		})
	}
}
