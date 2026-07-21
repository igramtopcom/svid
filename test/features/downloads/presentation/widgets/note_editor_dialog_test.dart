import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/presentation/widgets/note_editor_dialog.dart';

void main() {
  Widget buildTestApp({required Widget child}) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('NoteEditorDialog', () {
    testWidgets('shows empty TextField when initialNote is empty', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              await NoteEditorDialog.show(context);
            },
            child: const Text('Open'),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, isEmpty);
    });

    testWidgets('pre-fills TextField with initialNote', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              await NoteEditorDialog.show(context, initialNote: 'Hello world');
            },
            child: const Text('Open'),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, 'Hello world');
    });

    testWidgets('cancel returns null', (tester) async {
      String? result = 'sentinel';
      await tester.pumpWidget(buildTestApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              result = await NoteEditorDialog.show(context, initialNote: 'test');
            },
            child: const Text('Open'),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap Cancel (TextButton) — find by type since l10n renders key path
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('save returns entered text', (tester) async {
      String? result;
      await tester.pumpWidget(buildTestApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              result = await NoteEditorDialog.show(context);
            },
            child: const Text('Open'),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'My note');
      // Tap Save (FilledButton)
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(result, 'My note');
    });

    testWidgets('save returns empty string when text cleared', (tester) async {
      String? result;
      await tester.pumpWidget(buildTestApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              result = await NoteEditorDialog.show(context, initialNote: 'old note');
            },
            child: const Text('Open'),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Clear via clear button (IconButton with Icons.clear)
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      // Tap Save (FilledButton)
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(result, '');
    });

    testWidgets('maxLength is enforced at 200', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              await NoteEditorDialog.show(context);
            },
            child: const Text('Open'),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.maxLength, 200);
    });

    testWidgets('maxLines is 3', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              await NoteEditorDialog.show(context);
            },
            child: const Text('Open'),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.maxLines, 3);
    });
  });
}
