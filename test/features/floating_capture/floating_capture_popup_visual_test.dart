import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/floating_capture/domain/entities/popup_action_result.dart';
import 'package:ssvid/floating_window_main.dart';

Map<String, dynamic> _preview({
  String url = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  String platform = 'youtube',
  String urlType = 'video',
  String? title,
  String? uploader,
}) {
  return {
    'rawUrl': url,
    'platform': platform,
    'urlType': urlType,
    'title':
        title ??
        'A very long production video title that must stay readable inside '
            'the floating capture popup without pushing controls off screen',
    'uploader': uploader ?? 'A channel name that is also long enough to clip',
  };
}

String get _longFilename =>
    'A very long exported filename with spaces, unicode-safe punctuation, '
    'quality suffix, codec details, and final extension.mp4';

String get _longFailure =>
    'The selected quality is unavailable for this video. Please choose another '
    'format or open the app for details.';

Future<void> _pumpHarness(
  WidgetTester tester, {
  Map<String, dynamic>? initialPreview,
  List<Map<String, dynamic>> queue = const <Map<String, dynamic>>[],
  bool pending = false,
  int quotaRemaining = -1,
  PopupActionResult? result,
  String localeCode = 'en',
}) async {
  await tester.binding.setSurfaceSize(const Size(340, 460));
  await tester.pumpWidget(
    buildFloatingCaptureVisualHarness(
      initialPreview: initialPreview ?? _preview(),
      queue: queue,
      pending: pending,
      quotaRemaining: quotaRemaining,
      result: result,
      localeCode: localeCode,
    ),
  );
  await tester.pump();
}

void _expectNoRenderErrors(WidgetTester tester, [String? context]) {
  final errors = <Object>[];
  Object? error;
  while ((error = tester.takeException()) != null) {
    errors.add(error!);
  }
  expect(errors, isEmpty, reason: context);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('collapsed popup states render without overflow', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final queue = List.generate(
      4,
      (index) => _preview(
        url: 'https://www.youtube.com/watch?v=queue$index',
        title: 'Queued item ${index + 1} with long title',
      ),
    );

    final cases = <({String name, Widget Function() build})>[
      (
        name: 'idle video',
        build:
            () => buildFloatingCaptureVisualHarness(
              initialPreview: _preview(),
              quotaRemaining: 0,
            ),
      ),
      (
        name: 'pending video',
        build:
            () => buildFloatingCaptureVisualHarness(
              initialPreview: _preview(),
              pending: true,
            ),
      ),
      (
        name: 'playlist open-in-app',
        build:
            () => buildFloatingCaptureVisualHarness(
              initialPreview: _preview(
                url: 'https://www.youtube.com/playlist?list=PL_LONG_LIST',
                urlType: 'playlist',
                title: 'Playlist URL with enough title text to stress layout',
              ),
            ),
      ),
      (
        name: 'five-item queue',
        build:
            () => buildFloatingCaptureVisualHarness(
              initialPreview: _preview(title: 'Queue root'),
              queue: queue,
            ),
      ),
      (
        name: 'started result',
        build:
            () => buildFloatingCaptureVisualHarness(
              initialPreview: _preview(),
              result: PopupActionStarted(filename: _longFilename),
            ),
      ),
      (
        name: 'completed result',
        build:
            () => buildFloatingCaptureVisualHarness(
              initialPreview: _preview(),
              result: PopupActionCompleted(
                filename: _longFilename,
                savedPath: '/Users/test/Downloads/$_longFilename',
              ),
            ),
      ),
      (
        name: 'failed result',
        build:
            () => buildFloatingCaptureVisualHarness(
              initialPreview: _preview(),
              result: PopupActionFailed(_longFailure),
            ),
      ),
      (
        name: 'auth-required result vi',
        build:
            () => buildFloatingCaptureVisualHarness(
              initialPreview: _preview(),
              result: const PopupActionAuthRequired(),
              localeCode: 'vi',
            ),
      ),
      (
        name: 'metadata fallback',
        build:
            () => buildFloatingCaptureVisualHarness(
              initialPreview: _preview(title: null, uploader: null),
            ),
      ),
    ];

    for (final testCase in cases) {
      await tester.binding.setSurfaceSize(const Size(340, 460));
      await tester.pumpWidget(testCase.build());
      await tester.pump();
      _expectNoRenderErrors(tester, testCase.name);
    }
  });

  testWidgets('header and snooze menus render without overflow', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpHarness(tester);
    _expectNoRenderErrors(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pump(const Duration(milliseconds: 250));
    _expectNoRenderErrors(tester);

    await tester.tapAt(const Offset(8, 8));
    await tester.pump(const Duration(milliseconds: 250));
    _expectNoRenderErrors(tester);

    await tester.tap(find.byTooltip('Snooze'));
    await tester.pump(const Duration(milliseconds: 250));
    _expectNoRenderErrors(tester);
  });
}
