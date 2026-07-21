import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/converter/domain/entities/output_format.dart';
import 'package:ssvid/features/converter/presentation/providers/converter_providers.dart';

void main() {
  group('ConversionConfigNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('selecting an audio output format selects the matching codec', () {
      final notifier = container.read(conversionConfigProvider.notifier);

      notifier.setOutputFormat(OutputFormat.mp3);

      final config = container.read(conversionConfigProvider);
      expect(config.outputFormat, OutputFormat.mp3);
      expect(config.audioCodec, AudioCodecOption.mp3);
      expect(config.videoCodec, VideoCodecOption.none);
    });

    test('selecting an audio codec while audio-only updates file format', () {
      final notifier = container.read(conversionConfigProvider.notifier);

      notifier.setOutputFormat(OutputFormat.mp3);
      notifier.setAudioCodec(AudioCodecOption.opus);

      final config = container.read(conversionConfigProvider);
      expect(config.outputFormat, OutputFormat.opus);
      expect(config.audioCodec, AudioCodecOption.opus);
      expect(config.videoCodec, VideoCodecOption.none);
    });

    test('AAC codec uses M4A as the default app container', () {
      final notifier = container.read(conversionConfigProvider.notifier);

      notifier.setOutputFormat(OutputFormat.mp3);
      notifier.setAudioCodec(AudioCodecOption.aac);

      final config = container.read(conversionConfigProvider);
      expect(config.outputFormat, OutputFormat.m4a);
      expect(config.audioCodec, AudioCodecOption.aac);
    });

    test('switching back to a video format clears audio-only video codec', () {
      final notifier = container.read(conversionConfigProvider.notifier);

      notifier.setOutputFormat(OutputFormat.mp3);
      notifier.setOutputFormat(OutputFormat.mp4);

      final config = container.read(conversionConfigProvider);
      expect(config.outputFormat, OutputFormat.mp4);
      expect(config.videoCodec, isNull);
    });
  });
}
