// client/test/services/git/git_history_actions_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/services/git/git_command_runner.dart';
import 'package:teampilot/services/git/git_history_actions.dart';
import 'package:teampilot/services/git/git_service.dart';

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
    for (final e in responses.entries) {
      if (cmd.join(' ').startsWith(e.key)) return e.value;
    }
    return ProcessResult(0, 0, '', '');
  }
}

void main() {
  setUp(GitService.debugResetExecutableCache);
  late _FakeRunner fake;
  late GitHistoryActions actions;

  setUp(() {
    fake = _FakeRunner({});
    actions = GitHistoryActions(runner: LocalGitCommandRunner(runner: fake.call));
  });

  test('resetTo maps mode to flag', () async {
    await actions.resetTo('/r', 'main', mode: GitResetMode.hard);
    expect(fake.calls.single.sublist(0, 3), ['reset', '--hard', 'main']);
    await actions.resetTo('/r', 'h1', mode: GitResetMode.soft);
    expect(fake.calls.last[1], '--soft');
  });

  test('createTag annotated includes -a -m and optional start point',
      () async {
    await actions.createTag('/r', 'v2', at: 'h1', message: 'release');
    expect(fake.calls.single,
        ['tag', '-a', 'v2', '-m', 'release', 'h1']);
  });

  test('deleteBranch uses -d unless force', () async {
    await actions.deleteBranch('/r', 'dev');
    expect(fake.calls.single, ['branch', '-d', 'dev']);
    await actions.deleteBranch('/r', 'dev', force: true);
    expect(fake.calls.last, ['branch', '-D', 'dev']);
  });

  test('revert/cherry-pick/checkout-commit arg shapes', () async {
    await actions.revert('/r', 'h1');
    expect(fake.calls.single, ['revert', '--no-edit', 'h1']);
    await actions.cherryPick('/r', 'h2');
    expect(fake.calls[1], ['cherry-pick', 'h2']);
    await actions.checkoutCommit('/r', 'h3');
    expect(fake.calls.last, ['checkout', 'h3']);
  });

  test('stash pop/apply/drop with optional ref', () async {
    await actions.stashPop('/r');
    expect(fake.calls.single, ['stash', 'pop']);
    await actions.stashApply('/r', ref: 'stash@{1}');
    expect(fake.calls.last, ['stash', 'apply', 'stash@{1}']);
    await actions.stashDrop('/r', ref: 'stash@{0}');
    expect(fake.calls.last, ['stash', 'drop', 'stash@{0}']);
  });
}
