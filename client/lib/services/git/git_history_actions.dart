import '../../models/git_graph.dart';
import '../../utils/logging/logger.dart';
import '../storage/runtime_context.dart';
import 'git_command_runner.dart';
import 'git_service.dart' show GitException;

/// 历史写操作（分支/标签/提交级/stash/fetch）。全部经 [GitCommandRunner] 执行，
/// 非零退出抛 [GitException]；调用方（GitGraphCubit）负责刷新与错误呈现。
class GitHistoryActions {
  GitHistoryActions({GitCommandRunner? runner})
    : _runner = runner ?? LocalGitCommandRunner();

  factory GitHistoryActions.forContext(RuntimeContext ctx) =>
      GitHistoryActions(runner: gitCommandRunnerForContext(ctx));

  final GitCommandRunner _runner;

  Future<void> _run(String dir, List<String> args) async {
    final result = await _runner.runInDirectory(dir, args);
    if (result.exitCode != 0) {
      final detail = result.stderr.trim().isEmpty
          ? result.stdout.trim()
          : result.stderr.trim();
      appLogger.d('[GitActions] ${args.join(' ')} exit ${result.exitCode}: $detail');
      throw GitException(detail.isEmpty ? 'git ${args.first} failed' : detail);
    }
  }

  Future<void> createBranchAt(
    String dir,
    String name, {
    required String startPoint,
  }) =>
      _run(dir, ['branch', name, startPoint]);

  Future<void> renameBranch(String dir, String oldName, String newName) =>
      _run(dir, ['branch', '-m', oldName, newName]);

  Future<void> deleteBranch(String dir, String name, {bool force = false}) =>
      _run(dir, ['branch', force ? '-D' : '-d', name]);

  Future<void> checkoutBranch(String dir, String name) =>
      _run(dir, ['checkout', name]);

  Future<void> checkoutCommit(String dir, String hash) =>
      _run(dir, ['checkout', hash]);

  Future<void> mergeIntoCurrent(String dir, String refName) =>
      _run(dir, ['merge', '--no-edit', refName]);

  /// [message] 非空创建附注标签，否则轻量标签；[at] 为空指向 HEAD。
  Future<void> createTag(
    String dir,
    String name, {
    String? at,
    String? message,
  }) =>
      message != null && message.isNotEmpty
          ? _run(dir, [
              'tag',
              '-a',
              name,
              '-m',
              message,
              if (at != null && at.isNotEmpty) at,
            ])
          : _run(dir, [
              'tag',
              name,
              if (at != null && at.isNotEmpty) at,
            ]);

  Future<void> deleteTag(String dir, String name) =>
      _run(dir, ['tag', '-d', name]);

  Future<void> pushTag(
    String dir,
    String name, {
    String remote = 'origin',
  }) =>
      _run(dir, ['push', remote, name]);

  Future<void> cherryPick(String dir, String hash) =>
      _run(dir, ['cherry-pick', hash]);

  Future<void> revert(String dir, String hash) =>
      _run(dir, ['revert', '--no-edit', hash]);

  Future<void> resetTo(
    String dir,
    String ref, {
    required GitResetMode mode,
  }) =>
      _run(dir, [
        'reset',
        switch (mode) {
          GitResetMode.soft => '--soft',
          GitResetMode.mixed => '--mixed',
          GitResetMode.hard => '--hard',
        },
        ref,
      ]);

  Future<void> stashPop(String dir, {String? ref}) => _run(dir, [
        'stash',
        'pop',
        if (ref != null && ref.isNotEmpty) ref,
      ]);

  Future<void> stashApply(String dir, {String? ref}) => _run(dir, [
        'stash',
        'apply',
        if (ref != null && ref.isNotEmpty) ref,
      ]);

  Future<void> stashDrop(String dir, {String? ref}) => _run(dir, [
        'stash',
        'drop',
        if (ref != null && ref.isNotEmpty) ref,
      ]);

  Future<void> fetchAll(String dir) =>
      _run(dir, ['fetch', '--all', '--prune']);
}
