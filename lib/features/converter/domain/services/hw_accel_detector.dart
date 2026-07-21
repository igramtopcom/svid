import '../../../../core/binaries/binary_manager.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/process_helper.dart';
import '../entities/hw_accel_info.dart';

/// Detects available hardware acceleration capabilities by querying ffmpeg.
///
/// Runs `ffmpeg -hwaccels` and `ffmpeg -encoders` to determine what
/// hardware-accelerated encoding is available on the current system.
class HwAccelDetector {
  final BinaryManager _binaryManager;

  HwAccelDetector(this._binaryManager);

  /// Detect all available hardware accelerators and their encoder support.
  Future<List<HwAccelInfo>> detect() async {
    final ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    if (ffmpegPath == null) return [];

    try {
      final hwAccels = await _getHwAccels(ffmpegPath);
      final encoders = await _getHwEncoders(ffmpegPath);
      final decoders = await _getHwDecoders(ffmpegPath);

      final results = <HwAccelInfo>[];
      for (final accel in hwAccels) {
        final accelEncoders = encoders
            .where((e) => _matchesAccel(e, accel))
            .toList();
        final accelDecoders = decoders
            .where((d) => _matchesAccel(d, accel))
            .toList();

        results.add(HwAccelInfo(
          name: accel,
          encoders: accelEncoders,
          decoders: accelDecoders,
          isAvailable: true,
        ));
      }

      appLogger.info('[HwAccelDetector] Found ${results.length} accelerators: '
          '${results.map((r) => r.name).join(', ')}');

      return results;
    } catch (e) {
      appLogger.error('[HwAccelDetector] Detection failed', e);
      return [];
    }
  }

  /// Run `ffmpeg -hwaccels` to get list of available accelerators.
  Future<List<String>> _getHwAccels(String ffmpegPath) async {
    final result = await ProcessHelper.run(
      ffmpegPath,
      ['-hwaccels', '-hide_banner'],
    );

    if (result.exitCode != 0) return [];

    final output = result.stdout as String;
    final lines = output.split('\n');

    // Output format:
    // Hardware acceleration methods:
    // videotoolbox
    // ...
    final accels = <String>[];
    var started = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.contains('Hardware acceleration methods')) {
        started = true;
        continue;
      }
      if (started && trimmed.isNotEmpty) {
        accels.add(trimmed);
      }
    }

    return accels;
  }

  /// Run `ffmpeg -encoders` and extract hardware-accelerated encoder names.
  Future<List<String>> _getHwEncoders(String ffmpegPath) async {
    final result = await ProcessHelper.run(
      ffmpegPath,
      ['-encoders', '-hide_banner'],
    );

    if (result.exitCode != 0) return [];

    final output = result.stdout as String;
    return _extractHwCodecs(output);
  }

  /// Run `ffmpeg -decoders` and extract hardware-accelerated decoder names.
  Future<List<String>> _getHwDecoders(String ffmpegPath) async {
    final result = await ProcessHelper.run(
      ffmpegPath,
      ['-decoders', '-hide_banner'],
    );

    if (result.exitCode != 0) return [];

    final output = result.stdout as String;
    return _extractHwCodecs(output);
  }

  /// Extract hardware codec names from ffmpeg -encoders/-decoders output.
  List<String> _extractHwCodecs(String output) {
    final hwCodecs = <String>[];
    final hwSuffixes = [
      '_videotoolbox', '_nvenc', '_vaapi', '_qsv',
      '_amf', '_mf', '_cuvid', '_v4l2m2m',
    ];

    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      // Format: " V....D h264_videotoolbox  VideoToolbox H.264 Encoder"
      // The codec name is the second whitespace-separated token
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final name = parts[1];
        if (hwSuffixes.any((s) => name.contains(s))) {
          hwCodecs.add(name);
        }
      }
    }

    return hwCodecs;
  }

  /// Check if a codec name matches a hardware accelerator.
  bool _matchesAccel(String codecName, String accel) {
    switch (accel) {
      case 'videotoolbox':
        return codecName.contains('videotoolbox');
      case 'cuda':
        return codecName.contains('nvenc') || codecName.contains('cuvid');
      case 'vaapi':
        return codecName.contains('vaapi');
      case 'qsv':
        return codecName.contains('qsv');
      case 'd3d11va':
        return codecName.contains('d3d11') || codecName.contains('dxva');
      default:
        return codecName.contains(accel);
    }
  }
}
