import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_graph_actions_controller.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/services/git/git_service.dart';

import '../support/git_graph_test_fakes.dart';

void main() {
  late RecordingGraphActions actions;

  setUp(() => actions = RecordingGraphActions());

  Future<(GitGraphCubit, GitGraphActionsController)> build() async {
    final cubit = GitGraphCubit(
      history: FakeHistoryForGraph(rows: [graphCommitRow('c1')]),
      git: FakeGitForGraph(repoStatus()),
      actions: actions,
    );
    await cubit.setRepoRoot('/repo');
    return (cubit, GitGraphActionsController(cubit: cubit));
  }

  test('createBranch delegates then refreshes without error', () async {
    final (cubit, controller) = await build();
    expect(await controller.createBranch('dev', atHash: 'c1'), isTrue);
    expect(actions.calls.single, ['branch', 'dev', 'c1']);
    expect(cubit.state.errorMessage, isNull);
    expect((cubit.state.rows.single as GitCommitRow).hash, 'c1'); // 刷新后数据仍在
    await cubit.close();
  });

  test('failure surfaces error and returns false', () async {
    actions.throwNext = GitException('conflict');
    final (cubit, controller) = await build();
    expect(await controller.deleteBranch('dev'), isFalse);
    expect(cubit.state.errorMessage, contains('conflict'));
    await cubit.close();
  });

  test('resetTo hard maps mode flag', () async {
    final (cubit, controller) = await build();
    expect(await controller.resetTo('main', mode: GitResetMode.hard), isTrue);
    expect(actions.calls.single, ['reset', '--hard', 'main']);
    await cubit.close();
  });

  test('checkoutRemoteBranch splits remote prefix from full name', () async {
    final (cubit, controller) = await build();
    expect(await controller.checkoutRemoteBranch('origin/feature-x'), isTrue);
    expect(
      actions.calls.single,
      ['checkout-remote-branch', 'origin', 'feature-x'],
    );
    await cubit.close();
  });

  test('checkoutRemoteBranch keeps slashes after the remote segment', () async {
    final (cubit, controller) = await build();
    expect(
      await controller.checkoutRemoteBranch('origin/feature/nested'),
      isTrue,
    );
    expect(
      actions.calls.single,
      ['checkout-remote-branch', 'origin', 'feature/nested'],
    );
    await cubit.close();
  });

  test('checkoutTag delegates to actions', () async {
    final (cubit, controller) = await build();
    expect(await controller.checkoutTag('v1.0'), isTrue);
    expect(actions.calls.single, ['checkout-tag', 'v1.0']);
    await cubit.close();
  });

  test('deleteRemoteBranch splits remote prefix from full name', () async {
    final (cubit, controller) = await build();
    expect(await controller.deleteRemoteBranch('origin/feature-x'), isTrue);
    expect(
      actions.calls.single,
      ['delete-remote-branch', 'origin', 'feature-x'],
    );
    await cubit.close();
  });
}
