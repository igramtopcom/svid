/// Hardware acceleration capabilities detected on the system.
///
/// Represents a single HW accelerator (e.g., VideoToolbox on macOS,
/// NVENC on Windows/Linux with NVIDIA GPU, VAAPI on Linux).
class HwAccelInfo {
  /// Accelerator name (e.g., "videotoolbox", "cuda", "vaapi", "qsv")
  final String name;

  /// Available hardware encoders (e.g., ["h264_videotoolbox", "hevc_videotoolbox"])
  final List<String> encoders;

  /// Available hardware decoders
  final List<String> decoders;

  /// Whether this accelerator is available on the current system
  final bool isAvailable;

  const HwAccelInfo({
    required this.name,
    required this.encoders,
    required this.decoders,
    required this.isAvailable,
  });

  /// Display name for UI
  String get displayName {
    switch (name) {
      case 'videotoolbox':
        return 'VideoToolbox (Apple)';
      case 'cuda':
        return 'NVENC (NVIDIA)';
      case 'vaapi':
        return 'VAAPI (Linux)';
      case 'qsv':
        return 'QuickSync (Intel)';
      case 'd3d11va':
        return 'D3D11VA (Windows)';
      default:
        return name.toUpperCase();
    }
  }

  /// Whether this accelerator supports H.264 encoding
  bool get supportsH264 =>
      encoders.any((e) => e.contains('h264') || e.contains('264'));

  /// Whether this accelerator supports H.265/HEVC encoding
  bool get supportsH265 =>
      encoders.any((e) => e.contains('hevc') || e.contains('265'));

  HwAccelInfo copyWith({
    String? name,
    List<String>? encoders,
    List<String>? decoders,
    bool? isAvailable,
  }) {
    return HwAccelInfo(
      name: name ?? this.name,
      encoders: encoders ?? this.encoders,
      decoders: decoders ?? this.decoders,
      isAvailable: isAvailable ?? this.isAvailable,
    );
  }

  @override
  String toString() => 'HwAccelInfo($name, encoders=$encoders, available=$isAvailable)';
}
