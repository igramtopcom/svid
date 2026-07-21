import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/presentation/widgets/priority_badge.dart';

void main() {
  group('PriorityBadge', () {
    testWidgets('shows bolt icon when isHigh is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PriorityBadge(isHigh: true),
          ),
        ),
      );

      expect(find.byIcon(Icons.bolt), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
    });

    testWidgets('shows bolt icon when isSmartBoosted is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PriorityBadge(isSmartBoosted: true),
          ),
        ),
      );

      expect(find.byIcon(Icons.bolt), findsOneWidget);
    });

    testWidgets('shows arrow_downward icon when isLow is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PriorityBadge(isLow: true),
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      expect(find.byIcon(Icons.bolt), findsNothing);
    });

    testWidgets('shows nothing (SizedBox.shrink) for default/normal priority', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PriorityBadge(),
          ),
        ),
      );

      expect(find.byIcon(Icons.bolt), findsNothing);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget);
    });
  });
}
