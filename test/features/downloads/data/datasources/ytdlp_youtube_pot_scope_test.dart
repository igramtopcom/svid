import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:svid/core/binaries/binary_manager.dart';
import 'package:svid/core/binaries/binary_type.dart';
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:svid/features/downloads/data/remote/ytdlp/youtube_pot_provider_service.dart';

class _MockBinaryManager extends Mock implements BinaryManager {}

class _RecordingPotProviderService extends YouTubePotProviderService {
  int downloadInstallCalls = 0;

  @override
  Future<YouTubePotProviderPaths?> ensureInstalled({
    bool downloadIfMissing = true,
  }) async {
    if (!downloadIfMissing) return null;
    downloadInstallCalls += 1;
    return const YouTubePotProviderPaths(
      pluginDir: '/tmp/youtube-pot-plugin',
      cliPath: '/tmp/youtube-pot-cli',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YtDlpDataSource YouTube POT scoping', () {
    test(
      'public no-cookie extract does not enable POT plugin args',
      () async {
        if (Platform.isWindows) return;

        final harness = await _Harness.create();
        addTearDown(harness.dispose);

        await harness.dataSource.extractInfo(
          'https://www.youtube.com/watch?v=public123',
        );

        final args = await harness.readArgs();
        expect(harness.potProvider.downloadInstallCalls, 0);
        expect(args, isNot(contains('--plugin-dirs')));
        expect(args, isNot(contains('youtubepot-bgutilcli:cli_path')));
        expect(args, contains('youtube:skip=hls,dash,translated_subs'));
      },
      skip:
          Platform.isWindows
              ? 'Windows extract path uses the native Rust executor and never receives POT args here.'
              : false,
    );

    test(
      'authenticated extract enables POT plugin args',
      () async {
        if (Platform.isWindows) return;

        final harness = await _Harness.create();
        addTearDown(harness.dispose);

        await harness.dataSource.extractInfo(
          'https://www.youtube.com/watch?v=private123',
          cookiesFile: '/tmp/youtube-cookies.txt',
        );

        final args = await harness.readArgs();
        expect(harness.potProvider.downloadInstallCalls, 1);
        expect(args, contains('--plugin-dirs'));
        expect(args, contains('/tmp/youtube-pot-plugin'));
        expect(
          args,
          contains('youtubepot-bgutilcli:cli_path=/tmp/youtube-pot-cli'),
        );
        expect(args, contains('/tmp/youtube-cookies.txt'));
      },
      skip:
          Platform.isWindows
              ? 'Windows extract path uses the native Rust executor and never receives POT args here.'
              : false,
    );
  });
}

class _Harness {
  _Harness({
    required this.tempDir,
    required this.argsFile,
    required this.dataSource,
    required this.potProvider,
  });

  final Directory tempDir;
  final File argsFile;
  final YtDlpDataSource dataSource;
  final _RecordingPotProviderService potProvider;

  static Future<_Harness> create() async {
    final tempDir = await Directory.systemTemp.createTemp('ytdlp_pot_scope_');
    final argsFile = File('${tempDir.path}/args.txt');
    final script = File('${tempDir.path}/fake-yt-dlp.sh');
    await script.writeAsString('''
#!/bin/sh
: > '${argsFile.path}'
for arg in "\$@"; do
  printf '%s\\n' "\$arg" >> '${argsFile.path}'
done
cat <<'JSON'
{"id":"test123","title":"Test Video","extractor":"youtube","duration":60,"formats":[]}
JSON
''');
    await Process.run('chmod', ['+x', script.path]);

    final binaryManager = _MockBinaryManager();
    when(() => binaryManager.initialize()).thenAnswer((_) async {});
    when(
      () => binaryManager.getBinaryPath(BinaryType.ytDlp),
    ).thenAnswer((_) async => script.path);
    when(
      () => binaryManager.getBinaryPath(BinaryType.ffmpeg),
    ).thenAnswer((_) async => null);
    when(
      () => binaryManager.getBinaryPath(BinaryType.deno),
    ).thenAnswer((_) async => null);
    when(
      () => binaryManager.getVersion(BinaryType.ytDlp),
    ).thenAnswer((_) async => 'test-yt-dlp');

    final potProvider = _RecordingPotProviderService();
    final dataSource = YtDlpDataSource(
      binaryManager,
      youtubePotProviderService: potProvider,
    );

    return _Harness(
      tempDir: tempDir,
      argsFile: argsFile,
      dataSource: dataSource,
      potProvider: potProvider,
    );
  }

  Future<List<String>> readArgs() async {
    return argsFile.readAsLines();
  }

  Future<void> dispose() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}
