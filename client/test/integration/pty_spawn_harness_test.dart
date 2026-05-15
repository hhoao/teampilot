@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pty/flutter_pty.dart';

/// Exercises real [Pty.start] the same way TeamPilot does when flashskyai is missing.
void main() {
  test('missing flashskyai via Pty.start exits without hanging test runner', () async {
    final pty = Pty.start(
      'flashskyai-missing-for-harness-test',
      arguments: const ['--help'],
      workingDirectory: Directory.current.path,
      columns: 80,
      rows: 24,
    );

    final exitCode = await pty.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw StateError('PTY exitCode hung >5s'),
    );

    pty.kill();
    expect(exitCode, isNonZero);
  }, skip: !Platform.isLinux);

  test('parallel failed Pty spawns are known to hang on Linux', () async {
    // Documents flutter_pty behaviour: do not spawn many failing PTYs at once.
    // TeamPilot serializes Pty.start and validates PATH before spawning.
    final exits = <Future<int>>[];
    for (var i = 0; i < 4; i++) {
      final pty = Pty.start(
        'flashskyai-missing-for-harness-test',
        arguments: const [],
        workingDirectory: Directory.current.path,
        columns: 80,
        rows: 24,
      );
      exits.add(
        pty.exitCode.timeout(
          const Duration(seconds: 2),
          onTimeout: () => -999,
        ),
      );
    }

    final codes = await Future.wait(exits);
    expect(codes, everyElement(isNonZero));
  }, skip: !Platform.isLinux);
}
