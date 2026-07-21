import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/binaries/binary_downloader.dart';

void main() {
  group('BinaryDownloader.parseChecksums', () {
    const sampleManifest = '''
# yt-dlp SHA256 manifest (abridged)
b5f2c5e4c3a1c8a5b7f3d1e2c4b6a8d0e2f4c6b8a0c2d4e6f8b0c2d4e6f8a0b2  yt-dlp
aa11bb22cc33dd44ee55ff66001122334455667788990011223344556677889a  yt-dlp.exe
11223344556677889900aabbccddeeff00112233445566778899aabbccddeeff *yt-dlp_macos
ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100  yt-dlp_linux

# trailing comment line
''';

    test('finds plain text-mode entry (two spaces)', () {
      final hash = BinaryDownloader.parseChecksums(sampleManifest, 'yt-dlp');
      expect(
        hash,
        'b5f2c5e4c3a1c8a5b7f3d1e2c4b6a8d0e2f4c6b8a0c2d4e6f8b0c2d4e6f8a0b2',
      );
    });

    test('finds binary-mode entry (leading asterisk)', () {
      final hash =
          BinaryDownloader.parseChecksums(sampleManifest, 'yt-dlp_macos');
      expect(
        hash,
        '11223344556677889900aabbccddeeff00112233445566778899aabbccddeeff',
      );
    });

    test('returns null when filename absent', () {
      final hash = BinaryDownloader.parseChecksums(sampleManifest, 'ffmpeg');
      expect(hash, isNull);
    });

    test('normalizes uppercase hash to lowercase', () {
      const upper =
          'AA11BB22CC33DD44EE55FF66001122334455667788990011223344556677889A  yt-dlp.exe';
      final hash = BinaryDownloader.parseChecksums(upper, 'yt-dlp.exe');
      expect(
        hash,
        'aa11bb22cc33dd44ee55ff66001122334455667788990011223344556677889a',
      );
    });

    test('rejects non-hex or wrong-length tokens in hash position', () {
      const malformed = '''
notahashatall                                                    yt-dlp
abc123                                                           yt-dlp
aa11bb22cc33dd44ee55ff66001122334455667788990011223344556677889azz  yt-dlp
''';
      expect(
        BinaryDownloader.parseChecksums(malformed, 'yt-dlp'),
        isNull,
      );
    });

    test('skips blank lines and comment lines', () {
      const withNoise = '''


# comment above real entry
aa11bb22cc33dd44ee55ff66001122334455667788990011223344556677889a  yt-dlp.exe


''';
      final hash = BinaryDownloader.parseChecksums(withNoise, 'yt-dlp.exe');
      expect(
        hash,
        'aa11bb22cc33dd44ee55ff66001122334455667788990011223344556677889a',
      );
    });

    test('does not match substring — exact filename only', () {
      const manifest =
          'aa11bb22cc33dd44ee55ff66001122334455667788990011223344556677889a  yt-dlp-nightly\n';
      expect(BinaryDownloader.parseChecksums(manifest, 'yt-dlp'), isNull);
    });

    test('empty body returns null', () {
      expect(BinaryDownloader.parseChecksums('', 'yt-dlp'), isNull);
    });
  });
}
