import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_cubit.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/headless_ai_service.dart';
import 'package:teampilot/services/git/git_service.dart';

class _StubGitService extends GitService {
  _StubGitService(this._diff);
  final String _diff;

  /// Each `diffSelectedPaths` invocation's path list (selection order).
  final List<List<String>> diffSelectedPathsCalls = [];

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<String> stagedDiff(String dir, {int maxChars = 12000}) async => _diff;

  @override
  Future<String> diffSelectedPaths(String dir, List<String> paths) async {
    diffSelectedPathsCalls.add(paths);
    return _diff;
  }
}

const _setting = AiFeatureSetting(
  cli: CliTool.claude,
  providerId: 'p',
  model: 'm',
);

/// A repo whose selection contains `a.txt` (the index may be empty in the
/// selection model — generate must not care).
GitState _withSelection() => const GitState(
  repoRoot: '/repo',
  selectedPaths: {'a.txt'},
  status: GitRepoStatus(
    isRepository: true,
    staged: [
      GitFileChange(path: 'a.txt', kind: GitChangeKind.modified, staged: true),
    ],
    unstaged: [],
  ),
);

HeadlessAiService _headless({
  required void Function() onRun,
  bool failResolve = false,
}) {
  return HeadlessAiService(
    resolveProvider: (_, __) async => null,
    resolveExecutable: (name) async => failResolve ? null : name,
    tempDirFactory: () async => Directory.systemTemp.createTempSync('gc_'),
    resolveProvisionCapability: (_) => null,
    run: (exe, args, {environment, workingDirectory, timeout}) async {
      onRun();
      return ProcessResult(0, 0, '```\nfeat: generated\n```', '');
    },
  );
}

void main() {
  test('fills commit message from the AI result, diffing the selected paths',
      () async {
    var aiRuns = 0;
    final service = _StubGitService('diff');
    final cubit = GitCubit(
      service: service,
      headless: _headless(onRun: () => aiRuns++),
    );
    cubit.debugSetState(_withSelection());

    await cubit.generateCommitMessage(_setting);

    expect(service.diffSelectedPathsCalls, [
      ['a.txt'],
    ]);
    expect(cubit.state.commitMessage, 'feat: generated');
    expect(cubit.state.generatingCommitMessage, isFalse);
    expect(aiRuns, 1);
  });

  test('sets error on headless failure', () async {
    var aiRuns = 0;
    final service = _StubGitService('diff');
    final cubit = GitCubit(
      service: service,
      headless: _headless(onRun: () => aiRuns++, failResolve: true),
    );
    cubit.debugSetState(_withSelection());

    await cubit.generateCommitMessage(_setting);

    expect(cubit.state.errorMessage, isNotNull);
    expect(cubit.state.generatingCommitMessage, isFalse);
    expect(service.diffSelectedPathsCalls, [
      ['a.txt'],
    ]);
    expect(aiRuns, 0); // headless failed to resolve; run never invoked
  });

  test('no-op when nothing selected (no diff, no AI call)', () async {
    var aiRuns = 0;
    final service = _StubGitService('diff');
    final cubit = GitCubit(
      service: service,
      headless: _headless(onRun: () => aiRuns++),
    );
    cubit.debugSetState(const GitState(repoRoot: '/repo'));

    await cubit.generateCommitMessage(_setting);

    expect(cubit.state.commitMessage, '');
    expect(service.diffSelectedPathsCalls, isEmpty);
    expect(aiRuns, 0);
  });

  test('selected paths drive the diff even when the git index is empty', () async {
    var aiRuns = 0;
    final service = _StubGitService('diff');
    final cubit = GitCubit(
      service: service,
      headless: _headless(onRun: () => aiRuns++),
    );
    // Selection model: nothing is staged in the index, but `b.txt` is selected.
    cubit.debugSetState(
      const GitState(
        repoRoot: '/repo',
        selectedPaths: {'b.txt'},
        status: GitRepoStatus(
          isRepository: true,
          staged: [],
          unstaged: [
            GitFileChange(
              path: 'b.txt',
              kind: GitChangeKind.untracked,
              staged: false,
            ),
          ],
        ),
      ),
    );

    await cubit.generateCommitMessage(_setting);

    expect(service.diffSelectedPathsCalls, [
      ['b.txt'],
    ]);
    expect(cubit.state.commitMessage, 'feat: generated');
    expect(aiRuns, 1);
  });
}
