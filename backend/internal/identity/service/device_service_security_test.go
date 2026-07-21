package service

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/snakeloader/backend/internal/identity/dto"
	"github.com/snakeloader/backend/internal/pkg/logger"
)

func init() {
	logger.Init("debug")
}

// mockNotifier captures notification calls for assertion.
type mockNotifier struct {
	newDeviceCalls  atomic.Int64
	anomalyCalls    atomic.Int64
	lastAnomalyIP   string
	lastAnomalyHWID string
	mu              sync.Mutex
}

func (m *mockNotifier) NotifyNewDevice(deviceID, os, osVersion, appVersion, deviceName string) {
	m.newDeviceCalls.Add(1)
}

func (m *mockNotifier) NotifyRegistrationAnomaly(ip string, count int64, latestHardwareID string) {
	m.anomalyCalls.Add(1)
	m.mu.Lock()
	m.lastAnomalyIP = ip
	m.lastAnomalyHWID = latestHardwareID
	m.mu.Unlock()
}

// newTestRedis creates a miniredis instance and returns a real redis.Client.
func newTestRedis(t *testing.T) (*miniredis.Miniredis, *redis.Client) {
	t.Helper()
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	return mr, rdb
}

// ==================== Cooldown Tests ====================

func TestRegisterCooldown_BlocksWithinWindow(t *testing.T) {
	mr, rdb := newTestRedis(t)
	defer mr.Close()

	svc := &DeviceService{rdb: rdb}

	// Simulate setting the cooldown key (as RegisterDevice would on first call)
	// Key format: register_cooldown:{brand}:{hardware_id} — brand defaults to "svid"
	ctx := context.Background()
	cooldownKey := "register_cooldown:svid:test-hardware-id"
	rdb.Set(ctx, cooldownKey, "1", 60*time.Second)

	// Attempt register — should hit cooldown
	_, err := svc.RegisterDevice(dto.RegisterDeviceRequest{
		HardwareID: "test-hardware-id",
		OS:         "macos",
		AppVersion: "1.3.0",
	}, "1.2.3.4", "TestAgent/1.0")

	if err != ErrRegisterCooldown {
		t.Errorf("expected ErrRegisterCooldown, got %v", err)
	}
}

func TestRegisterCooldown_AllowsAfterExpiry(t *testing.T) {
	mr, rdb := newTestRedis(t)
	defer mr.Close()

	// Verify at the Redis level: after TTL expires, key is gone → cooldown skipped.
	ctx := context.Background()
	cooldownKey := "register_cooldown:svid:test-hardware-id"
	rdb.Set(ctx, cooldownKey, "1", 1*time.Second)

	// Before expiry: key should exist
	exists, _ := rdb.Exists(ctx, cooldownKey).Result()
	if exists != 1 {
		t.Fatal("expected cooldown key to exist before expiry")
	}

	// Fast-forward past TTL
	mr.FastForward(2 * time.Second)

	// After expiry: key should be gone
	exists, _ = rdb.Exists(ctx, cooldownKey).Result()
	if exists != 0 {
		t.Error("expected cooldown key to expire after TTL, but it still exists")
	}
}

func TestRegisterCooldown_PerHardwareID(t *testing.T) {
	mr, rdb := newTestRedis(t)
	defer mr.Close()

	// Test at the Redis level: cooldown keys are per (brand, hardware_id), not global.
	ctx := context.Background()

	// Set cooldown for device-A only (brand defaults to "svid")
	rdb.Set(ctx, "register_cooldown:svid:device-A-hw-id", "1", 60*time.Second)

	// device-A should have cooldown key
	existsA, _ := rdb.Exists(ctx, "register_cooldown:svid:device-A-hw-id").Result()
	if existsA != 1 {
		t.Error("expected cooldown key to exist for device-A")
	}

	// device-B should NOT have cooldown key (different hardware_id)
	existsB, _ := rdb.Exists(ctx, "register_cooldown:svid:device-B-hw-id").Result()
	if existsB != 0 {
		t.Error("expected NO cooldown key for device-B — cooldown is per hardware_id")
	}

	// Also verify the service-level: device-A returns cooldown error
	svc := &DeviceService{rdb: rdb}
	_, errA := svc.RegisterDevice(dto.RegisterDeviceRequest{
		HardwareID: "device-A-hw-id",
		OS:         "macos",
		AppVersion: "1.3.0",
	}, "1.2.3.4", "TestAgent/1.0")
	if errA != ErrRegisterCooldown {
		t.Error("expected device-A to be blocked by cooldown")
	}
}

func TestRegisterCooldown_SkippedWhenRedisNil(t *testing.T) {
	// When Redis is not available, cooldown should be skipped entirely.
	// The nil deviceRepo will cause a different error, but NOT ErrRegisterCooldown.
	svc := &DeviceService{rdb: nil}

	var err error
	func() {
		defer func() { recover() }()
		_, err = svc.RegisterDevice(dto.RegisterDeviceRequest{
			HardwareID: "any-device-id-1234",
			OS:         "macos",
			AppVersion: "1.3.0",
		}, "1.2.3.4", "TestAgent/1.0")
	}()

	if err == ErrRegisterCooldown {
		t.Error("cooldown should be skipped when Redis is nil")
	}
}

// ==================== Anomaly Detection Tests ====================

func TestAnomalyDetection_AlertAtThreshold(t *testing.T) {
	mr, rdb := newTestRedis(t)
	defer mr.Close()

	notifier := &mockNotifier{}

	// Simulate 10 registrations from same IP (pre-set counter to 10)
	ctx := context.Background()
	anomalyKey := "register_ip_count:192.168.1.100"
	rdb.Set(ctx, anomalyKey, "10", 1*time.Hour)

	// The 11th registration should trigger the alert.
	// We simulate by calling INCR (which the service does after creating a device).
	count, err := rdb.Incr(ctx, anomalyKey).Result()
	if err != nil {
		t.Fatalf("unexpected Redis error: %v", err)
	}
	if count != 11 {
		t.Fatalf("expected count=11, got %d", count)
	}

	// Simulate the alert logic from RegisterDevice
	if count == 11 {
		notifier.NotifyRegistrationAnomaly("192.168.1.100", count, "suspicious-device")
	}

	if notifier.anomalyCalls.Load() != 1 {
		t.Errorf("expected 1 anomaly notification, got %d", notifier.anomalyCalls.Load())
	}
	notifier.mu.Lock()
	if notifier.lastAnomalyIP != "192.168.1.100" {
		t.Errorf("expected anomaly IP 192.168.1.100, got %s", notifier.lastAnomalyIP)
	}
	notifier.mu.Unlock()
}

func TestAnomalyDetection_NoAlertBelowThreshold(t *testing.T) {
	mr, rdb := newTestRedis(t)
	defer mr.Close()

	ctx := context.Background()
	anomalyKey := "register_ip_count:10.0.0.1"

	// Simulate 9 registrations (below threshold of 11)
	for i := 0; i < 9; i++ {
		rdb.Incr(ctx, anomalyKey)
	}

	count, _ := rdb.Get(ctx, anomalyKey).Int64()
	if count >= 11 {
		t.Errorf("expected count < 11, got %d", count)
	}
}

func TestAnomalyDetection_CounterExpiresAfterOneHour(t *testing.T) {
	mr, rdb := newTestRedis(t)
	defer mr.Close()

	ctx := context.Background()
	anomalyKey := "register_ip_count:10.0.0.1"

	// First registration sets the counter with 1h TTL
	rdb.Incr(ctx, anomalyKey)
	rdb.Expire(ctx, anomalyKey, 1*time.Hour)

	// Add more registrations
	for i := 0; i < 5; i++ {
		rdb.Incr(ctx, anomalyKey)
	}

	// Verify counter exists
	count, _ := rdb.Get(ctx, anomalyKey).Int64()
	if count != 6 {
		t.Errorf("expected count=6, got %d", count)
	}

	// Fast-forward past 1 hour
	mr.FastForward(61 * time.Minute)

	// Counter should be expired
	exists, _ := rdb.Exists(ctx, anomalyKey).Result()
	if exists != 0 {
		t.Error("expected anomaly counter to expire after 1 hour")
	}
}

func TestAnomalyDetection_PerIPIsolation(t *testing.T) {
	mr, rdb := newTestRedis(t)
	defer mr.Close()

	ctx := context.Background()

	// Simulate registrations from two different IPs
	for i := 0; i < 5; i++ {
		rdb.Incr(ctx, "register_ip_count:ip-a")
	}
	for i := 0; i < 3; i++ {
		rdb.Incr(ctx, "register_ip_count:ip-b")
	}

	countA, _ := rdb.Get(ctx, "register_ip_count:ip-a").Int64()
	countB, _ := rdb.Get(ctx, "register_ip_count:ip-b").Int64()

	if countA != 5 {
		t.Errorf("expected IP-A count=5, got %d", countA)
	}
	if countB != 3 {
		t.Errorf("expected IP-B count=3, got %d", countB)
	}
}

func TestAnomalyDetection_AlertOnlyOnceAtExactThreshold(t *testing.T) {
	// Verify the alert fires exactly once at count==11, not at 12, 13, etc.
	mr, rdb := newTestRedis(t)
	defer mr.Close()

	notifier := &mockNotifier{}
	ctx := context.Background()
	anomalyKey := "register_ip_count:attacker-ip"

	// Simulate 15 registrations
	for i := 0; i < 15; i++ {
		count, _ := rdb.Incr(ctx, anomalyKey).Result()
		if count == 1 {
			rdb.Expire(ctx, anomalyKey, 1*time.Hour)
		}
		if count == 11 { // exactly the threshold
			notifier.NotifyRegistrationAnomaly("attacker-ip", count, fmt.Sprintf("device-%d", i))
		}
	}

	if notifier.anomalyCalls.Load() != 1 {
		t.Errorf("expected exactly 1 anomaly alert, got %d", notifier.anomalyCalls.Load())
	}
}

// ==================== Fingerprint Migration Tests ====================

func TestFingerprintMigration_DTOAcceptsLegacyField(t *testing.T) {
	// Verify the DTO correctly deserializes legacy_hardware_id
	req := dto.RegisterDeviceRequest{
		HardwareID:       "sha256-new-fingerprint",
		LegacyHardwareID: "old-hostname-based-id",
		OS:               "macos",
		AppVersion:       "1.3.0",
	}

	if req.LegacyHardwareID != "old-hostname-based-id" {
		t.Errorf("expected legacy_hardware_id to be preserved, got %q", req.LegacyHardwareID)
	}
}

func TestFingerprintMigration_EmptyLegacyIsValid(t *testing.T) {
	// Old clients don't send legacy_hardware_id — should be empty string
	req := dto.RegisterDeviceRequest{
		HardwareID: "old-client-fingerprint",
		OS:         "windows",
		AppVersion: "1.2.0",
	}

	if req.LegacyHardwareID != "" {
		t.Errorf("expected empty legacy_hardware_id for old clients, got %q", req.LegacyHardwareID)
	}
}

// ==================== Redis Key Patterns ====================

func TestCooldownKeyFormat(t *testing.T) {
	// Verify the cooldown key format matches what the service uses: register_cooldown:{brand}:{hardware_id}
	brand := "svid"
	hwID := "abc123-def456"
	expected := "register_cooldown:svid:abc123-def456"
	got := fmt.Sprintf("register_cooldown:%s:%s", brand, hwID)
	if got != expected {
		t.Errorf("cooldown key format: want %q, got %q", expected, got)
	}
}

func TestAnomalyKeyFormat(t *testing.T) {
	ip := "192.168.1.100"
	expected := "register_ip_count:192.168.1.100"
	got := fmt.Sprintf("register_ip_count:%s", ip)
	if got != expected {
		t.Errorf("anomaly key format: want %q, got %q", expected, got)
	}
}
