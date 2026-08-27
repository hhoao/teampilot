import 'package:flutter_test/flutter_test.dart';

import '../../tool/run_tests.dart';

void main() {
  group('firstHostedUrl', () {
    test('extracts the url of the first hosted package', () {
      const lock = '''
packages:
  analyzer:
    dependency: "direct main"
    description:
      name: analyzer
      sha256: "abc"
      url: "https://pub.dev"
    source: hosted
    version: "14.1.0"
''';
      expect(firstHostedUrl(lock), 'https://pub.dev');
    });

    test('returns null when no package is hosted', () {
      const lock = '''
packages:
  shared_ui:
    dependency: "direct main"
    description:
      path: "../packages/shared_ui"
      relative: true
    source: path
    version: "0.0.0"
''';
      expect(firstHostedUrl(lock), isNull);
    });
  });

  group('normalizeHostedUrl', () {
    test('ignores trailing slashes', () {
      expect(
        normalizeHostedUrl('https://pub.flutter-io.cn/'),
        'https://pub.flutter-io.cn',
      );
    });
  });

  group('pubSourceMismatchMessage', () {
    test('accepts an exact match', () {
      expect(
        pubSourceMismatchMessage(
          lockedUrl: 'https://pub.dev',
          effectiveSource: 'https://pub.dev',
        ),
        isNull,
      );
    });

    test('accepts a match modulo trailing slash', () {
      expect(
        pubSourceMismatchMessage(
          lockedUrl: 'https://pub.dev',
          effectiveSource: 'https://pub.dev/',
        ),
        isNull,
      );
    });

    test('skips the check without a locked hosted url', () {
      expect(
        pubSourceMismatchMessage(lockedUrl: null, effectiveSource: null),
        isNull,
      );
    });

    test('reports drift with remediation guidance', () {
      final message = pubSourceMismatchMessage(
        lockedUrl: 'https://pub.dev',
        effectiveSource: 'https://pub.flutter-io.cn',
      );
      expect(message, isNotNull);
      expect(message, contains('PUB_HOSTED_URL'));
      expect(message, contains('RUN_TESTS_ALLOW_PUB_SOURCE_MISMATCH'));
    });
  });
}
