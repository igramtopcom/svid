import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../../../core/config/brand_config.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/logging/app_logger.dart';
import '../../../../../core/network/shared_http_client.dart';

class YouTubePotProviderPaths {
  final String pluginDir;
  final String cliPath;

  const YouTubePotProviderPaths({
    required this.pluginDir,
    required this.cliPath,
  });
}

class YouTubePotProviderService {
  YouTubePotProviderService({http.Client? client})
    : _client = client ?? SharedHttpClient.instance;

  static const _version = 'v0.8.1';
  static const _releaseBase =
      'https://github.com/jim60105/bgutil-ytdlp-pot-provider-rs/releases/download/$_version';
  static const _pluginAsset = 'bgutil-ytdlp-pot-provider-rs.zip';
  static const _pluginPackageDirName = 'bgutil-ytdlp-pot-provider-rs';
  static const _cliSha256ByAsset = <String, String>{
    // v0.8.1, bgutil-pot-windows-x86_64.exe
    'bgutil-pot-windows-x86_64.exe':
        '25d6b05c79176aa792454c3d1727922ca47e56cf11cb1e866615d751819b14a0',
  };

  final http.Client _client;
  Future<YouTubePotProviderPaths?>? _inFlight;

  Future<YouTubePotProviderPaths?> ensureInstalled({
    bool downloadIfMissing = true,
  }) {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _ensureInstalled(downloadIfMissing: downloadIfMissing);
    _inFlight = future;
    return future.whenComplete(() {
      _inFlight = null;
    });
  }

  Future<YouTubePotProviderPaths?> _ensureInstalled({
    required bool downloadIfMissing,
  }) async {
    final cliAsset = _cliAssetName();
    if (cliAsset == null) {
      appLogger.info('[YouTube POT] Unsupported platform for bgutil provider');
      return null;
    }

    final appSupport = await getApplicationSupportDirectory();
    final rootDir = path.join(appSupport.path, 'bin', 'youtube-pot', _version);
    final cliPath = path.join(rootDir, _normalizedCliFileName(cliAsset));
    final pluginRoot = path.join(rootDir, 'plugins');
    final pluginPackageDir = path.join(pluginRoot, _pluginPackageDirName);
    final pluginMarker = path.join(
      pluginPackageDir,
      'yt_dlp_plugins',
      'extractor',
      'getpot_bgutil_cli.py',
    );
    final expectedCliSha256 = _cliSha256ByAsset[cliAsset];

    if (await File(cliPath).exists() && await File(pluginMarker).exists()) {
      if (expectedCliSha256 != null &&
          !await _fileMatchesSha256(File(cliPath), expectedCliSha256)) {
        appLogger.warning(
          '[YouTube POT] Existing bgutil CLI hash mismatch; reinstalling: '
          'cli=$cliPath',
        );
        try {
          await File(cliPath).delete();
        } catch (_) {}
      } else {
        appLogger.info(
          '[YouTube POT] Provider ready $_version: '
          'pluginDir=$pluginRoot cli=$cliPath',
        );
        return YouTubePotProviderPaths(pluginDir: pluginRoot, cliPath: cliPath);
      }
    }

    if (await File(cliPath).exists() && await File(pluginMarker).exists()) {
      return YouTubePotProviderPaths(pluginDir: pluginRoot, cliPath: cliPath);
    }

    if (!downloadIfMissing) return null;

    try {
      await Directory(rootDir).create(recursive: true);
      await _downloadFile(
        Uri.parse('$_releaseBase/$cliAsset'),
        File(cliPath),
        expectedSha256: expectedCliSha256,
      );
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', cliPath]);
      }

      final zipPath = path.join(rootDir, _pluginAsset);
      await _downloadFile(
        Uri.parse('$_releaseBase/$_pluginAsset'),
        File(zipPath),
      );
      await _extractPlugin(File(zipPath), Directory(pluginPackageDir));

      if (!await File(pluginMarker).exists()) {
        throw StateError(
          'Plugin marker missing after extraction: $pluginMarker',
        );
      }

      appLogger.info(
        '[YouTube POT] Installed bgutil provider $_version: '
        'pluginDir=$pluginRoot cli=$cliPath',
      );
      return YouTubePotProviderPaths(pluginDir: pluginRoot, cliPath: cliPath);
    } catch (e, st) {
      appLogger.warning('[YouTube POT] Provider unavailable: $e', e, st);
      return null;
    }
  }

  Future<void> _downloadFile(
    Uri uri,
    File target, {
    String? expectedSha256,
  }) async {
    final temp = File('${target.path}.download');
    await target.parent.create(recursive: true);

    final request = http.Request('GET', uri);
    request.headers['User-Agent'] =
        '${BrandConfig.current.appName}/${AppConstants.appVersion}';

    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw HttpException(
        'HTTP ${response.statusCode} downloading $uri',
        uri: uri,
      );
    }

    final sink = temp.openWrite();
    try {
      await response.stream.timeout(const Duration(seconds: 60)).pipe(sink);
    } finally {
      await sink.close();
    }

    if (expectedSha256 != null) {
      final actualSha256 = await _sha256Of(temp);
      if (actualSha256.toLowerCase() != expectedSha256.toLowerCase()) {
        try {
          await temp.delete();
        } catch (_) {}
        throw StateError(
          'SHA256 mismatch for ${path.basename(target.path)}: '
          'expected=$expectedSha256 actual=$actualSha256',
        );
      }
      appLogger.info(
        '[YouTube POT] Verified SHA256 for ${path.basename(target.path)}',
      );
    }

    if (await target.exists()) {
      await target.delete();
    }
    await temp.rename(target.path);
  }

  Future<bool> _fileMatchesSha256(File file, String expectedSha256) async {
    if (!await file.exists()) return false;
    final actualSha256 = await _sha256Of(file);
    return actualSha256.toLowerCase() == expectedSha256.toLowerCase();
  }

  Future<String> _sha256Of(File file) async {
    return sha256.convert(await file.readAsBytes()).toString();
  }

  Future<void> _extractPlugin(File zipFile, Directory targetDir) async {
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    final targetRoot = path.normalize(path.absolute(targetDir.path));
    final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());

    for (final entry in archive.files) {
      final entryName = entry.name.replaceAll('\\', '/');
      final outputPath = path.normalize(
        path.absolute(targetDir.path, entryName),
      );
      final insideTarget =
          outputPath == targetRoot || path.isWithin(targetRoot, outputPath);
      if (!insideTarget) {
        throw StateError(
          'Refusing zip entry outside plugin dir: ${entry.name}',
        );
      }

      if (entry.isFile) {
        final file = File(outputPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.content as List<int>, flush: true);
      } else {
        await Directory(outputPath).create(recursive: true);
      }
    }
  }

  String? _cliAssetName() {
    if (Platform.isWindows) return 'bgutil-pot-windows-x86_64.exe';
    if (Platform.isLinux) return 'bgutil-pot-linux-x86_64';
    if (Platform.isMacOS) {
      return _isAppleSilicon()
          ? 'bgutil-pot-macos-aarch64'
          : 'bgutil-pot-macos-x86_64';
    }
    return null;
  }

  String _normalizedCliFileName(String assetName) {
    return Platform.isWindows ? 'bgutil-pot.exe' : 'bgutil-pot';
  }

  bool _isAppleSilicon() {
    try {
      final result = Process.runSync('uname', ['-m']);
      return result.stdout.toString().trim() == 'arm64';
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static String get versionForTesting => _version;
}
