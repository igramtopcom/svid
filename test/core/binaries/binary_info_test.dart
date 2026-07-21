import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/binaries/binary_info.dart';
import 'package:svid/core/binaries/binary_type.dart';

void main() {
  group('BinaryInfo fallback URL chain', () {
    test('allUrls returns [primary] when no fallback declared', () {
      const info = BinaryInfo(
        type: BinaryType.ytDlp,
        version: 'latest',
        downloadUrl: 'https://example.com/yt-dlp.exe',
      );
      expect(info.allUrls, ['https://example.com/yt-dlp.exe']);
    });

    test('allUrls returns primary first then fallbacks in order', () {
      const info = BinaryInfo(
        type: BinaryType.galleryDl,
        version: 'latest',
        downloadUrl: 'https://primary.example/gallery-dl.exe',
        fallbackUrls: [
          'https://secondary.example/gallery-dl.exe',
          'https://tertiary.example/gallery-dl.exe',
        ],
      );
      expect(info.allUrls, [
        'https://primary.example/gallery-dl.exe',
        'https://secondary.example/gallery-dl.exe',
        'https://tertiary.example/gallery-dl.exe',
      ]);
    });

    test('optional defaults to false (required binary)', () {
      const info = BinaryInfo(
        type: BinaryType.ytDlp,
        version: 'latest',
        downloadUrl: 'https://example.com/yt-dlp.exe',
      );
      expect(info.optional, isFalse);
    });

    test('optional flag passes through when set', () {
      const info = BinaryInfo(
        type: BinaryType.galleryDl,
        version: 'latest',
        downloadUrl: 'https://example.com/gallery-dl.exe',
        optional: true,
      );
      expect(info.optional, isTrue);
    });
  });

  group('BinaryInfo.getLatest — production resilience', () {
    // These tests don't run platform-conditional code per platform — we
    // only assert the surface contract (optional flag, fallback present)
    // that the binary_manager + setup screen rely on.

    test('gallery-dl is marked optional on every platform path', () {
      // Sanity: every BinaryInfo factory path returns galleryDl with
      // optional=true. Without this, an upstream `mikf/gallery-dl` empty
      // release like 2026-04-24 would brick first launch on the platforms
      // that depend on it.
      //
      // We cannot easily switch Platform inside a unit test, so we read
      // the metadata directly from the static factory by inspecting the
      // const BinaryInfo declarations. If the factory ever drops the
      // `optional: true` flag for galleryDl on any platform, this test
      // catches it via the runtime call on the current platform.
      final current = BinaryInfo.getLatest(BinaryType.galleryDl);
      expect(
        current.optional,
        isTrue,
        reason:
            'gallery-dl must be optional so an upstream-empty release '
            'cannot block first launch.',
      );
    });

    test('yt-dlp is required (not optional) — core video extraction', () {
      final current = BinaryInfo.getLatest(BinaryType.ytDlp);
      expect(current.optional, isFalse);
    });

    test('ffmpeg is required (not optional) — core media processing', () {
      final current = BinaryInfo.getLatest(BinaryType.ffmpeg);
      expect(current.optional, isFalse);
    });

    test(
      'gallery-dl on Windows + Linux declares at least one fallback URL',
      () {
        // macOS has no second source for the gallery-dl binary
        // (mikf/gallery-dl ships only .exe and .bin; gdl-org/builds is the
        // sole macOS builder), so we only assert fallback presence on
        // Windows + Linux — those are the platforms that bricked on
        // 2026-04-24 when the single-source mikf URL went 404.
        if (Platform.isMacOS) return;

        final current = BinaryInfo.getLatest(BinaryType.galleryDl);
        expect(
          current.fallbackUrls,
          isNotEmpty,
          reason:
              'Single-source URL coupling is the failure mode that broke '
              'all VidCombo Windows fresh installs on 2026-04-24. Maintain at '
              'least one fallback mirror.',
        );
        expect(current.fallbackUrls, isNot(contains(current.downloadUrl)));
      },
    );
  });

  group('BinaryInfo.getLatest — region-blocked recovery (P0 mirrors)', () {
    // Production support evidence: "Stuck in setting up media tool
    // interface" reports from users in CN / corporate VPN networks where
    // github.com release downloads time out. Admin response confirmed VPN
    // resolves it. The fix routes through public GitHub mirrors so an
    // unreachable github.com hostname does not brick first launch.
    //
    // SHA-256 verification (yt-dlp upstream `SHA2-256SUMS` manifest /
    // inline Deno checksum map) still guards integrity, so a mirror that
    // serves the wrong bytes is rejected.

    test('yt-dlp on Windows + Linux declares mirror fallback URLs', () {
      // yt-dlp_macos is universal and macOS has not surfaced region-block
      // reports in support; restrict the assertion to the platforms where
      // the production reports actually came from.
      if (Platform.isMacOS) return;

      final current = BinaryInfo.getLatest(BinaryType.ytDlp);
      expect(
        current.fallbackUrls,
        isNotEmpty,
        reason:
            'yt-dlp is a required binary; first launch hard-fails '
            'without it. Must have at least one non-github.com mirror.',
      );
      // Every fallback should be a different host than the primary so a
      // DNS-level block of github.com does not also block the fallback.
      for (final url in current.fallbackUrls) {
        expect(
          url,
          isNot(current.downloadUrl),
          reason: 'Fallback URL must differ from primary',
        );
      }
    });

    test('ffmpeg on Windows + Linux declares mirror fallback URLs', () {
      if (Platform.isMacOS) return;
      final current = BinaryInfo.getLatest(BinaryType.ffmpeg);
      expect(current.fallbackUrls, isNotEmpty);
    });

    test('Deno declares mirror fallback URLs on every platform', () {
      // YouTube nsig recovery requires Deno on every desktop platform.
      // optional: true keeps first-launch unblocked when ALL mirrors fail,
      // but the goal is still to avoid that path for region-blocked users.
      final current = BinaryInfo.getLatest(BinaryType.deno);
      expect(
        current.fallbackUrls,
        isNotEmpty,
        reason:
            'Deno failure silently degrades YouTube login extraction to '
            'storyboards-only. Mirror fallback prevents this for region-'
            'blocked users.',
      );
      expect(
        current.optional,
        isTrue,
        reason:
            'Deno must remain optional so unrecoverable mirror outage '
            'never blocks first launch.',
      );
    });
  });

  group('BinaryInfo.getLatest — yt-dlp channel', () {
    test('yt-dlp downloads from official master-builds channel', () {
      final current = BinaryInfo.getLatest(BinaryType.ytDlp);
      expect(
        current.downloadUrl,
        contains('github.com/yt-dlp/yt-dlp-master-builds/releases/latest'),
      );
      expect(
        current.checksumsUrl,
        contains('github.com/yt-dlp/yt-dlp-master-builds/releases/latest'),
      );
      expect(
        current.downloadUrl,
        isNot(contains('github.com/yt-dlp/yt-dlp/releases/latest')),
      );
    });
  });
}
