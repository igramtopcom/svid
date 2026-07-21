import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/settings/domain/enums/audio_codec_preference.dart';
import 'package:svid/features/settings/domain/enums/container_format_preference.dart';
import 'package:svid/features/settings/domain/enums/download_engine.dart';
import 'package:svid/features/settings/domain/enums/fps_preference.dart';
import 'package:svid/features/settings/domain/enums/quality_preference.dart';
import 'package:svid/features/settings/domain/enums/video_codec_preference.dart';
import 'package:svid/features/settings/presentation/providers/settings_provider.dart';

/// Create a SettingsState with all required fields filled in
SettingsState _defaultState({
  int socketTimeout = 30,
  int maxRetries = 3,
  int httpChunkSizeMb = 10,
  String filenameTemplate = '%(title)s.%(ext)s',
  String customPostprocessorArgs = '',
}) {
  return SettingsState(
    downloadPath: '~/Downloads',
    maxConcurrentDownloads: 3,
    themeMode: ThemeMode.system,
    autoStartDownloads: false,
    autoClipboardDetection: true,
    notificationsEnabled: true,
    preferredQuality: QualityPreference.auto,
    downloadEngine: DownloadEngine.ytdlpOnly,
    autoUpdateYtdlp: true,
    ytdlpTimeout: 30,
    videoCodecPreference: VideoCodecPreference.auto,
    audioCodecPreference: AudioCodecPreference.auto,
    containerFormatPreference: ContainerFormatPreference.mp4,
    fpsPreference: FpsPreference.auto,
    maxResolution: 0,
    subtitlesEnabled: false,
    subtitlesLanguages: const ['en'],
    subtitlesFormat: 'srt',
    embedSubtitles: false,
    writeThumbnail: false,
    embedThumbnail: true,
    embedMetadata: true,
    embedChapters: true,
    sponsorBlockEnabled: false,
    sponsorBlockAction: 'skip',
    sponsorBlockCategories: const ['sponsor'],
    forceRemux: false,
    tiktokRemoveWatermark: true,
    geoBypass: false,
    archiveEnabled: false,
    socketTimeout: socketTimeout,
    maxRetries: maxRetries,
    httpChunkSizeMb: httpChunkSizeMb,
    filenameTemplate: filenameTemplate,
    customPostprocessorArgs: customPostprocessorArgs,
  );
}

void main() {
  group('SettingsState — Advanced Options Fields', () {
    test('defaults are correct', () {
      final state = _defaultState();
      expect(state.socketTimeout, 30);
      expect(state.maxRetries, 3);
      expect(state.httpChunkSizeMb, 10);
      expect(state.filenameTemplate, '%(title)s.%(ext)s');
      expect(state.customPostprocessorArgs, '');
    });

    test('copyWith updates socketTimeout', () {
      final state = _defaultState();
      final updated = state.copyWith(socketTimeout: 60);
      expect(updated.socketTimeout, 60);
      expect(updated.maxRetries, 3); // unchanged
    });

    test('copyWith updates maxRetries', () {
      final state = _defaultState();
      final updated = state.copyWith(maxRetries: 8);
      expect(updated.maxRetries, 8);
      expect(updated.socketTimeout, 30); // unchanged
    });

    test('copyWith updates httpChunkSizeMb', () {
      final state = _defaultState();
      final updated = state.copyWith(httpChunkSizeMb: 25);
      expect(updated.httpChunkSizeMb, 25);
    });

    test('copyWith updates filenameTemplate', () {
      final state = _defaultState();
      final updated = state.copyWith(
        filenameTemplate: '%(title)s - %(uploader)s.%(ext)s',
      );
      expect(updated.filenameTemplate, '%(title)s - %(uploader)s.%(ext)s');
    });

    test('copyWith updates customPostprocessorArgs', () {
      final state = _defaultState();
      final updated = state.copyWith(customPostprocessorArgs: '-ac 2 -ar 44100');
      expect(updated.customPostprocessorArgs, '-ac 2 -ar 44100');
    });

    test('copyWith preserves other fields when updating advanced options', () {
      final state = _defaultState().copyWith(
        downloadPath: '/custom/path',
        maxConcurrentDownloads: 5,
      );
      final updated = state.copyWith(
        socketTimeout: 90,
        filenameTemplate: '%(id)s.%(ext)s',
      );
      expect(updated.downloadPath, '/custom/path');
      expect(updated.maxConcurrentDownloads, 5);
      expect(updated.socketTimeout, 90);
      expect(updated.filenameTemplate, '%(id)s.%(ext)s');
      // Original advanced defaults preserved
      expect(updated.maxRetries, 3);
      expect(updated.httpChunkSizeMb, 10);
      expect(updated.customPostprocessorArgs, '');
    });
  });
}
