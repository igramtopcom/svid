import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/premium/domain/entities/premium_feature.dart';
import 'package:svid/features/premium/presentation/widgets/upgrade_prompt_dialog.dart';

void main() {
  Widget buildTestApp({required Widget child}) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('UpgradePromptDialog', () {
    testWidgets('shows dialog with upgrade icon', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => UpgradePromptDialog.show(context),
            child: const Text('Open'),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byIcon(Icons.stars_rounded), findsWidgets);
    });

    testWidgets('shows feature info when feature is provided', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => UpgradePromptDialog.show(
              context,
              feature: PremiumFeature.advancedAnalytics,
            ),
            child: const Text('Open'),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Feature icon should be present
      expect(find.byIcon(Icons.bar_chart), findsOneWidget);
    });

    testWidgets('cancel button returns false', (tester) async {
      bool? result;

      await tester.pumpWidget(buildTestApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              result = await UpgradePromptDialog.show(context);
            },
            child: const Text('Open'),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap Cancel
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('upgrade button returns true', (tester) async {
      bool? result;

      await tester.pumpWidget(buildTestApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              result = await UpgradePromptDialog.show(context);
            },
            child: const Text('Open'),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap the Upgrade MaterialButton (gradient CTA in Nocturne Cinematic dialog)
      await tester.tap(find.byWidgetPredicate((w) => w is MaterialButton));
      await tester.pumpAndSettle();

      expect(result, true);
    });

    testWidgets('shows without feature (generic upgrade)', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => UpgradePromptDialog.show(context),
            child: const Text('Open'),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      // No feature-specific icon (only the main premium icon)
      expect(find.byIcon(Icons.bar_chart), findsNothing);
    });
  });

  group('UpgradePromptDialog static helpers', () {
    test('featureIcon returns correct icon for each feature', () {
      expect(
        UpgradePromptDialog.featureIcon(PremiumFeature.unlimitedDownloads),
        Icons.all_inclusive,
      );
      expect(
        UpgradePromptDialog.featureIcon(PremiumFeature.highQuality4K),
        Icons.hd,
      );
      expect(
        UpgradePromptDialog.featureIcon(PremiumFeature.browserShield),
        Icons.shield,
      );
      expect(
        UpgradePromptDialog.featureIcon(PremiumFeature.advancedAnalytics),
        Icons.bar_chart,
      );
      expect(
        UpgradePromptDialog.featureIcon(PremiumFeature.scheduledDownloads),
        Icons.schedule,
      );
      expect(
        UpgradePromptDialog.featureIcon(PremiumFeature.smartCollections),
        Icons.folder_special,
      );
    });

    test('featureIcon covers all PremiumFeature values', () {
      for (final feature in PremiumFeature.values) {
        // Should not throw — exhaustive switch
        expect(
          UpgradePromptDialog.featureIcon(feature),
          isA<IconData>(),
        );
      }
    });

    test('featureDisplayName covers all PremiumFeature values', () {
      for (final feature in PremiumFeature.values) {
        final name = UpgradePromptDialog.featureDisplayName(feature);
        expect(name, isNotEmpty);
      }
    });
  });
}
