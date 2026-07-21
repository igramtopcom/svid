import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:svid/core/binaries/binary_manager.dart';
import 'package:svid/core/binaries/binary_type.dart';
import 'package:svid/core/database/app_database.dart' hide ConversionJob;
import 'package:svid/features/converter/domain/entities/conversion_config.dart';
import 'package:svid/features/converter/domain/entities/conversion_job.dart';
import 'package:svid/features/converter/domain/entities/conversion_status.dart';
import 'package:svid/features/converter/domain/entities/output_format.dart';
import 'package:svid/features/converter/domain/repositories/conversion_repository.dart';
import 'package:svid/features/converter/presentation/providers/conversion_queue_provider.dart';

class _MockConversionRepository extends Mock implements ConversionRepository {}

class _MockBinaryManager extends Mock implements BinaryManager {}

class _FakeConversionJob extends Fake implements ConversionJob {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_FakeConversionJob());
  });

  group('ConversionQueueNotifier', () {
    late AppDatabase db;
    late _MockConversionRepository repository;
    late _MockBinaryManager binaryManager;
    late Directory tempDir;
    late File ffmpegBinary;

    setUp(() async {
      db = AppDatabase.forTest();
      repository = _MockConversionRepository();
      binaryManager = _MockBinaryManager();
      tempDir = await Directory.systemTemp.createTemp('converter_queue_test_');
      ffmpegBinary = File(p.join(tempDir.path, 'ffmpeg'));
      await ffmpegBinary.writeAsString('stub');

      when(
        () => binaryManager.getBinaryPath(BinaryType.ffmpeg),
      ).thenAnswer((_) async => ffmpegBinary.path);
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'reserves the slot immediately so free tier keeps later jobs queued',
      () async {
        final activeConversion = StreamController<ConversionProgress>();

        when(
          () => repository.convertFile(any()),
        ).thenAnswer((_) => activeConversion.stream);

        final notifier = ConversionQueueNotifier(
          repository,
          db,
          false,
          binaryManager,
          isNotificationsEnabled: () => true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final inputA = File(p.join(tempDir.path, 'input_a.mp4'));
        final inputB = File(p.join(tempDir.path, 'input_b.mp4'));
        await inputA.writeAsString('a');
        await inputB.writeAsString('b');

        const config = ConversionConfig(outputFormat: OutputFormat.mp4);

        await notifier.addToQueue(inputPath: inputA.path, config: config);
        await notifier.addToQueue(inputPath: inputB.path, config: config);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(notifier.state.where((job) => job.status.isActive).length, 1);
        expect(
          notifier.state
              .where((job) => job.status == ConversionStatus.queued)
              .length,
          1,
        );
        verify(() => repository.convertFile(any())).called(1);

        await activeConversion.close();
        notifier.dispose();
      },
    );

    test(
      'split jobs use a directory output target and complete from segments',
      () async {
        final notifier = ConversionQueueNotifier(
          repository,
          db,
          false,
          binaryManager,
          isNotificationsEnabled: () => true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final input = File(p.join(tempDir.path, 'movie.mp4'));
        await input.writeAsString('video');
        final outputDir = p.join(tempDir.path, 'movie_segments');

        when(
          () => repository.splitVideo(
            jobId: any(named: 'jobId'),
            inputPath: any(named: 'inputPath'),
            outputDir: any(named: 'outputDir'),
            intervalSeconds: any(named: 'intervalSeconds'),
            inputDuration: any(named: 'inputDuration'),
          ),
        ).thenAnswer((invocation) async* {
          final dirPath = invocation.namedArguments[#outputDir] as String;
          final dir = Directory(dirPath);
          await dir.create(recursive: true);
          await File(
            p.join(dir.path, 'movie_segment_000.mp4'),
          ).writeAsString('a');
          await File(
            p.join(dir.path, 'movie_segment_001.mp4'),
          ).writeAsString('bc');
          yield const ConversionProgress(progress: 0.5);
          yield ConversionProgress.completed();
        });

        const config = ConversionConfig(
          outputFormat: OutputFormat.mp4,
          splitInterval: 60,
        );

        await notifier.addToQueue(inputPath: input.path, config: config);
        await Future<void>.delayed(const Duration(milliseconds: 40));

        final job = notifier.state.single;
        expect(job.status, ConversionStatus.completed);
        expect(job.outputPath, outputDir);
        expect(job.outputFilename, 'movie_segments');
        expect(job.outputSize, 3);

        notifier.dispose();
      },
    );

    test(
      'cancelled thumbnail jobs ignore late completion and stay cancelled',
      () async {
        final notifier = ConversionQueueNotifier(
          repository,
          db,
          false,
          binaryManager,
          isNotificationsEnabled: () => true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final input = File(p.join(tempDir.path, 'clip.mp4'));
        final extracted = File(p.join(tempDir.path, 'clip_thumb_2s.jpg'));
        await input.writeAsString('clip');

        final completer = Completer<String?>();
        when(
          () => repository.extractThumbnail(
            inputPath: any(named: 'inputPath'),
            outputPath: any(named: 'outputPath'),
            timestamp: any(named: 'timestamp'),
            jobId: any(named: 'jobId'),
          ),
        ).thenAnswer((_) => completer.future);
        when(() => repository.cancelConversion(any())).thenReturn(null);

        const config = ConversionConfig(
          outputFormat: OutputFormat.mp4,
          extractThumbnail: true,
          thumbnailTimestamp: 2,
        );

        final job = await notifier.addToQueue(
          inputPath: input.path,
          config: config,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        await notifier.cancelJob(job.id);
        await extracted.writeAsString('thumb');
        completer.complete(extracted.path);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(notifier.state.single.status, ConversionStatus.cancelled);

        notifier.dispose();
      },
    );
  });
}
