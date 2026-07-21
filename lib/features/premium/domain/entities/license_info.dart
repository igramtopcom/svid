import 'license_device.dart';

/// Server-side license information fetched from `GET /api/v1/premium/license`.
///
/// This provides authoritative subscription data including real device counts,
/// max devices per plan, and the full list of registered devices.
class LicenseInfo {
  final String tier;
  final DateTime? expiresAt;
  final bool isAutoRenew;
  final String billingCycle;
  final String paymentMethod;
  final int deviceCount;
  final int maxDevices;
  final String licenseKey;
  final DateTime? cancelledAt;
  final List<LicenseDevice> devices;

  const LicenseInfo({
    required this.tier,
    this.expiresAt,
    required this.isAutoRenew,
    required this.billingCycle,
    required this.paymentMethod,
    required this.deviceCount,
    required this.maxDevices,
    required this.licenseKey,
    this.cancelledAt,
    this.devices = const [],
  });

  bool get isPremium => tier == 'premium';
  bool get isCancelled => cancelledAt != null;

  factory LicenseInfo.fromJson(Map<String, dynamic> json) {
    return LicenseInfo(
      tier: json['tier'] as String? ?? 'free',
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
      isAutoRenew: json['is_auto_renew'] as bool? ?? false,
      billingCycle: json['billing_cycle'] as String? ?? '',
      paymentMethod: json['payment_method'] as String? ?? '',
      deviceCount: json['device_count'] as int? ?? 0,
      maxDevices: json['max_devices'] as int? ?? 1,
      licenseKey: json['license_key'] as String? ?? '',
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.tryParse(json['cancelled_at'] as String)
          : null,
      devices: json['devices'] != null
          ? LicenseDevice.listFromJson(json['devices'])
          : [],
    );
  }
}
