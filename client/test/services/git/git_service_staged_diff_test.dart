import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/git/git_service.dart';

class _FakeRunner {
  _FakeRunner(this.stagedDiffOut);
  final String stagedDiffOut;
  final List<List<String>> calls = [];

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    if (!arguments.contains('-C')) return ProcessResult(0, 0, '/usr/bin/git\n', '');
    calls.add(arguments);
    return ProcessResult(0, 0, stagedDiffOut, '');
  }
}

void main() {
  test('stagedDiff runs git diff --cached --no-color', () async {
    final runner = _FakeRunner('diff body');
    final service = GitService(runner: runner.call);

    final out = await service.stagedDiff('/repo');

    expect(out, 'diff body');
    expect(runner.calls.single.sublist(2), ['diff', '--cached', '--no-color']);
  });

  test('stagedDiff truncates oversized output', () async {
    final big = 'x' * 20000;
    final service = GitService(runner: _FakeRunner(big).call);

    final out = await service.stagedDiff('/repo', maxChars: 100);

    expect(out.length, lessThan(big.length));
    expect(out, contains('diff truncated'));
  });
}
