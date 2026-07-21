import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/entities/download_config.dart';
import 'package:svid/features/downloads/domain/entities/video_info.dart';
import 'package:svid/features/home/presentation/screens/home_download_mixin.dart';
import 'package:svid/features/settings/domain/entities/format_preset_extended.dart';

void main() {
  group('HomeDownloadMixin audio preset config', () {
    test('active audio preset threads bitrate into DownloadConfig target', () {
      final harness = _Harness();
      const quality = Quality(
        qualityText: 'Audio - M4A (AAC)',
        size: '17 MB',
        encryptedUrl: 'token',
        mediaType: MediaType.audio,
        tbr: 128,
      );
      final preset = _preset(containerFormat: 'm4a', audioBitrate: 192);

      final config = harness.buildConfigFromPreset(preset, quality);

      expect(config.fileType, DownloadFileType.audio);
      expect(config.qualityIntent, DownloadQualityIntent.specific);
      expect(config.qualityTarget?.outputFormat, 'm4a');
      expect(config.qualityTarget?.targetBitrateKbps, 192);
      expect(config.audioBitrateKbpsFor(quality), 192);
    });

    test(
      'saved audio preset preserves explicit dialog bitrate over source tbr',
      () {
        final harness = _Harness();
        const quality = Quality(
          qualityText: 'Audio - M4A (AAC)',
          size: '17 MB',
          encryptedUrl: 'token',
          mediaType: MediaType.audio,
          tbr: 128,
        );
        const config = DownloadConfig(
          selectedQualities: [quality],
          qualityTarget: PortableQualityTarget.audio(
            outputFormat: 'm4a',
            targetBitrateKbps: 192,
          ),
        );

        final preset = harness.buildPresetFromConfig(
          name: 'M4A 192',
          config: config,
          matchedQuality: quality,
        );

        expect(preset.audioOnly, isTrue);
        expect(preset.containerFormat, 'm4a');
        expect(preset.audioBitrate, 192);
      },
    );
  });
}

FormatPresetExtended _preset({
  required String containerFormat,
  required int audioBitrate,
}) => FormatPresetExtended(
  id: 'audio_m4a_192',
  name: 'M4A 192',
  isBuiltIn: false,
  maxResolution: 0,
  videoCodec: 'auto',
  audioCodec: 'auto',
  containerFormat: containerFormat,
  fpsPreference: 'auto',
  audioOnly: true,
  audioBitrate: audioBitrate,
  createdAt: DateTime(2026, 5, 22),
);

class _Harness with HomeDownloadMixin {
  final TextEditingController _urlController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Set<String> _autoLoginAttemptedUrls = <String>{};
  final Set<String> _autoLoginCookieRetryAttemptedUrls = <String>{};
  final Set<String> _autoLoginInFlightUrls = <String>{};
  final Set<int> _authRetryAttemptedDownloadIds = <int>{};
  bool _isShowingDialog = false;
  bool _bypassArchiveCheck = false;
  String? _pendingDirectDownloadUrl;
  String? _pendingForceConfigDialogUrl;

  @override
  WidgetRef get ref => throw UnimplementedError();

  @override
  bool get mounted => true;

  @override
  BuildContext get context => throw UnimplementedError();

  @override
  TextEditingController get urlController => _urlController;

  @override
  GlobalKey<FormState> get formKey => _formKey;

  @override
  bool get isShowingDialog => _isShowingDialog;

  @override
  set isShowingDialog(bool value) => _isShowingDialog = value;

  @override
  bool get bypassArchiveCheck => _bypassArchiveCheck;

  @override
  set bypassArchiveCheck(bool value) => _bypassArchiveCheck = value;

  @override
  String? get pendingDirectDownloadUrl => _pendingDirectDownloadUrl;

  @override
  set pendingDirectDownloadUrl(String? value) =>
      _pendingDirectDownloadUrl = value;

  @override
  String? get pendingForceConfigDialogUrl => _pendingForceConfigDialogUrl;

  @override
  set pendingForceConfigDialogUrl(String? value) =>
      _pendingForceConfigDialogUrl = value;

  @override
  Set<String> get autoLoginAttemptedUrls => _autoLoginAttemptedUrls;

  @override
  Set<String> get autoLoginCookieRetryAttemptedUrls =>
      _autoLoginCookieRetryAttemptedUrls;

  @override
  Set<String> get autoLoginInFlightUrls => _autoLoginInFlightUrls;

  @override
  Set<int> get authRetryAttemptedDownloadIds => _authRetryAttemptedDownloadIds;

  @override
  void registerPopupOriginatedDownloadId(int id) {}

  @override
  Future<void> handleBatchDownload(
    List<String> urls, {
    String? playlistId,
    String? playlistTitle,
  }) async {}
}
