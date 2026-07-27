import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/git_process_stderr.dart';

void main() {
  test('skips cloning-into progress and keeps real error', () {
    final r = ProcessResult(1, 128, '', '''
正克隆到 '/tmp/foo'...
fatal: destination path '/tmp/foo' already exists and is not an empty directory.
''');
    final s = gitProcessStderrSnippet(r);
    expect(s, contains('fatal:'));
    expect(s.contains('正克隆到'), isFalse);
  });

  test('english Cloning into is skipped', () {
    final r = ProcessResult(
      1,
      128,
      '',
      "Cloning into '/tmp/x'...\nfatal: unable to access 'https://example.com/': Failed\n",
    );
    expect(gitProcessStderrSnippet(r), contains('fatal:'));
  });

  test('empty stderr uses exit code', () {
    expect(
      gitProcessStderrSnippet(ProcessResult(1, 1, '', '')),
      'exit 1',
    );
  });
}
