import '../../cubits/chat_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import 'workbench_shell_actions.dart';
import 'workbench_strip_nav.dart';

/// Keyboard / command navigation over the unified workbench strip
/// (session / file / diff / shell / run) for the active workspace.
class WorkbenchStripNavigator {
  WorkbenchStripNavigator({
    required WorkbenchCubit workbench,
    required ChatCubit chat,
  }) : _workbench = workbench,
       _chat = chat;

  final WorkbenchCubit _workbench;
  final ChatCubit _chat;

  void focusAt(int ordinal) {
    final workspaceId = _activeWorkspaceId;
    if (workspaceId == null) return;
    final target = workbenchTabAt(_workbench.tabOrder(workspaceId), ordinal);
    if (target == null) return;
    _select(workspaceId, target);
  }

  void next() {
    final workspaceId = _activeWorkspaceId;
    if (workspaceId == null) return;
    final bucket = _workbench.state.bucket(workspaceId);
    final target = workbenchNextTab(bucket.tabOrder, bucket.activeTabId);
    if (target == null) return;
    _select(workspaceId, target);
  }

  void previous() {
    final workspaceId = _activeWorkspaceId;
    if (workspaceId == null) return;
    final bucket = _workbench.state.bucket(workspaceId);
    final target = workbenchPrevTab(bucket.tabOrder, bucket.activeTabId);
    if (target == null) return;
    _select(workspaceId, target);
  }

  String? get _activeWorkspaceId {
    final id = _chat.tabStore.activeWorkspaceId.trim();
    return id.isEmpty ? null : id;
  }

  void _select(String workspaceId, WorkbenchTabId tab) {
    WorkbenchShellActions.selectResolved(
      workbench: _workbench,
      chat: _chat,
      workspaceId: workspaceId,
      tabScopeId: workspaceId,
      tab: tab,
    );
  }
}
