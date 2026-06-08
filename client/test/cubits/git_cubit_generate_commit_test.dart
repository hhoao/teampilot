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
  @override
  Future<bool> get isAvailable async => true;
  @override
  Future<String> stagedDiff(String dir, {int maxChars = 12000}) async => _diff;
}

const _setting = AiFeatureSetting(
  cli: CliTool.claude,
  providerId: 'p',
  model: 'm',
);

GitState _withStaged() => const GitState(
  repoRoot: '/repo',
  status: GitRepoStatus(
    isRepository: true,
    staged: [GitFileChange(path: 'a.txt', kind: GitChangeKind.modified, staged: true)],
    unstaged: [],
  ),
);

void main() {
  test('fills commit message from the AI result', () async {
    final headless = HeadlessAiService(
      resolveProvider: (_, __) async => null,
      resolveExecutable: (name) async => name,
      tempDirFactory: () async =>
          Directory.systemTemp.createTempSync('gc_'),
      resolveProvisionCapability: (_) => null,
      run: (exe, args, {environment, workingDirectory, timeout}) async =>
          ProcessResult(0, 0, '```\nfeat: generated\n```', ''),
    );
    final cubit = GitCubit(service: _StubGitService('diff'), headless: headless);
    cubit.debugSetState(_withStaged());

    await cubit.generateCommitMessage(_setting);

    expect(cubit.state.commitMessage, 'feat: generated');
    expect(cubit.state.generatingCommitMessage, isFalse);
  });

  test('sets error on headless failure', () async {
    final headless = HeadlessAiService(
      resolveProvider: (_, __) async => null,
      resolveExecutable: (_) async => null,
      tempDirFactory: () async => Directory.systemTemp.createTempSync('gc_'),
      resolveProvisionCapability: (_) => null,
      run: (exe, args, {environment, workingDirectory, timeout}) async =>
          ProcessResult(0, 0, '', ''),
    );
    final cubit = GitCubit(service: _StubGitService('diff'), headless: headless);
    cubit.debugSetState(_withStaged());

    await cubit.generateCommitMessage(_setting);

    expect(cubit.state.errorMessage, isNotNull);
    expect(cubit.state.generatingCommitMessage, isFalse);
  });

  test('no-op when nothing staged', () async {
    final cubit = GitCubit(service: _StubGitService('diff'));
    cubit.debugSetState(const GitState(repoRoot: '/repo'));
    await cubit.generateCommitMessage(_setting);
    expect(cubit.state.commitMessage, '');
  });
}
