import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../cubits/resource_manager_cubit.dart';
import '../../../cubits/workbench/workbench_cubit.dart';
import '../../../cubits/workbench/workbench_tab.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/git_worktree.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../services/resource_manager/process_metrics_service.dart';
import '../../../services/resource_manager/pty_process_registry.dart';
import '../../../services/resource_manager/resource_binding.dart';
import '../../../services/resource_manager/resource_binding_adapter.dart';
import '../../../services/resource_manager/resource_manager_lifecycle.dart';
import '../../../services/resource_manager/resource_tree_merge.dart';
import '../../../services/terminal/workspace_terminal_registry.dart';
import '../../../services/terminal/workspace_terminal_run_service.dart';
import '../../../services/workspace/workspace_worktree_registry.dart';
import '../../../widgets/app_toast/app_toast.dart';
import 'workspace_route_active_scope.dart';

/// Owns [ResourceManagerCubit], live binding collection, kill, and navigate.
class WorkspaceResourceManagerScope extends StatefulWidget {
  const WorkspaceResourceManagerScope({
    required this.workspaceId,
    required this.child,
    super.key,
  });

  final String workspaceId;
  final Widget child;

  @override
  State<WorkspaceResourceManagerScope> createState() =>
      _WorkspaceResourceManagerScopeState();
}

class _WorkspaceResourceManagerScopeState
    extends State<WorkspaceResourceManagerScope> {
  late final ResourceManagerCubit _cubit;
  StreamSubscription<ChatState>? _chatSub;
  WorkspaceTerminalGroup? _group;
  VoidCallback? _groupListener;
  StreamSubscription<WorktreeState>? _worktreeSub;
  WorktreeCubit? _worktreeCubit;
  var _workspaceBound = false;
  var _wasRouteActive = true;

  String get _workspaceId => widget.workspaceId;

  @override
  void initState() {
    super.initState();
    _cubit = ResourceManagerCubit(
      metricsService: ProcessMetricsService(),
      registry: PtyProcessRegistry(),
      bindingsSource: _readBindings,
      killBinding: _killBinding,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeActive =
        WorkspaceRouteActiveScope.maybeOf(context)?.routeActive ?? true;
    if (!_workspaceBound || _cubit.state.workspaceId != _workspaceId) {
      _workspaceBound = true;
      _cubit.setWorkspace(_workspaceId);
    }
    if (routeActive && !_wasRouteActive) {
      _cubit.onRouteActiveChanged(true);
      _cubit.setWorkspace(_workspaceId);
    } else if (!routeActive && _wasRouteActive) {
      _cubit.onRouteActiveChanged(false);
    }
    _wasRouteActive = routeActive;
    _bindChatListener();
    _bindTerminalGroup();
    _bindWorktreeListener();
  }

  @override
  void didUpdateWidget(covariant WorkspaceResourceManagerScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId) {
      _cubit.setWorkspace(widget.workspaceId);
      _bindTerminalGroup();
      _bindWorktreeListener();
      _refreshBindings();
    }
  }

  @override
  void dispose() {
    unawaited(_chatSub?.cancel());
    _chatSub = null;
    unawaited(_worktreeSub?.cancel());
    _worktreeSub = null;
    _worktreeCubit = null;
    _detachGroupListener();
    unawaited(_cubit.close());
    super.dispose();
  }

  void _bindChatListener() {
    final chat = context.read<ChatCubit>();
    if (_chatSub != null) return;
    _chatSub = chat.stream.listen((_) => _refreshBindings());
    _refreshBindings();
  }

  void _bindTerminalGroup() {
    final group = context.read<WorkspaceTerminalRegistry>().groupFor(
      _workspaceId,
    );
    if (identical(_group, group)) return;
    _detachGroupListener();
    _group = group;
    _groupListener = _refreshBindings;
    group.addListener(_groupListener!);
  }

  void _detachGroupListener() {
    final group = _group;
    final listener = _groupListener;
    if (group != null && listener != null) {
      group.removeListener(listener);
    }
    _group = null;
    _groupListener = null;
  }

  void _bindWorktreeListener() {
    final workspace = _workspaceOrNull();
    if (workspace == null) return;
    final worktreeCubit = context.read<WorkspaceWorktreeRegistry>().cubitFor(
      workspaceId: _workspaceId,
      repoPath: workspace.firstFolderPath,
    );
    if (identical(_worktreeCubit, worktreeCubit)) return;
    unawaited(_worktreeSub?.cancel());
    _worktreeCubit = worktreeCubit;
    _worktreeSub = worktreeCubit.stream.listen((_) => _refreshBindings());
  }

  Workspace? _workspaceOrNull() {
    final workspaces = context.read<ChatCubit>().state.workspaces;
    for (final w in workspaces) {
      if (w.workspaceId == _workspaceId) return w;
    }
    return null;
  }

  List<ResourceBinding> _readBindings() {
    if (!mounted) return const [];
    final chat = context.read<ChatCubit>();
    final group = context.read<WorkspaceTerminalRegistry>().groupFor(
      _workspaceId,
    );
    final workspace = _workspaceOrNull();
    final worktrees = workspace == null
        ? const <GitWorktree>[]
        : context
            .read<WorkspaceWorktreeRegistry>()
            .cubitFor(
              workspaceId: _workspaceId,
              repoPath: workspace.firstFolderPath,
            )
            .state
            .worktrees;
    final emptyTitle = context.l10n.defaultNewChatSessionTitle;
    final profiles = context.read<LaunchProfileCubit>();

    return collectLiveResourceBindings(
      workspaceId: _workspaceId,
      tabs: chat.tabStore.tabsForWorkspace(_workspaceId),
      terminalGroup: group,
      worktrees: worktrees,
      sessionTitle: (tab) => resourceManagerSessionTitle(
        tab,
        emptyFallback: emptyTitle,
      ),
      memberName: (tab, memberId) {
        final teamId = tab.persistedSession?.sessionTeam.trim() ?? '';
        TeamProfile? team;
        if (teamId.isNotEmpty) {
          final profile = profiles.byId(teamId);
          if (profile is TeamProfile) team = profile;
        }
        return resourceManagerMemberName(
          tab: tab,
          memberId: memberId,
          team: team,
        );
      },
    );
  }

  void _refreshBindings() {
    if (!mounted || _cubit.isClosed) return;
    _cubit.syncRegistryFromBindings();
  }

  Future<void> _killBinding(String bindingKey) async {
    try {
      await killResourceManagerBinding(
        bindingKey: bindingKey,
        disconnectMemberShell: (sessionId, memberId) async {
          context.read<ChatCubit>().disconnectMemberShell(sessionId, memberId);
        },
        killWorkspaceShell: (workspaceId, entryId) async {
          final runService = context.read<WorkspaceTerminalRunService>();
          final group = context.read<WorkspaceTerminalRegistry>().groupFor(
            workspaceId,
          );
          runService.handleEntryClosed(entryId);
          group.removeEntry(entryId);
          context.read<WorkbenchCubit>().removeTab(
            workspaceId,
            WorkbenchTabId.shell(entryId),
          );
        },
      );
      _refreshBindings();
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          message: context.l10n.resourceManagerKillFailed,
          variant: TpToastVariant.error,
        );
      }
      rethrow;
    }
  }

  void _navigateLeaf(ResourceTreeLeafVm leaf) {
    final workbench = context.read<WorkbenchCubit>();
    final chat = context.read<ChatCubit>();

    switch (leaf.kind) {
      case ResourceBindingKind.chatMember:
        final sessionId = leaf.sessionId?.trim() ?? '';
        final memberId = leaf.memberId?.trim() ?? '';
        if (sessionId.isEmpty) return;
        workbench.ensureTab(
          _workspaceId,
          WorkbenchTabId.session(sessionId),
          preview: false,
        );
        final tabs = chat.tabStore.tabsForWorkspace(_workspaceId);
        final index = tabs.indexWhere((t) => t.info.id == sessionId);
        if (index >= 0) chat.selectTab(index);
        if (memberId.isNotEmpty) chat.selectMember(memberId);
        chat.setSessionWorkbenchView(
          sessionId,
          SessionWorkbenchView.terminal,
        );
      case ResourceBindingKind.workspaceShell:
        final entryId = leaf.shellEntryId?.trim() ?? '';
        if (entryId.isEmpty) return;
        workbench.ensureTab(
          _workspaceId,
          WorkbenchTabId.shell(entryId),
        );
        context
            .read<WorkspaceTerminalRegistry>()
            .groupFor(_workspaceId)
            .activeId = entryId;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ResourceManagerCubit>.value(
      value: _cubit,
      child: ResourceManagerNavigateScope(
        onNavigateLeaf: _navigateLeaf,
        child: widget.child,
      ),
    );
  }
}

/// Exposes navigate callback to descendants (status-bar item resolves at build).
class ResourceManagerNavigateScope extends InheritedWidget {
  const ResourceManagerNavigateScope({
    required this.onNavigateLeaf,
    required super.child,
    super.key,
  });

  final void Function(ResourceTreeLeafVm leaf) onNavigateLeaf;

  static void Function(ResourceTreeLeafVm leaf)? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ResourceManagerNavigateScope>()
        ?.onNavigateLeaf;
  }

  @override
  bool updateShouldNotify(ResourceManagerNavigateScope oldWidget) =>
      onNavigateLeaf != oldWidget.onNavigateLeaf;
}
