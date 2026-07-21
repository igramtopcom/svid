import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/widgets/app_confirm_dialog.dart';

void main() {
  Future<_DialogHandle> openDialog(
    WidgetTester tester, {
    bool isDestructive = false,
  }) async {
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => TextButton(
                onPressed: () {
                  result = AppConfirmDialog.show(
                    context,
                    title: 'Confirm action',
                    message: 'Proceed with action?',
                    confirmLabel: 'Confirm',
                    cancelLabel: 'Cancel',
                    isDestructive: isDestructive,
                  );
                },
                child: const Text('Open'),
              ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return _DialogHandle(result);
  }

  testWidgets('Enter confirms non-destructive dialogs', (tester) async {
    final handle = await openDialog(tester);

    expect(find.text('Confirm action'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(await handle.result, isTrue);
    expect(find.text('Confirm action'), findsNothing);
  });

  testWidgets('Enter does not confirm destructive dialogs', (tester) async {
    final handle = await openDialog(tester, isDestructive: true);

    expect(find.text('Confirm action'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Confirm action'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(await handle.result, isTrue);
  });
}

class _DialogHandle {
  final Future<bool> result;

  const _DialogHandle(this.result);
}
