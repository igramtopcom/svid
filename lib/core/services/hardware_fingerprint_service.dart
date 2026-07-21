import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../config/brand_config.dart';
import '../logging/app_logger.dart';

/// Generates a stable, unique hardware fingerprint per machine.
///
/// Uses platform-specific hardware identifiers:
/// - macOS: IOPlatformUUID (from ioreg)
/// - Windows: MachineGuid (from HKLM registry)
/// - Linux: /etc/machine-id
///
/// The raw UUID is SHA-256 hashed with a brand-specific salt to prevent
/// cross-app and cross-brand fingerprint correlation.
class HardwareFingerprintService {
  static String get _salt => '${BrandConfig.current.brand.name}_v2_desktop';

  /// Generate the new strong hardware fingerprint.
  /// Returns `desktop_v2_{first16HexOfSHA256}` or null if extraction fails.
  static Future<String?> generateFingerprint() async {
    try {
      final platformUuid = await _getPlatformUuid();
      if (platformUuid == null || platformUuid.isEmpty) {
        appLogger.warning('Platform UUID extraction returned empty');
        return null;
      }

      final salted = '$_salt:$platformUuid';
      final hash = sha256.convert(utf8.encode(salted)).toString();
      final fingerprint = 'desktop_v2_${hash.substring(0, 16)}';

      appLogger.debug('Generated hardware fingerprint: $fingerprint');
      return fingerprint;
    } catch (e) {
      appLogger.warning('Hardware fingerprint generation failed: $e');
      return null;
    }
  }

  /// Generate the legacy fingerprint (for migration dual-send).
  /// Must match the old `_generateHardwareId()` exactly.
  static String generateLegacyFingerprint() {
    final hostname = Platform.localHostname;
    final os = Platform.operatingSystem;
    final osVersion = Platform.operatingSystemVersion;
    final raw = '$hostname-$os-$osVersion';
    var hash = 0;
    for (var i = 0; i < raw.length; i++) {
      hash = ((hash << 5) - hash + raw.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return 'desktop_${hash.toRadixString(16).padLeft(8, '0')}_$hostname';
  }

  /// Get the raw platform UUID without hashing.
  /// Used by VidCombo adapter for backward-compatible device_id matching.
  static Future<String?> getRawPlatformUuid() => _getPlatformUuid();

  /// Extract platform-specific hardware UUID.
  static Future<String?> _getPlatformUuid() async {
    if (Platform.isMacOS) return _getMacOsUuid();
    if (Platform.isWindows) return _getWindowsUuid();
    if (Platform.isLinux) return _getLinuxUuid();
    return null;
  }

  /// macOS: IOPlatformUUID from ioreg.
  /// Available to all users, stable across reboots and OS updates.
  static Future<String?> _getMacOsUuid() async {
    final result = await Process.run('ioreg', [
      '-rd1',
      '-c',
      'IOPlatformExpertDevice',
    ]);
    if (result.exitCode != 0) return null;

    final output = result.stdout as String;
    // Parse: "IOPlatformUUID" = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
    final match = RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"').firstMatch(output);
    return match?.group(1);
  }

  /// Windows: MachineGuid from HKLM\SOFTWARE\Microsoft\Cryptography.
  /// Readable by all users, stable across reboots. Changes on OS reinstall.
  static Future<String?> _getWindowsUuid() async {
    final result = await Process.run('reg', [
      'query',
      r'HKLM\SOFTWARE\Microsoft\Cryptography',
      '/v',
      'MachineGuid',
    ]);
    if (result.exitCode != 0) return null;

    final output = result.stdout as String;
    // Parse: MachineGuid    REG_SZ    xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    final match = RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)').firstMatch(output);
    return match?.group(1);
  }

  /// Linux: /etc/machine-id — stable per installation, readable by all users.
  static Future<String?> _getLinuxUuid() async {
    final file = File('/etc/machine-id');
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    return content.trim();
  }
}
