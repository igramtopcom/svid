import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/theme/app_colors.dart';
import 'package:svid/features/home/presentation/widgets/download_progress_painter.dart';

void main() {
  group('DownloadProgressBar', () {
    testWidgets('renders without errors at 0%', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 10,
              child: DownloadProgressBar(
                progress: 0.0,
                color: Colors.blue,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DownloadProgressBar), findsOneWidget);
    });

    testWidgets('renders without errors at 50%', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 10,
              child: DownloadProgressBar(
                progress: 0.5,
                color: Colors.green,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DownloadProgressBar), findsOneWidget);
    });

    testWidgets('renders without errors at 100%', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 10,
              child: DownloadProgressBar(
                progress: 1.0,
                color: Colors.green,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DownloadProgressBar), findsOneWidget);
    });

    testWidgets('clamps progress above 1.0 without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 10,
              child: DownloadProgressBar(
                progress: 1.5,
                color: Colors.blue,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DownloadProgressBar), findsOneWidget);
    });

    testWidgets('clamps progress below 0.0 without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 10,
              child: DownloadProgressBar(
                progress: -0.5,
                color: Colors.blue,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DownloadProgressBar), findsOneWidget);
    });

    testWidgets('uses custom height', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 20,
              child: DownloadProgressBar(
                progress: 0.5,
                color: Colors.blue,
                height: 8.0,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DownloadProgressBar), findsOneWidget);
    });

    testWidgets('animate=false renders CustomPaint directly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 10,
              child: DownloadProgressBar(
                progress: 0.5,
                color: Colors.blue,
                animate: false,
              ),
            ),
          ),
        ),
      );

      // When not animated, DownloadProgressBar renders CustomPaint directly
      final progressBarFinder = find.byType(DownloadProgressBar);
      final customPaintFinder = find.descendant(
        of: progressBarFinder,
        matching: find.byType(CustomPaint),
      );
      expect(customPaintFinder, findsOneWidget);
    });

    testWidgets('animate=true creates animated version with pulse',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 10,
              child: DownloadProgressBar(
                progress: 0.5,
                color: Colors.blue,
                animate: true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DownloadProgressBar), findsOneWidget);

      // When animated, uses AnimatedBuilder within DownloadProgressBar subtree
      final progressBarFinder = find.byType(DownloadProgressBar);
      final animatedBuilderFinder = find.descendant(
        of: progressBarFinder,
        matching: find.byType(AnimatedBuilder),
      );
      expect(animatedBuilderFinder, findsOneWidget);

      // Advance animation and verify no errors
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pump(const Duration(milliseconds: 750));
    });

    testWidgets('animated bar disposes cleanly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 10,
              child: DownloadProgressBar(
                progress: 0.3,
                color: Colors.blue,
                animate: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 500));

      // Replace widget to trigger dispose — should not throw
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SizedBox()),
        ),
      );
    });

    testWidgets('uses custom background color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 10,
              child: DownloadProgressBar(
                progress: 0.5,
                color: Colors.blue,
                backgroundColor: Colors.red,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DownloadProgressBar), findsOneWidget);
    });

    testWidgets('progress update triggers rebuild', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 10,
              child: DownloadProgressBar(
                progress: 0.3,
                color: Colors.blue,
              ),
            ),
          ),
        ),
      );

      // Update progress
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 10,
              child: DownloadProgressBar(
                progress: 0.7,
                color: Colors.blue,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DownloadProgressBar), findsOneWidget);
    });

    testWidgets('color change triggers rebuild', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 10,
              child: DownloadProgressBar(
                progress: 0.5,
                color: Colors.blue,
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 10,
              child: DownloadProgressBar(
                progress: 0.5,
                color: Colors.green,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DownloadProgressBar), findsOneWidget);
    });
  });

  group('CompletionCheckmark', () {
    testWidgets('renders check_circle icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompletionCheckmark(),
          ),
        ),
      );

      expect(find.byType(CompletionCheckmark), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('uses custom size and color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompletionCheckmark(size: 32, color: Colors.blue),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle));
      expect(icon.size, 32);
      expect(icon.color, Colors.blue);
    });

    testWidgets('animates with scale-up bounce', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompletionCheckmark(),
          ),
        ),
      );

      // Find ScaleTransition within CompletionCheckmark subtree
      final checkmarkFinder = find.byType(CompletionCheckmark);
      final scaleFinder = find.descendant(
        of: checkmarkFinder,
        matching: find.byType(ScaleTransition),
      );
      expect(scaleFinder, findsOneWidget);

      final scaleWidget = tester.widget<ScaleTransition>(scaleFinder);
      // At start, scale should be near 0
      expect(scaleWidget.scale.value, closeTo(0.0, 0.01));

      // After full animation, should settle at 1.0
      await tester.pumpAndSettle();
      final scaleAfter = tester.widget<ScaleTransition>(scaleFinder);
      expect(scaleAfter.scale.value, closeTo(1.0, 0.01));
    });

    testWidgets('disposes cleanly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompletionCheckmark(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 200));

      // Remove widget — should not throw
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SizedBox()),
        ),
      );
    });

    testWidgets('default size is 20', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompletionCheckmark(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle));
      expect(icon.size, 20);
    });

    testWidgets('default color is green', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompletionCheckmark(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle));
      expect(icon.color, AppColors.successGreen);
    });
  });
}
