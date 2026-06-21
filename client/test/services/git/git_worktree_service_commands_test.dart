import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/git/git_worktree_service.dart';

/// Fake [ProcessRunner]: no `-C` arg == the locate probe; otherwise record the
/// git subcommand (args after `-C <dir>`) and return scripted output.
class _FakeRunner {
  _FakeRunner({this.listOutput = '', this.failRemoveBranch = false});
  final String listOutput;
  final bool failRemoveBranch;
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
    if (cmd.length >= 2 && cmd[0] == 'worktree' && cmd[1] == 'list') {
      return ProcessResult(0, 0, listOutput, '');
    }
    if (failRemoveBranch && cmd.isNotEmpty && cmd[0] == 'branch') {
      return ProcessResult(0, 1, '', 'error: branch not fully merged');
    }
    return ProcessResult(0, 0, '', '');
  }
}

void main() {
  test('list parses -z porcelain output', () async {
    final runner = _FakeRunner(
      listOutput: 'worktree /repo\x00HEAD abc\x00branch refs/heads/main\x00\x00',
    );
    final svc = GitWorktreeService(runner: runner.call);
    final list = await svc.list('/repo');
    expect(list, hasLength(1));
    expect(list.first.path, '/repo');
    expect(list.first.branch, 'refs/heads/main');
  });

  test('add new branch uses --no-track -b with base', () async {
    final runner = _FakeRunner();
    final svc = GitWorktreeService(runner: runner.call);
    await svc.add('/repo', '/wt/feat', branch: 'feat/x', baseRef: 'origin/main');
    expect(
      runner.calls.last,
      ['worktree', 'add', '--no-track', '-b', 'feat/x', '/wt/feat', 'origin/main'],
    );
  });

  test('add new branch without base omits trailing base ref', () async {
    final runner = _FakeRunner();
    final svc = GitWorktreeService(runner: runner.call);
    await svc.add('/repo', '/wt/feat', branch: 'feat/x');
    expect(runner.calls.last,
        ['worktree', 'add', '--no-track', '-b', 'feat/x', '/wt/feat']);
  });

  test('add existing branch omits -b', () async {
    final runner = _FakeRunner();
    final svc = GitWorktreeService(runner: runner.call);
    await svc.add('/repo', '/wt/feat', branch: 'feat/x', existingBranch: true);
    expect(runner.calls.last, ['worktree', 'add', '/wt/feat', 'feat/x']);
  });

  test('remove with force passes --force', () async {
    final runner = _FakeRunner();
    final svc = GitWorktreeService(runner: runner.call);
    await svc.remove('/repo', '/wt/feat', force: true);
    expect(runner.calls.last, ['worktree', 'remove', '--force', '/wt/feat']);
  });

  test('remove with deleteBranch also runs branch -d', () async {
    final runner = _FakeRunner();
    final svc = GitWorktreeService(runner: runner.call);
    await svc.remove('/repo', '/wt/feat', deleteBranch: 'feat/x');
    expect(runner.calls[runner.calls.length - 2],
        ['worktree', 'remove', '/wt/feat']);
    expect(runner.calls.last, ['branch', '-d', '--', 'feat/x']);
  });

  test('remove tolerates branch -d failure (unmerged branch preserved)', () async {
    final runner = _FakeRunner(failRemoveBranch: true);
    final svc = GitWorktreeService(runner: runner.call);
    // Should NOT throw even though `branch -d` exits non-zero.
    await svc.remove('/repo', '/wt/feat', deleteBranch: 'feat/x');
    expect(runner.calls.last, ['branch', '-d', '--', 'feat/x']);
  });
}
