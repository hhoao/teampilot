import 'package:flutter_test/flutter_test.dart';

import '../../tool/run_tests.dart';

void main() {
  test(
    'default invocation excludes integration tests and caps concurrency',
    () {
      expect(buildFlutterTestArgs(const []), [
        'test',
        '--exclude-tags',
        'integration',
        '--concurrency=4',
      ]);
    },
  );

  test('single-test invocation preserves the requested path', () {
    expect(buildFlutterTestArgs(const ['test/pages/example_test.dart']), [
      'test',
      '--exclude-tags',
      'integration',
      '--concurrency=4',
      'test/pages/example_test.dart',
    ]);
  });

  test('explicit long-form concurrency is not overridden', () {
    expect(buildFlutterTestArgs(const ['--concurrency=2', 'test/models']), [
      'test',
      '--exclude-tags',
      'integration',
      '--concurrency=2',
      'test/models',
    ]);
  });

  test('explicit short-form concurrency is not overridden', () {
    expect(buildFlutterTestArgs(const ['-j', '1', 'test/services/terminal']), [
      'test',
      '--exclude-tags',
      'integration',
      '-j',
      '1',
      'test/services/terminal',
    ]);
  });

  test('explicit tag selection controls integration filtering', () {
    expect(
      buildFlutterTestArgs(const ['--tags', 'integration && cross-platform']),
      ['test', '--concurrency=4', '--tags', 'integration && cross-platform'],
    );
  });
}
