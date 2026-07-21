import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/youtube_search/presentation/widgets/youtube_search_skeleton.dart';

void main() {
  testWidgets('renders shrink-wrapped pagination skeleton inside a ListView', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [
              SizedBox(height: 120),
              YouTubeSearchSkeleton(itemCount: 2, shrinkWrap: true),
            ],
          ),
        ),
      ),
    );

    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(YouTubeSearchSkeleton), findsOneWidget);
  });
}
