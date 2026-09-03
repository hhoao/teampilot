import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_compare.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_command_runner.dart';
import 'package:teampilot/services/git/git_history_service.dart';
import 'package:teampilot/services/git/git_service.dart';

/// Same pattern as git_history_service_test.dart `_FakeRunner`.
class _FakeRunner {
  _FakeRunner(this.responses);
  final Map<String, ProcessResult> responses;
  final List<List<String>> calls = [];

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    final cIdx = arguments.indexOf('-C');
    if (cIdx < 0) return ProcessResult(0, 0, '/usr/bin/git\n', '');
    final cmd = arguments.sublist(cIdx + 2);
    calls.add(cmd);
    final key = cmd.join(' ');
    for (final e in responses.entries) {
      if (key.startsWith(e.key)) return e.value;
    }
    return ProcessResult(0, 0, '', '');
  }
}

ProcessResult ok([String stdout = '']) => ProcessResult(0, 0, stdout, '');

ProcessResult diffOut([String stdout = '']) => ProcessResult(0, 1, stdout, '');

void main() {
  setUp(GitService.debugResetExecutableCache);

  test('listDiffFiles ref vs working tree requests name-status and ls-files',
      () async {
    final fake = _FakeRunner({
      'diff --name-status --find-renames api-dev': diffOut('M\ta.txt\n'),
      'ls-files --others --exclude-standard': ok('new.txt\n'),
    });
    final history = GitHistoryService(
      runner: LocalGitCommandRunner(runner: fake.call),
    );
    final files = await history.listDiffFiles(
      '/repo',
      const GitCompareRef('api-dev'),
      const GitCompareWorkingTree(),
    );
    expect(files.map((f) => f.path), containsAll(['a.txt', 'new.txt']));
    expect(
      files.firstWhere((f) => f.path == 'new.txt').kind,
      GitChangeKind.untracked,
    );
    expect(
      files.firstWhere((f) => f.path == 'a.txt').kind,
      GitChangeKind.modified,
    );
    expect(files.every((f) => !f.staged), isTrue);
    expect(
      fake.calls.any(
        (c) =>
            c.length >= 4 &&
            c[0] == 'diff' &&
            c.contains('--name-status') &&
            c.contains('--find-renames') &&
            c.contains('api-dev'),
      ),
      isTrue,
    );
    expect(
      fake.calls.any(
        (c) =>
            c.join(' ').startsWith('ls-files --others --exclude-standard'),
      ),
      isTrue,
    );
  });

  test('listDiffFiles skips untracked path already in name-status', () async {
    final fake = _FakeRunner({
      'diff --name-status --find-renames HEAD': diffOut('A\tnew.txt\n'),
      'ls-files --others --exclude-standard': ok('new.txt\nother.txt\n'),
    });
    final history = GitHistoryService(
      runner: LocalGitCommandRunner(runner: fake.call),
    );
    final files = await history.listDiffFiles(
      '/repo',
      const GitCompareRef('HEAD'),
      const GitCompareWorkingTree(),
    );
    expect(files.where((f) => f.path == 'new.txt'), hasLength(1));
    expect(
      files.firstWhere((f) => f.path == 'new.txt').kind,
      GitChangeKind.added,
    );
    expect(
      files.firstWhere((f) => f.path == 'other.txt').kind,
      GitChangeKind.untracked,
    );
  });

  test('listDiffFiles ref vs ref uses name-status without ls-files', () async {
    final fake = _FakeRunner({
      'diff --name-status --find-renames A B': diffOut(
        'M\tx.txt\n'
        'R100\told.txt\tnew.txt\n',
      ),
    });
    final history = GitHistoryService(
      runner: LocalGitCommandRunner(runner: fake.call),
    );
    final files = await history.listDiffFiles(
      '/repo',
      const GitCompareRef('A'),
      const GitCompareRef('B'),
    );
    expect(files.map((f) => f.path).toList(), ['x.txt', 'new.txt']);
    expect(files[1].kind, GitChangeKind.renamed);
    expect(files[1].originalPath, 'old.txt');
    expect(fake.calls.any((c) => c.first == 'ls-files'), isFalse);
  });

  test('fileDiff untracked uses --no-index', () async {
    final fake = _FakeRunner({
      'diff --no-index': diffOut('diff --git a/new.txt\n'),
    });
    final history = GitHistoryService(
      runner: LocalGitCommandRunner(runner: fake.call),
    );
    await history.fileDiff(
      '/repo',
      const GitCompareRef('HEAD'),
      const GitCompareWorkingTree(),
      'new.txt',
      untracked: true,
    );
    final last = fake.calls.last;
    expect(last, contains('--no-index'));
    expect(last, contains('/dev/null'));
    expect(last, contains('new.txt'));
  });

  test('fileDiff ref vs working tree tracked diffs against ref', () async {
    final fake = _FakeRunner({
      'diff': diffOut('diff --git a/a.txt\n'),
    });
    final history = GitHistoryService(
      runner: LocalGitCommandRunner(runner: fake.call),
    );
    await history.fileDiff(
      '/repo',
      const GitCompareRef('api-dev'),
      const GitCompareWorkingTree(),
      'a.txt',
      ignoreWhitespace: true,
      fullContext: true,
    );
    final last = fake.calls.last;
    expect(last.first, 'diff');
    expect(last, contains('--no-color'));
    expect(last, contains('-w'));
    expect(last, contains('-U1000000'));
    expect(last, contains('api-dev'));
    expect(last, containsAllInOrder(['--', 'a.txt']));
    expect(last.contains('--no-index'), isFalse);
  });

  test('fileDiff ref vs ref diffs the two refs', () async {
    final fake = _FakeRunner({
      'diff': diffOut('diff --git a/a.txt\n'),
    });
    final history = GitHistoryService(
      runner: LocalGitCommandRunner(runner: fake.call),
    );
    await history.fileDiff(
      '/repo',
      const GitCompareRef('A'),
      const GitCompareRef('B'),
      'a.txt',
    );
    final last = fake.calls.last;
    expect(last.first, 'diff');
    expect(last, containsAllInOrder(['A', 'B', '--', 'a.txt']));
  });
}
