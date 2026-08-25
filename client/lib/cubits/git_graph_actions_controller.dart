import '../models/git_graph.dart';
import '../services/git/git_history_actions.dart';
import '../services/git/git_service.dart' show GitException;
import '../utils/logging/logger.dart';
import 'git_graph_cubit.dart';

/// Git Graph 面板的写操作入口。每个操作成功后触发 cubit.refresh()，
/// 失败时把 [GitException.message] 写入状态并返回 false（UI 弹提示）。
class GitGraphActionsController {
  GitGraphActionsController({required this.cubit});

  final GitGraphCubit cubit;

  // 本控制器是 cubit 写操作入口的宿主，属测试缝的合法消费方。
  // ignore: invalid_use_of_visible_for_testing_member
  GitHistoryActions get _actions => cubit.actions;
  String get _dir => cubit.state.repoRoot;

  Future<bool> createBranch(String name, {required String atHash}) =>
      _run(() => _actions.createBranchAt(_dir, name, startPoint: atHash));

  Future<bool> renameBranch(String oldName, String newName) =>
      _run(() => _actions.renameBranch(_dir, oldName, newName));

  Future<bool> deleteBranch(String name, {bool force = false}) =>
      _run(() => _actions.deleteBranch(_dir, name, force: force));

  Future<bool> checkoutBranch(String name) =>
      _run(() => _actions.checkoutBranch(_dir, name));

  Future<bool> checkoutCommit(String hash) =>
      _run(() => _actions.checkoutCommit(_dir, hash));

  Future<bool> mergeIntoCurrent(String refName) =>
      _run(() => _actions.mergeIntoCurrent(_dir, refName));

  Future<bool> createTag(String name, {String? at, String? message}) =>
      _run(() => _actions.createTag(_dir, name, at: at, message: message));

  Future<bool> deleteTag(String name) =>
      _run(() => _actions.deleteTag(_dir, name));

  Future<bool> pushTag(String name) => _run(() => _actions.pushTag(_dir, name));

  Future<bool> cherryPick(String hash) =>
      _run(() => _actions.cherryPick(_dir, hash));

  Future<bool> revert(String hash) => _run(() => _actions.revert(_dir, hash));

  /// [ref] 为目标提交或分支名；hard 由确认对话框把关后才进入这里。
  Future<bool> resetTo(String ref, {required GitResetMode mode}) =>
      _run(() => _actions.resetTo(_dir, ref, mode: mode));

  Future<bool> stashPop({String? ref}) =>
      _run(() => _actions.stashPop(_dir, ref: ref));

  Future<bool> stashApply({String? ref}) =>
      _run(() => _actions.stashApply(_dir, ref: ref));

  Future<bool> stashDrop({String? ref}) =>
      _run(() => _actions.stashDrop(_dir, ref: ref));

  Future<bool> fetchAll() => _run(() => _actions.fetchAll(_dir));

  Future<bool> pull() =>
      // ignore: invalid_use_of_visible_for_testing_member
      _run(() => cubit.gitService.pull(_dir));
  Future<bool> push() =>
      // ignore: invalid_use_of_visible_for_testing_member
      _run(() => cubit.gitService.push(_dir));

  Future<bool> _run(Future<void> Function() action) async {
    try {
      await action();
      await cubit.refresh();
      return true;
    } on GitException catch (e) {
      appLogger.e('[GitGraph] action failed: ${e.message}');
      cubit.surfaceError(e.message);
      await cubit.refresh(); // 失败也可能部分生效（如冲突），刷新对齐真实状态
      return false;
    }
  }
}
