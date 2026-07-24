import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/resource_manager_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../services/resource_manager/process_metrics_service.dart';
import '../../services/resource_manager/pty_process_registry.dart';
import '../../services/resource_manager/resource_binding.dart';
import '../../services/resource_manager/resource_binding_adapter.dart';
import '../../services/resource_manager/resource_manager_lifecycle.dart';
import '../../services/resource_manager/resource_tree_merge.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
import '../../services/terminal/workspace_terminal_run_service.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/workspace_status_bar/resource_usage_status_item.dart';
import '../../widgets/workspace_status_bar/workspace_status_bar.dart';
import 'home_workspace_tab_scope.dart';

/// App-global Resource Manager: cubit, bindings across all workspaces, status bar.
class GlobalResourceManagerHost extends StatefulWidget {
  const GlobalResourceManagerHost({required this.child, super.key});

  final Widget child;

  @override
  State<GlobalResourceManagerHost> createState() =>
      _GlobalResourceManagerHostState();
}

class _GlobalResourceManagerHostState extends State<GlobalResourceManagerHost> {
  late final ResourceManagerCubit _cubit;
  StreamSubscription<ChatState>? _chatSub;
  final Map<String, WorkspaceTerminalGroup> _groups = {};
  final Map<String, VoidCallback> _groupListeners = {};
  String? _lastChatBindingsSignature;
  var _metricsPollingStarted = false;

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
    _bindChatListener();
    _syncTerminalGroupListeners();
    if (!_metricsPollingStarted) {
      _metricsPollingStarted = true;
      unawaited(_cubit.ensureMetricsPolling());
    }
  }

  @override
  void dispose() {
    unawaited(_chatSub?.cancel());
    _chatSub = null;
    _detachAllGroupListeners();
    unawaited(_cubit.close());
    super.dispose();
  }

  void _bindChatListener() {
    final chat = context.read<ChatCubit>();
    if (_chatSub != null) return;
    _lastChatBindingsSignature = _chatBindingsSignature(chat);
    _chatSub = chat.stream.listen((_) {
      final next = _chatBindingsSignature(chat);
      if (next == _lastChatBindingsSignature) return;
      _lastChatBindingsSignature = next;
      _syncTerminalGroupListeners();
      _refreshBindings();
    });
    _syncTerminalGroupListeners();
    _refreshBindings();
  }

  /// Cheap fingerprint of shell inventory ChatCubit owns (ignores transcript /
  /// agent-status noise that should not refresh Resource Manager).
  String _chatBindingsSignature(ChatCubit chat) {
    final buf = StringBuffer();
    for (final w in chat.state.workspaces) {
      buf.write(w.workspaceId);
      buf.write('\x1f');
      buf.write(w.effectiveDisplay);
      buf.write('\n');
    }
    for (final tab in chat.tabStore.openTabs) {
      buf.write(tab.workspaceId);
      buf.write('\x1f');
      buf.write(tab.info.id);
      buf.write('\x1f');
      buf.write(tab.info.title);
      for (final e in tab.memberShells.entries) {
        buf.write('\x1f');
        buf.write(e.key);
        buf.write(':');
        buf.write(e.value.pid ?? 0);
        buf.write(e.value.isConnected || e.value.isRunning ? '1' : '0');
      }
      buf.write('\n');
    }
    return buf.toString();
  }

  void _syncTerminalGroupListeners() {
    if (!mounted) return;
    final registry = context.read<WorkspaceTerminalRegistry>();
    final chat = context.read<ChatCubit>();
    final ids = <String>{
      for (final w in chat.state.workspaces) w.workspaceId,
      for (final t in chat.tabStore.openTabs)
        if (t.workspaceId.isNotEmpty) t.workspaceId,
    };
    for (final id in ids.toList()) {
      if (_groups.containsKey(id)) continue;
      final group = registry.groupFor(id);
      void listener() => _refreshBindings();
      group.addListener(listener);
      _groups[id] = group;
      _groupListeners[id] = listener;
    }
    final stale = _groups.keys.where((id) => !ids.contains(id)).toList();
    for (final id in stale) {
      final group = _groups.remove(id);
      final listener = _groupListeners.remove(id);
      if (group != null && listener != null) {
        group.removeListener(listener);
      }
    }
  }

  void _detachAllGroupListeners() {
    for (final entry in _groups.entries) {
      final listener = _groupListeners[entry.key];
      if (listener != null) entry.value.removeListener(listener);
    }
    _groups.clear();
    _groupListeners.clear();
  }

  List<ResourceBinding> _readBindings() {
    if (!mounted) return const [];
    final chat = context.read<ChatCubit>();
    final registry = context.read<WorkspaceTerminalRegistry>();
    final emptyTitle = context.l10n.defaultNewChatSessionTitle;
    final profiles = context.read<LaunchProfileCubit>();

    return collectLiveResourceBindingsAllWorkspaces(
      workspaces: chat.state.workspaces,
      allTabs: chat.tabStore.openTabs,
      terminalRegistry: registry,
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
    final workspaceId = leaf.workspaceId?.trim() ?? '';
    if (workspaceId.isEmpty) return;

    HomeTabScope.openInTab(context, workspaceId, activate: true);

    final workbench = context.read<WorkbenchCubit>();
    final chat = context.read<ChatCubit>();

    switch (leaf.kind) {
      case ResourceBindingKind.chatMember:
        final sessionId = leaf.sessionId?.trim() ?? '';
        final memberId = leaf.memberId?.trim() ?? '';
        if (sessionId.isEmpty) return;
        workbench.ensureTab(
          workspaceId,
          WorkbenchTabId.session(sessionId),
          preview: false,
        );
        final tabs = chat.tabStore.tabsForWorkspace(workspaceId);
        final index = tabs.indexWhere((t) => t.info.id == sessionId);
        if (index >= 0) chat.selectTab(index);
        if (memberId.isNotEmpty) chat.selectMember(memberId);
        // Keep whatever chat/terminal surface the session already shows
        // (do not force terminal like a process-manager jump).
      case ResourceBindingKind.workspaceShell:
        final entryId = leaf.shellEntryId?.trim() ?? '';
        if (entryId.isEmpty) return;
        workbench.ensureTab(
          workspaceId,
          WorkbenchTabId.shell(entryId),
        );
        context
            .read<WorkspaceTerminalRegistry>()
            .groupFor(workspaceId)
            .activeId = entryId;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ResourceManagerCubit>.value(
      value: _cubit,
      child: ResourceManagerNavigateScope(
        onNavigateLeaf: _navigateLeaf,
        child: Column(
          children: [
            Expanded(child: widget.child),
            WorkspaceStatusBar(
              items: [ResourceUsageStatusItem()],
            ),
          ],
        ),
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
