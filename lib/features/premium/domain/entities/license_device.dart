/// A device registered to a premium license.
///
/// Returned by `GET /api/v1/premium/devices` and embedded in [LicenseInfo].
class LicenseDevice {
  final String id;
  final String licenseId;
  final String deviceId;
  final String? deviceName;
  final String? os;
  final String? osVersion;
  final String? appVersion;
  final DateTime registeredAt;
  final DateTime lastVerifiedAt;

  const LicenseDevice({
    required this.id,
    required this.licenseId,
    required this.deviceId,
    this.deviceName,
    this.os,
    this.osVersion,
    this.appVersion,
    required this.registeredAt,
    required this.lastVerifiedAt,
  });

  /// Human-readable display name for this device.
  /// Falls back to truncated device ID if no name is available.
  String get displayName {
    if (deviceName != null && deviceName!.isNotEmpty) return deviceName!;
    if (deviceId.length > 8) return '${deviceId.substring(0, 8)}...';
    return deviceId;
  }

  /// OS label (e.g. "macOS 15.3" or "Windows").
  String get osLabel {
    if (os == null || os!.isEmpty) return 'Desktop';
    if (osVersion != null && osVersion!.isNotEmpty) return '$os $osVersion';
    return os!;
  }

  factory LicenseDevice.fromJson(Map<String, dynamic> json) {
    return LicenseDevice(
      id: json['id'] as String? ?? '',
      licenseId: json['license_id'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      deviceName: json['device_name'] as String?,
      os: json['os'] as String?,
      osVersion: json['os_version'] as String?,
      appVersion: json['app_version'] as String?,
      registeredAt: json['registered_at'] != null
          ? DateTime.parse(json['registered_at'] as String)
          : DateTime.now(),
      lastVerifiedAt: json['last_verified_at'] != null
          ? DateTime.parse(json['last_verified_at'] as String)
          : DateTime.now(),
    );
  }

  static List<LicenseDevice> listFromJson(dynamic json) {
    if (json is! List) return [];
    return json
        .map((e) => LicenseDevice.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
