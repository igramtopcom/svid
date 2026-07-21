import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/binaries/binary_downloader.dart';

/// Unit tests for the upstream SHA-256 manifest parser. This is the
/// supply-chain gate — a malformed or tampered manifest must never cause
/// the downloader to silently accept a binary with a wrong hash.
void main() {
  // Valid 64-char hex digests used throughout the suite.
  const h1 = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  const h2 = 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';
  const h3 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  group('BinaryDownloader.parseChecksums — happy path', () {
    test('parses GNU sha256sum text-mode entry', () {
      final body = '$h1  yt-dlp\n$h2  yt-dlp.exe\n';
      expect(BinaryDownloader.parseChecksums(body, 'yt-dlp'), h1);
      expect(BinaryDownloader.parseChecksums(body, 'yt-dlp.exe'), h2);
    });

    test('parses GNU sha256sum binary-mode entry ("*" prefix on filename)', () {
      // Format: "<hash>␣*<filename>"
      final body = '$h1 *yt-dlp_macos';
      expect(BinaryDownloader.parseChecksums(body, 'yt-dlp_macos'), h1);
    });

    test('lower-cases upstream uppercase hex — match is case-insensitive', () {
      final body = '${h1.toUpperCase()}  yt-dlp';
      expect(BinaryDownloader.parseChecksums(body, 'yt-dlp'), h1);
    });

    test('tolerates extra whitespace and CRLF line endings', () {
      final body = '  $h1   yt-dlp  \r\n'
          '\r\n'
          '$h2  yt-dlp.exe\r\n';
      expect(BinaryDownloader.parseChecksums(body, 'yt-dlp'), h1);
      expect(BinaryDownloader.parseChecksums(body, 'yt-dlp.exe'), h2);
    });

    test('skips comment lines and blank lines', () {
      final body = '# yt-dlp release SHA-256 manifest\n'
          '# generated automatically\n'
          '\n'
          '$h1  yt-dlp\n';
      expect(BinaryDownloader.parseChecksums(body, 'yt-dlp'), h1);
    });
  });

  group('BinaryDownloader.parseChecksums — rejection cases', () {
    test('returns null when the filename is not listed', () {
      final body = '$h1  yt-dlp';
      expect(BinaryDownloader.parseChecksums(body, 'yt-dlp.exe'), isNull);
    });

    test('returns null for an entry whose hash is not 64 hex chars', () {
      // Hash is 63 chars — must NOT be accepted. Otherwise a truncated
      // manifest could ghost-verify to a prefix match.
      final short = h1.substring(0, 63);
      final body = '$short  yt-dlp';
      expect(BinaryDownloader.parseChecksums(body, 'yt-dlp'), isNull);
    });

    test('returns null for an entry with non-hex chars in the hash', () {
      // Attacker mutation: ZZZZ... in hash position, still 64 chars long.
      final body = '${'z' * 64}  yt-dlp';
      expect(BinaryDownloader.parseChecksums(body, 'yt-dlp'), isNull);
    });

    test('returns null for an empty body', () {
      expect(BinaryDownloader.parseChecksums('', 'yt-dlp'), isNull);
    });

    test(
      'exact filename match only — does NOT accept suffix / prefix / substring',
      () {
        // Upstream manifest has `yt-dlp.exe`; a lookup for `yt-dlp` must
        // NOT match the .exe entry (filename confusion would accept a
        // Windows binary as the macOS zipapp and vice versa).
        final body = '$h1  yt-dlp.exe';
        expect(BinaryDownloader.parseChecksums(body, 'yt-dlp'), isNull);
        expect(BinaryDownloader.parseChecksums(body, 'dlp.exe'), isNull);
        expect(BinaryDownloader.parseChecksums(body, 'yt-dlp.ex'), isNull);
      },
    );

    test('picks the FIRST matching entry when filename appears twice', () {
      // A manifest is not supposed to list the same filename twice, but
      // defensive ordering prevents a late-in-file tampered entry from
      // overriding an earlier legitimate one.
      final body = '$h1  yt-dlp\n$h2  yt-dlp\n';
      expect(BinaryDownloader.parseChecksums(body, 'yt-dlp'), h1);
    });
  });

  group('BinaryDownloader.parseChecksums — real-world fixtures', () {
    test('parses a representative yt-dlp SHA2-256SUMS excerpt', () {
      // Abbreviated shape of the upstream yt-dlp release manifest. Real
      // file has ~25 entries; we verify three of the ones we actually
      // request across macOS / Windows / Linux.
      final body = '# yt-dlp SHA2-256SUMS\n'
          '$h1  yt-dlp\n'
          '$h2  yt-dlp.exe\n'
          '$h3  yt-dlp_linux\n'
          '${h1.replaceRange(0, 1, 'e')}  yt-dlp_macos\n';
      expect(BinaryDownloader.parseChecksums(body, 'yt-dlp'), h1);
      expect(BinaryDownloader.parseChecksums(body, 'yt-dlp.exe'), h2);
      expect(BinaryDownloader.parseChecksums(body, 'yt-dlp_linux'), h3);
    });
  });
}
