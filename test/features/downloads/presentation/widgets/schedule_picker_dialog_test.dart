import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/presentation/widgets/schedule_picker_dialog.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SchedulePickerDialog', () {
    testWidgets('renders date and time list tiles', (tester) async {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => SchedulePickerDialog.show(ctx),
            child: const Text('Open'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Dialog should show date-related icon
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });

    testWidgets('Cancel button dismisses dialog without returning value', (tester) async {
      ScheduleResult? result;
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await SchedulePickerDialog.show(ctx);
            },
            child: const Text('Open'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // In pure-unit test env without EasyLocalization wrap, `.tr()` returns
      // the raw key `common.cancel` instead of localized "Cancel". Match by
      // either to keep the contract holding in both environments.
      final cancelFinder = find.text('Cancel').evaluate().isNotEmpty
          ? find.text('Cancel')
          : find.text('common.cancel');
      await tester.tap(cancelFinder);
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });
}
