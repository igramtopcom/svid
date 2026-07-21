import 'dart:io' show Platform;

import 'binary_manager.dart';
import 'binary_type.dart';

/// yt-dlp publishes a GNU-format `SHA2-256SUMS` file alongside each release.
/// It lists the hex SHA-256 for every artifact (yt-dlp, yt-dlp.exe,
/// yt-dlp_macos, yt-dlp_linux, etc.) — we fetch it before accepting a binary
/// so an attacker cannot swap the individual asset without also swapping the
/// manifest. Checksum file and binaries live on the same origin, so this
/// protects against asset-level tampering (wrong file served) more than
/// against full origin compromise; the latter is the job of the backend
/// signed-manifest work (out of scope here).
///
/// Production tracks yt-dlp's `master` binary channel rather than stable.
/// Stable is often stale against site-side extractor breakages; master is the
/// official canary channel and gives the app the latest extractor fixes while
/// still flowing through our safe download/checksum/rollback pipeline.
const String ytDlpReleaseChannel = 'master-builds';
const String ytDlpReleaseRepo = 'yt-dlp/yt-dlp-master-builds';
const String _ytDlpReleaseBaseUrl =
    'https://github.com/$ytDlpReleaseRepo/releases/latest/download';
const String _ytDlpChecksumsUrl = '$_ytDlpReleaseBaseUrl/SHA2-256SUMS';

String _ytDlpAssetUrl(String filename) => '$_ytDlpReleaseBaseUrl/$filename';

/// Deno JS runtime — pinned version for production determinism.
///
/// Required by yt-dlp 2025.11.12+ for full YouTube extraction (n-challenge
/// + nsig signature solving). Without Deno, logged-in YouTube returns only
/// storyboard formats. We pin a specific version (rather than tracking
/// `latest`) so that:
///   1. SHA256 verification is deterministic — `latest` redirects to a
///      different artifact every time Deno releases a patch.
///   2. App behaviour cannot silently change when Deno upstream releases
///      a new version. A bump goes through code review + canary CI.
///
/// To bump: download the new asset, recompute SHA256, update both the
/// version string and the checksum map below, run canary tests on a clean
/// VM. Deno does NOT publish per-asset checksum files (unlike yt-dlp's
/// SHA2-256SUMS), so we ship the hash inline as the source of truth.
const String _denoVersion = '2.7.14';

const String _denoBaseUrl =
    'https://github.com/denoland/deno/releases/download/v$_denoVersion';

/// SHA-256 of each per-platform Deno zip archive at version `_denoVersion`.
/// Computed locally against fresh downloads (2026-05-07).
const Map<String, String> _denoSha256 = {
  'aarch64-apple-darwin':
      'aeb5825f83b4a9cd7f9355a1c4ddd666205dacf76ccb7b98c2b10e066bc9e4bb',
  'x86_64-apple-darwin':
      'c89149513bf8e82ab5b351dac544f8c0cada90753bd2f576f46325fb67997ae1',
  'x86_64-pc-windows-msvc':
      '25f9871f5c1d9e999d60071f8069767134495fd601d2e2c7ce1e8c641487bda0',
  'x86_64-unknown-linux-gnu':
      '3287efef53606966469cb6a02781327be22b908959397f976e2996dc1b64ae0f',
};

/// Build a Deno [BinaryInfo] for the given Deno target triple.
/// `optional: true` — Deno failure does NOT block first-launch. Non-YouTube
/// extraction (TikTok, IG, etc.) still works without Deno; only YouTube
/// logged-in extraction degrades. The user-facing error path then reports
/// `jsRuntimeUnavailable` instead of pretending login is needed.
///
/// Fallback mirrors: production support has multiple reports of users in
/// region-blocked networks (China, certain corporate VPNs) hitting "Stuck
/// in setting up media tool interface" — admin response confirms VPN
/// resolves it, i.e. `github.com` itself is unreachable. The fallback chain
/// routes through a public GitHub mirror. Ops should swap the mirror host
/// for a private CDN once one is provisioned; the SHA256 verification in
/// [BinaryInfo.sha256] still guards integrity regardless of host.
BinaryInfo _denoInfo(String target) {
  final sha = _denoSha256[target];
  final primary = '$_denoBaseUrl/deno-$target.zip';
  return BinaryInfo(
    type: BinaryType.deno,
    version: _denoVersion,
    downloadUrl: primary,
    fallbackUrls: githubMirrorChain(primary),
    isArchive: true,
    archiveInternalPath: target.contains('windows') ? 'deno.exe' : 'deno',
    sha256: sha,
    optional: true,
  );
}

/// Build mirror-prefixed variants of a `github.com` download URL for users
/// whose network cannot reach the canonical GitHub host. Each mirror is a
/// known stable public reverse-proxy that re-serves the same release asset
/// byte-for-byte; integrity is still enforced via SHA-256 (yt-dlp manifest
/// or inline checksum map). Order is reliability-first based on community
/// uptime trackers.
///
/// Exposed publicly so `BinaryDownloader` can use the same chain for the
/// upstream SHA-256 manifest fetch — otherwise a network that blocks
/// `github.com` would fail BOTH the binary download (mirror works) AND the
/// manifest fetch (no mirror) → downloader falls open and accepts the
/// binary on HTTPS trust alone. Mirroring the manifest closes that loop.
///
/// Ops follow-up: replace these public proxies with a brand-owned CDN once
/// provisioned (Cloudflare R2 or similar). Until then, public proxies are
/// the only ship-able recovery path for the "Stuck setting up media tool"
/// production class.
List<String> githubMirrorChain(String githubUrl) {
  if (!githubUrl.startsWith('https://github.com/')) return const [];
  return [
    // ghfast.top — community-maintained GitHub mirror with global edge.
    'https://ghfast.top/$githubUrl',
    // gh-proxy.com — long-running stable proxy widely used in CN networks.
    'https://gh-proxy.com/$githubUrl',
  ];
}

/// Information about a binary for a specific platform
class BinaryInfo {
  final BinaryType type;
  final String version;
  final String downloadUrl;
  final String? sha256;
  final int? expectedSize;
  final bool isArchive;
  final String? archiveInternalPath;

  /// URL of an upstream-published SHA256SUMS-style checksum file. When set,
  /// [BinaryDownloader] fetches this BEFORE accepting the downloaded payload,
  /// parses it, and rejects the binary if its hash does not match the entry
  /// keyed by [checksumsFilename]. Used for sources that publish signed or
  /// co-located checksum manifests (e.g. yt-dlp `SHA2-256SUMS`). Leave null
  /// for sources that do not publish a checksum file — the downloader still
  /// computes the hash and logs it for audit, but cannot authoritatively
  /// verify.
  final String? checksumsUrl;

  /// Filename to look up inside the checksums file. Upstream checksum files
  /// list many artifacts; this is the exact name entry to match against.
  final String? checksumsFilename;

  /// Secondary URLs the downloader will try in order if the primary
  /// [downloadUrl] returns a non-200 status (404, 5xx, …) or fails its
  /// HEAD-redirect resolution. Defends against the upstream-publishes-empty
  /// release pattern (e.g. `mikf/gallery-dl` v1.32.0 on 2026-04-24 published
  /// with zero assets, which silently bricked Windows fresh-installs of
  /// VidCombo because all-or-nothing first-launch hard-failed).
  final List<String> fallbackUrls;

  /// When true, a download failure for this binary is surfaced as a
  /// non-fatal warning and the rest of first-launch proceeds. Used for
  /// auxiliary binaries (e.g. gallery-dl is only required for image/carousel
  /// downloads — video extraction via yt-dlp + ffmpeg works without it).
  /// When false (default), failure halts first-launch.
  final bool optional;

  const BinaryInfo({
    required this.type,
    required this.version,
    required this.downloadUrl,
    this.sha256,
    this.expectedSize,
    this.isArchive = false,
    this.archiveInternalPath,
    this.checksumsUrl,
    this.checksumsFilename,
    this.fallbackUrls = const [],
    this.optional = false,
  });

  /// Ordered list of all URLs to try (primary first, then fallbacks).
  List<String> get allUrls => [downloadUrl, ...fallbackUrls];

  /// Get the latest binary info for current platform
  static BinaryInfo getLatest(BinaryType type) {
    if (Platform.isMacOS) {
      return _getMacOSInfo(type);
    } else if (Platform.isWindows) {
      return _getWindowsInfo(type);
    } else if (Platform.isLinux) {
      return _getLinuxInfo(type);
    }
    throw UnsupportedError('Unsupported platform');
  }

  static BinaryInfo _getMacOSInfo(BinaryType type) {
    switch (type) {
      case BinaryType.ytDlp:
        // Use zipapp (no PyInstaller extraction delay) when Python 3.10+ is available
        // Fallback to PyInstaller binary (yt-dlp_macos) otherwise
        final useZipapp = BinaryManager.pythonPath != null;
        return BinaryInfo(
          type: BinaryType.ytDlp,
          version: 'latest',
          downloadUrl:
              useZipapp
                  ? _ytDlpAssetUrl('yt-dlp')
                  : _ytDlpAssetUrl('yt-dlp_macos'),
          isArchive: false,
          checksumsUrl: _ytDlpChecksumsUrl,
          checksumsFilename: useZipapp ? 'yt-dlp' : 'yt-dlp_macos',
        );
      case BinaryType.ffmpeg:
        // martin-riedl.de: architecture-specific builds (arm64 + amd64)
        // evermeet.cx is x86_64 only → crashes on Apple Silicon without Rosetta 2
        final arch = BinaryManager.macOSArch;
        return BinaryInfo(
          type: BinaryType.ffmpeg,
          version: 'latest',
          downloadUrl:
              'https://ffmpeg.martin-riedl.de/redirect/latest/macos/$arch/snapshot/ffmpeg.zip',
          isArchive: true,
          archiveInternalPath: 'ffmpeg',
        );
      case BinaryType.galleryDl:
        // gdl-org/builds: ARM64 only — Intel Macs need Rosetta 2
        // No x86_64 macOS binary exists from any source
        return const BinaryInfo(
          type: BinaryType.galleryDl,
          version: 'latest',
          downloadUrl:
              'https://github.com/gdl-org/builds/releases/latest/download/gallery-dl_macos',
          isArchive: false,
          optional: true,
        );
      case BinaryType.deno:
        // Map BinaryManager.macOSArch ("arm64" / "amd64") to Deno's target
        // triple naming. Deno publishes both Apple Silicon and Intel macOS
        // builds — pick correctly so app does not silently degrade Intel
        // users to Rosetta translation.
        final target =
            BinaryManager.macOSArch == 'arm64'
                ? 'aarch64-apple-darwin'
                : 'x86_64-apple-darwin';
        return _denoInfo(target);
    }
  }

  static BinaryInfo _getWindowsInfo(BinaryType type) {
    switch (type) {
      case BinaryType.ytDlp:
        final ytDlpPrimary = _ytDlpAssetUrl('yt-dlp.exe');
        return BinaryInfo(
          type: BinaryType.ytDlp,
          version: 'latest',
          downloadUrl: ytDlpPrimary,
          fallbackUrls: githubMirrorChain(ytDlpPrimary),
          isArchive: false,
          checksumsUrl: _ytDlpChecksumsUrl,
          checksumsFilename: 'yt-dlp.exe',
        );
      case BinaryType.ffmpeg:
        // Using BtbN builds for Windows (gpl version with all codecs)
        const ffmpegPrimary =
            'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip';
        return BinaryInfo(
          type: BinaryType.ffmpeg,
          version: 'latest',
          downloadUrl: ffmpegPrimary,
          fallbackUrls: githubMirrorChain(ffmpegPrimary),
          isArchive: true,
          archiveInternalPath: 'ffmpeg-master-latest-win64-gpl/bin/ffmpeg.exe',
        );
      case BinaryType.galleryDl:
        // Primary: gdl-org/builds — daily mirror, has consistently shipped
        // gallery-dl_windows.exe even when upstream `mikf/gallery-dl` ships
        // an empty release (e.g. v1.32.0 on 2026-04-24, which 404'd every
        // Windows fresh install for both brands).
        // Fallback: upstream mikf/gallery-dl — used only if gdl-org mirror
        // is unreachable (rare; both repos on github.com so single failure
        // domain at the platform level, but separate at the asset level).
        return const BinaryInfo(
          type: BinaryType.galleryDl,
          version: 'latest',
          downloadUrl:
              'https://github.com/gdl-org/builds/releases/latest/download/gallery-dl_windows.exe',
          isArchive: false,
          fallbackUrls: [
            'https://github.com/mikf/gallery-dl/releases/latest/download/gallery-dl.exe',
          ],
          optional: true,
        );
      case BinaryType.deno:
        return _denoInfo('x86_64-pc-windows-msvc');
    }
  }

  static BinaryInfo _getLinuxInfo(BinaryType type) {
    switch (type) {
      case BinaryType.ytDlp:
        final ytDlpPrimary = _ytDlpAssetUrl('yt-dlp_linux');
        return BinaryInfo(
          type: BinaryType.ytDlp,
          version: 'latest',
          downloadUrl: ytDlpPrimary,
          fallbackUrls: githubMirrorChain(ytDlpPrimary),
          isArchive: false,
          checksumsUrl: _ytDlpChecksumsUrl,
          checksumsFilename: 'yt-dlp_linux',
        );
      case BinaryType.ffmpeg:
        // Using BtbN builds for Linux
        return const BinaryInfo(
          type: BinaryType.ffmpeg,
          version: 'latest',
          downloadUrl:
              'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz',
          isArchive: true,
          archiveInternalPath: 'ffmpeg-master-latest-linux64-gpl/bin/ffmpeg',
        );
      case BinaryType.galleryDl:
        // See _getWindowsInfo galleryDl note for rationale on the
        // gdl-org/builds primary + mikf/gallery-dl fallback ordering.
        return const BinaryInfo(
          type: BinaryType.galleryDl,
          version: 'latest',
          downloadUrl:
              'https://github.com/gdl-org/builds/releases/latest/download/gallery-dl_linux',
          isArchive: false,
          fallbackUrls: [
            'https://github.com/mikf/gallery-dl/releases/latest/download/gallery-dl.bin',
          ],
          optional: true,
        );
      case BinaryType.deno:
        return _denoInfo('x86_64-unknown-linux-gnu');
    }
  }
}
