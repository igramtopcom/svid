import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/services/noop_error_reporter.dart';

import 'fake_error_reporter.dart';

void main() {
  group('NoOpErrorReporter', () {
    late NoOpErrorReporter reporter;

    setUp(() {
      reporter = NoOpErrorReporter();
    });

    test('init completes without error', () async {
      await expectLater(reporter.init(), completes);
    });

    test('captureException completes without error', () async {
      await expectLater(
        reporter.captureException(Exception('test'), stackTrace: StackTrace.current),
        completes,
      );
    });

    test('captureMessage completes without error', () async {
      await expectLater(reporter.captureMessage('test message'), completes);
    });

    test('addBreadcrumb does not throw', () {
      expect(() => reporter.addBreadcrumb('test', data: {'key': 'value'}), returnsNormally);
    });

    test('setTag does not throw', () {
      expect(() => reporter.setTag('env', 'test'), returnsNormally);
    });

    test('setUserIdentifier does not throw', () {
      expect(
        () => reporter.setUserIdentifier('123', username: 'user', email: 'a@b.com'),
        returnsNormally,
      );
    });

    test('clearUserIdentifier does not throw', () {
      expect(() => reporter.clearUserIdentifier(), returnsNormally);
    });

    test('navigationObserver returns null', () {
      expect(reporter.navigationObserver, isNull);
    });

    test('setEnabled does not throw', () {
      expect(() => reporter.setEnabled(false), returnsNormally);
    });
  });

  group('FakeErrorReporter', () {
    late FakeErrorReporter reporter;

    setUp(() {
      reporter = FakeErrorReporter();
    });

    test('records init call', () async {
      expect(reporter.initCalled, isFalse);
      await reporter.init();
      expect(reporter.initCalled, isTrue);
    });

    test('records captured exceptions', () async {
      final error = Exception('test error');
      await reporter.captureException(error, context: 'test_context');

      expect(reporter.capturedExceptions, hasLength(1));
      expect(reporter.capturedExceptions.first.exception, equals(error));
      expect(reporter.capturedExceptions.first.context, equals('test_context'));
    });

    test('records captured messages', () async {
      await reporter.captureMessage('hello');
      await reporter.captureMessage('world');

      expect(reporter.capturedMessages, equals(['hello', 'world']));
    });

    test('records breadcrumbs', () {
      reporter.addBreadcrumb('step 1');
      reporter.addBreadcrumb('step 2');

      expect(reporter.breadcrumbs, equals(['step 1', 'step 2']));
    });

    test('records tags', () {
      reporter.setTag('env', 'test');
      reporter.setTag('version', '1.0.0');

      expect(reporter.tags, equals({'env': 'test', 'version': '1.0.0'}));
    });

    test('records user identifier', () {
      reporter.setUserIdentifier('u1', username: 'alice', email: 'a@b.com');

      expect(reporter.userId, equals('u1'));
      expect(reporter.userUsername, equals('alice'));
      expect(reporter.userEmail, equals('a@b.com'));
    });

    test('clears user identifier', () {
      reporter.setUserIdentifier('u1', username: 'alice');
      reporter.clearUserIdentifier();

      expect(reporter.userId, isNull);
      expect(reporter.userUsername, isNull);
    });

    test('reset clears all recorded data', () async {
      await reporter.init();
      await reporter.captureException(Exception('e'));
      await reporter.captureMessage('msg');
      reporter.addBreadcrumb('b');
      reporter.setTag('k', 'v');
      reporter.setUserIdentifier('u1');

      reporter.reset();

      expect(reporter.initCalled, isFalse);
      expect(reporter.capturedExceptions, isEmpty);
      expect(reporter.capturedMessages, isEmpty);
      expect(reporter.breadcrumbs, isEmpty);
      expect(reporter.tags, isEmpty);
      expect(reporter.userId, isNull);
    });
  });
}
