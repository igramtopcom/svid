import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/repositories/download_repository.dart';

/// RC1 of Ultra Plan v3 — Codex Blockers #1–3.
///
/// The retry path was previously sending yt-dlp with NO format
/// selector + NO cookies, so failed downloads would retry as a
/// different quality and re-fail on private/age-gated/cookie-bound
/// videos. RC1 extends [RetryDownloadPlan] with `cookiesFile` +
/// `cookiesFromBrowser` (the `format` field was already present).
///
/// These tests pin the plan's STRUCTURAL contract — the bits the
/// repository forwards verbatim into the yt-dlp args. The
/// integration of those args is exercised by the runtime smoke
/// matrix (`docs/research/smoke-matrix-runbook-2026-05-21.md`),
/// not by unit tests.
void main() {
  group('RetryDownloadPlan — Codex Blocker #1 (format)', () {
    test('format field carries a yt-dlp -f selector string', () {
      const plan = RetryDownloadPlan(
        format: 'bestvideo[height<=1080]+bestaudio/best',
      );
      expect(plan.format, isNotNull);
      expect(plan.format, contains('bestvideo'));
      expect(plan.format, contains('height<=1080'));
    });

    test('format is null-safe when caller leaves it unset', () {
      const plan = RetryDownloadPlan();
      expect(
        plan.format,
        isNull,
        reason: 'Plan must allow null format for legacy / audio paths',
      );
    });

    test('format coexists with sortOptions for full retry parity', () {
      const plan = RetryDownloadPlan(
        format: 'bestvideo+bestaudio',
        sortOptions: 'res,ext:mp4:m4a',
      );
      expect(plan.format, isNotNull);
      expect(plan.sortOptions, isNotNull);
    });
  });

  group('RetryDownloadPlan — Codex Blocker #2 (cookies)', () {
    test('cookiesFile field is present + nullable', () {
      const planA = RetryDownloadPlan(cookiesFile: '/tmp/cookies/youtube.txt');
      expect(planA.cookiesFile, '/tmp/cookies/youtube.txt');

      const planB = RetryDownloadPlan();
      expect(planB.cookiesFile, isNull);
    });

    test('cookiesFromBrowser field is present + nullable', () {
      const planA = RetryDownloadPlan(cookiesFromBrowser: 'chrome');
      expect(planA.cookiesFromBrowser, 'chrome');

      const planB = RetryDownloadPlan();
      expect(planB.cookiesFromBrowser, isNull);
    });
  });

  group('RetryDownloadPlan — Codex Blocker #3 (file > browser)', () {
    test('plan ALLOWS both fields set — precedence is caller-enforced', () {
      // The Plan is a transport struct; the precedence rule is the
      // CALLER's job (notifier sets `cookiesFromBrowser = file ==
      // null ? ref.read(browser) : null`). The struct itself
      // permits both because the test that the caller is
      // disciplined lives in the notifier flow, not in the data
      // class.
      const plan = RetryDownloadPlan(
        cookiesFile: '/tmp/cookies/youtube.txt',
        cookiesFromBrowser: 'chrome',
      );
      expect(plan.cookiesFile, isNotNull);
      expect(plan.cookiesFromBrowser, isNotNull);
    });

    test('canonical "file present, browser null" shape passes', () {
      // The well-formed shape after notifier precedence: file set,
      // browser nulled to prevent Chrome DB-lock.
      const plan = RetryDownloadPlan(
        cookiesFile: '/tmp/cookies/youtube.txt',
        cookiesFromBrowser: null,
      );
      expect(plan.cookiesFile, isNotNull);
      expect(plan.cookiesFromBrowser, isNull);
    });

    test('canonical "browser fallback" shape (no file) passes', () {
      const plan = RetryDownloadPlan(
        cookiesFile: null,
        cookiesFromBrowser: 'firefox',
      );
      expect(plan.cookiesFile, isNull);
      expect(plan.cookiesFromBrowser, isNotNull);
    });
  });

  group('RetryDownloadPlan — audio extract path', () {
    test('extractAudio=true with audioFormat is wellformed', () {
      const plan = RetryDownloadPlan(extractAudio: true, audioFormat: 'mp3');
      expect(plan.extractAudio, isTrue);
      expect(plan.audioFormat, 'mp3');
    });

    test('extractAudio=true can carry explicit bitrate target', () {
      const plan = RetryDownloadPlan(
        extractAudio: true,
        audioFormat: 'm4a',
        audioBitrateKbps: 320,
      );
      expect(plan.audioFormat, 'm4a');
      expect(plan.audioBitrateKbps, 320);
    });

    test('audio-only retry can still carry cookies', () {
      // Members-only / age-restricted music videos still need
      // cookies on the audio extract retry, just like the video
      // case.
      const plan = RetryDownloadPlan(
        extractAudio: true,
        audioFormat: 'mp3',
        cookiesFile: '/tmp/cookies/youtube.txt',
      );
      expect(plan.cookiesFile, isNotNull);
    });
  });

  group('RetryDownloadPlan — full coverage shape', () {
    test('every field is constructible together', () {
      const plan = RetryDownloadPlan(
        format: 'bestvideo+bestaudio',
        sortOptions: 'res,ext:mp4:m4a',
        videoFormat: 'avi',
        audioFormat: null,
        audioBitrateKbps: null,
        mergeFormatPriority: 'mkv/mp4/webm',
        remuxVideo: null,
        recodeVideo: 'avi',
        extractAudio: false,
        maxVideoHeight: 1080,
        targetVideoHeight: 1080,
        cookiesFile: '/tmp/cookies/youtube.txt',
        cookiesFromBrowser: null,
      );
      expect(plan.format, isNotNull);
      expect(plan.videoFormat, 'avi');
      expect(plan.recodeVideo, 'avi');
      expect(plan.maxVideoHeight, 1080);
      expect(plan.targetVideoHeight, 1080);
      expect(plan.cookiesFile, isNotNull);
      expect(plan.cookiesFromBrowser, isNull);
    });
  });
}
