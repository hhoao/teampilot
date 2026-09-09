import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../widgets/app_toast/app_toast.dart';

import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
import '../../services/terminal/workspace_terminal_title_resolver.dart';
import '../../services/workspace/workspace_pane_policy.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/ui/app_keys.dart';
import '../../utils/workspace/workspace_active_context.dart';
import '../../widgets/workspace_terminal_panel.dart';
import '../../widgets/workbench/workbench_split_layout_view.dart';
import '../../widgets/workbench/workbench_tab_drag.dart';
import '../workbench/workbench_group_host.dart';
import '../workspace_shell/workspace_shell_tabs.dart';
import 'chat_page_structural_signal.dart';
import 'team_config_incomplete_dialog.dart';

class ChatPageShell extends StatelessWidget {
  const ChatPageShell({
    required this.cwd,
    required this.workspaceId,
    required this.tabScopeId,
    this.routeActive = true,
    this.additionalPaths = const [],
    this.sessionId,
    this.holdHandle,
    super.key,
  });

  final String cwd;

  /// Extra workspace folders for the multi-root file tree / source control.
  final List<String> additionalPaths;
  final String? sessionId;
  final String workspaceId;
  final String tabScopeId;
  final bool routeActive;
  final WorkspaceTerminalHoldHandle? holdHandle;

  @override
  Widget build(BuildContext context) {
    // Center-only: geometry (sidebar / right tools / bottom terminal) is owned
    // by `WorkspaceIdeShell` above this widget. `ChatPageShell` now renders just
    // the center workbench column: a recursive split view hosting one
    // [WorkbenchGroupHost] (its own WorkspaceShell tab bar + body) per
    // editor-group leaf of the center layout.
    return _chatLaunchListener(
      context,
      _ChatWorkspaceShell(
        cwd: cwd,
        additionalPaths: additionalPaths,
        sessionId: sessionId,
        workspaceId: workspaceId,
        tabScopeId: tabScopeId,
        routeActive: routeActive,
        holdHandle: holdHandle,
      ),
    );
  }
}

class _ChatWorkspaceShell extends StatelessWidget {
  const _ChatWorkspaceShell({
    required this.cwd,
    required this.additionalPaths,
    required this.sessionId,
    required this.workspaceId,
    required this.tabScopeId,
    required this.routeActive,
    this.holdHandle,
  });

  final String cwd;

  /// Extra workspace folders for the multi-root file tree / source control.
  final List<String> additionalPaths;
  final String? sessionId;
  final String workspaceId;
  final String tabScopeId;
  final bool routeActive;
  final WorkspaceTerminalHoldHandle? holdHandle;

  bool _scopedTabBuildWhen(
    WorkbenchCubit workbench,
    ChatCubit cubit,
    ChatState previous,
    ChatState next,
  ) {
    if (!routeActive) return false;
    final prevSignal = chatPageStructuralSignal(
      state: previous,
      tabStore: cubit.tabStore,
      workbench: workbench,
      tabScopeId: tabScopeId,
    );
    final nextSignal = chatPageStructuralSignal(
      state: next,
      tabStore: cubit.tabStore,
      workbench: workbench,
      tabScopeId: tabScopeId,
    );
    return prevSignal != nextSignal;
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ChatCubit>();
    final workbench = context.read<WorkbenchCubit>();
    return BlocBuilder<ChatCubit, ChatState>(
      buildWhen: (previous, next) =>
          _scopedTabBuildWhen(workbench, cubit, previous, next),
      builder: (context, state) {
        final workspace = state.workspaces
            .where((w) => w.workspaceId == workspaceId)
            .firstOrNull;
        if (workspace == null) {
          return const SizedBox.shrink();
        }
        final runtimeTabs = _runtimeTabsForScope(cubit, tabScopeId);
        final shellGroup = context
            .read<WorkspaceTerminalRegistry>()
            .groupFor(tabScopeId);
        final shellEntries = shellGroup.entries;
        final shellTitles = {
          for (final entry in shellEntries)
            entry.id: WorkspaceTerminalTitleResolver.tabTitle(
              entry: entry,
              siblings: shellEntries,
              baseLabel: entry.titleLabel.isEmpty ? '…' : entry.titleLabel,
            ),
        };

        return BlocBuilder<WorkbenchCubit, WorkbenchState>(
          buildWhen: (prev, next) =>
              prev.bar(workspaceId) != next.bar(workspaceId),
          builder: (context, workbenchState) {
            final editorBucket = context
                .select<EditorCubit, WorkspaceEditorBucket>(
                  (c) => c.state.bucket(workspaceId),
                );
            final showTabBar = context.select<LayoutCubit, bool>(
              (c) => c.state.preferences.sessionTabBarVisible,
            );
            final layout = workbench.centerLayout(workspaceId);
            final splitEnabled =
                MediaQuery.widthOf(context) >=
                WorkspacePanePolicy.narrowBreakpointWidth;

            // Team chrome actions resolve from the focused group's context.
            // Single group → rendered once above the split view; multi-group →
            // duplicated into each group host's action row (VSCode-style).
            final active = WorkspaceActiveContext.resolve(
              workbench: workbench,
              chat: cubit,
              launchProfiles: context.read<LaunchProfileCubit>(),
              tabScopeId: tabScopeId,
            );
            final singleGroup = layout.groups.length == 1;
            final chatActions =
                active.isPersonal || active.team == null
                ? const <Widget>[]
                : _chatActions(context, active.team!);

            final splitView = WorkbenchSplitLayoutView(
              layout: layout,
              holdHandle: holdHandle,
              splitEnabled: splitEnabled,
              onResizeCommit: (commits) => workbench
                  .commitSplitResizeBatch(workspaceId, commits: commits),
              onGroupFocused: routeActive
                  ? (id) => workbench.focusGroup(workspaceId, id)
                  : null,
              // Read the focused group inside the callback — the build-time
              // layout would be a stale closure after any focus change.
              onDividerDoubleTap: () => workbench.toggleMaximizeGroup(
                workspaceId,
                workbench.centerFocusedGroupId(workspaceId),
              ),
              groupBuilder: (context, groupId, strip) => KeyedSubtree(
                key: ValueKey('workbench-group-host-$groupId'),
                child: WorkbenchGroupHost(
                  workspace: workspace,
                  workspaceId: workspaceId,
                  tabScopeId: tabScopeId,
                  cwd: cwd,
                  additionalPaths: additionalPaths,
                  groupId: groupId,
                  strip: strip,
                  focused:
                      layout.focusedGroupId == groupId ||
                      layout.maximizedGroupId == groupId,
                  routeActive: routeActive,
                  chatState: state,
                  runtimeTabs: runtimeTabs,
                  editorBucket: editorBucket,
                  shellTitles: shellTitles,
                  showTabBar: showTabBar,
                  splitEnabled: splitEnabled,
                  holdHandle: holdHandle,
                  sessionId: sessionId,
                  actions: singleGroup ? const [] : chatActions,
                ),
              ),
            );

            return WorkbenchTabDragHost(
              child: singleGroup && chatActions.isNotEmpty
                  ? Column(
                      children: [
                        WorkspaceShellActionsBar(actions: chatActions),
                        Expanded(child: splitView),
                      ],
                    )
                  : KeyedSubtree(
                      key: const ValueKey('center-split-view-root'),
                      child: splitView,
                    ),
            );
          },
        );
      },
    );
  }

  List<Widget> _chatActions(BuildContext context, TeamProfile team) {
    return [
      IconButton.filledTonal(
        key: AppKeys.openTeamLeadButton,
        tooltip: 'Open team-lead',
        onPressed: throttledOnPressed('chat_open_team_lead', () {
          final lead = team.members.where((m) => m.id == 'team-lead');
          if (lead.isEmpty) {
            context.read<ChatCubit>().addSystemMessage(
              'FlashskyAI requires a member named team-lead.',
            );
            return;
          }
          unawaited(
            context.read<ChatCubit>().openMemberTab(
              team,
              lead.first,
              workspaceCwd: cwd,
            ),
          );
        }),
        icon: Icon(Icons.person_outline),
      ),
      IconButton.filled(
        key: AppKeys.openTeamButton,
        tooltip: 'Open Team',
        onPressed: throttledAsync(
          'chat_launch_all_members',
          () => context.read<ChatCubit>().launchAllMembers(
            team,
            workspaceCwd: cwd,
          ),
        ),
        icon: Icon(Icons.groups_outlined),
      ),
    ];
  }
}

List<ChatTab> _runtimeTabsForScope(ChatCubit cubit, String tabScopeId) {
  final bucket = cubit.tabStore.tabsForWorkspace(tabScopeId);
  if (bucket.isNotEmpty) return bucket;
  if (cubit.tabStore.activeWorkspaceId == tabScopeId) {
    return cubit.tabStore.activeTabs;
  }
  return bucket;
}

Widget _chatLaunchListener(BuildContext context, Widget child) {
  return BlocListener<ChatCubit, ChatState>(
    listenWhen: (previous, next) =>
        previous.snackbarMessage != next.snackbarMessage &&
        next.snackbarMessage != null,
    listener: (listenerContext, state) {
      if (!listenerContext.mounted) return;
      final code = state.snackbarMessage;
      if (code == null) return;
      final message = code == 'claude_credentials_missing'
          ? listenerContext.l10n.claudeLaunchCredentialsMissingWarning
          : code;
      AppToast.show(
        listenerContext,
        message: message,
        variant: code == 'claude_credentials_missing'
            ? TpToastVariant.warning
            : TpToastVariant.info,
      );
      listenerContext.read<ChatCubit>().clearSnackbarMessage();
    },
    child: BlocListener<EditorCubit, EditorState>(
      listenWhen: (previous, next) =>
          previous.snackbarMessage != next.snackbarMessage &&
          next.snackbarMessage != null &&
          !isDiffEditorSurfaceSnackbar(next.snackbarMessage!),
      listener: (listenerContext, state) {
        if (!listenerContext.mounted) return;
        final code = state.snackbarMessage;
        if (code == null) return;
        final message = listenerContext.l10n.editorSnackbarMessage(code);
        AppToast.show(listenerContext, message: message);
        listenerContext.read<EditorCubit>().clearSnackbarMessage();
      },
      child: BlocListener<ChatCubit, ChatState>(
        listenWhen: (previous, next) =>
            previous.teamConfigValidation != next.teamConfigValidation &&
            next.teamConfigValidation != null,
        listener: (listenerContext, state) {
          final validation = state.teamConfigValidation;
          listenerContext.read<ChatCubit>().clearTeamConfigValidation();
          if (validation == null || !listenerContext.mounted) return;
          unawaited(
            showTeamConfigIncompleteDialog(listenerContext, validation),
          );
        },
        child: child,
      ),
    ),
  );
}
