import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/workbench/workbench_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../models/app_session.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_folder.dart';
import '../../../services/git/git_command_runner.dart';
import '../../../services/git/git_worktree_service.dart';
import '../../../services/storage/runtime_context.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import '../../../utils/workspace/workspace_path_utils.dart';
import '../../../utils/session/workspace_tab_session_scope.dart';
import 'workspace_route_active_scope.dart';

/// Keeps [WorkspaceToolsScopeCubit] and [WorktreeCubit]'s git runner aligned
/// with cwd, workspace folders, and the active session.
class WorkspaceToolsScopeSync extends StatefulWidget {
  const WorkspaceToolsScopeSync({
    required this.workspace,
    required this.cwd,
    required this.tabScopeId,
    required this.child,
    super.key,
  });

  final Workspace workspace;
  final String cwd;
  final String tabScopeId;
  final Widget child;

  @override
  State<WorkspaceToolsScopeSync> createState() =>
      _WorkspaceToolsScopeSyncState();
}

class _WorkspaceToolsScopeSyncState extends State<WorkspaceToolsScopeSync> {
  String? _lastSyncKey;
  String? _lastWorktreeTargetId;
  String? _lastBarActiveSessionId;
  bool _wasRouteActive = false;

  bool get _routeActive => WorkspaceRouteActiveScope.routeActiveOf(context);

  AppSession? _activeSession(ChatCubit chat) {
    final sessionId = scopedActiveSessionId(
      context.read<WorkbenchCubit>(),
      widget.tabScopeId,
    );
    if (sessionId == null || sessionId.isEmpty) return null;
    final workspaceId = widget.workspace.workspaceId;
    for (final session in chat.state.sessions) {
      if (session.sessionId == sessionId &&
          session.workspaceId == workspaceId) {
        return session;
      }
    }
    return null;
  }

  String _syncKey({
    required String cwd,
    required List<String> additionalPaths,
    required List<WorkspaceFolder> workspaceFolders,
    required AppSession? session,
  }) {
    final sessionFolders = session?.folders ?? const [];
    final sessionKey = session?.sessionId ?? '';
    return '$cwd|${additionalPaths.join('\x1e')}|'
        '${workspaceFolders.map((f) => '${f.path}@${f.targetId}').join('\x1e')}|'
        '$sessionKey|'
        '${sessionFolders.map((f) => '${f.path}@${f.targetId}').join('\x1e')}';
  }

  Future<void> _sync(ChatCubit chat) async {
    if (!_routeActive) return;

    final session = _activeSession(chat);
    final key = _syncKey(
      cwd: widget.cwd,
      additionalPaths: widget.workspace.extraFolderPaths,
      workspaceFolders: widget.workspace.folders,
      session: session,
    );
    if (key == _lastSyncKey) return;
    _lastSyncKey = key;

    final scopeCubit = context.read<WorkspaceToolsScopeCubit>();
    await scopeCubit.sync(
      workspaceFolders: widget.workspace.folders,
      cwd: widget.cwd,
      additionalPaths: widget.workspace.extraFolderPaths,
      sessionFolders: session?.folders,
    );
    if (!mounted) return;

    final tools = scopeCubit.state.tools;
    if (tools == null) return;
    // Git worktree list is per storage target; bind only with the runner for
    // this tools plane (never a default local runner against a remote path).
    // Session cwd selection uses WorktreeCubit.syncCurrentForSessionPath.
    if (_lastWorktreeTargetId != tools.targetId) {
      _lastWorktreeTargetId = tools.targetId;
      final worktreeCubit = context.read<WorktreeCubit>();
      final repoPath = worktreeRepoPathForToolsTarget(
        folders: widget.workspace.folders,
        activeTargetId: tools.targetId,
        cwd: widget.cwd,
        cubitRepoPath: worktreeCubit.state.repoPath,
        sessionPrimaryPath: session?.firstFolderPath,
        fallbackRepoPath: widget.workspace.firstFolderPath,
      );
      worktreeCubit.bindWorktreeService(
        _worktreeServiceFor(context, tools.context),
        repoPath: repoPath,
        preferCurrentPath: session?.firstFolderPath ?? widget.cwd,
      );
      final prefetchPaths = [
        for (final folder in widget.workspace.folders)
          if (folder.targetId == tools.targetId) folder.path,
      ];
      if (prefetchPaths.length > 1) {
        unawaited(worktreeCubit.prefetchProjects(prefetchPaths));
      }
    }
  }

  /// Test harnesses may inject [GitCommandRunner]; production uses [toolsContext].
  GitWorktreeService _worktreeServiceFor(
    BuildContext context,
    RuntimeContext toolsContext,
  ) {
    try {
      return GitWorktreeService(runner: context.read<GitCommandRunner>());
    } on ProviderNotFoundException {
      return GitWorktreeService.forContext(toolsContext);
    }
  }

  bool _chatAffectsToolsPlane(ChatCubit chat, ChatState prev, ChatState next) {
    if (!_routeActive) return false;
    if (chat.tabStore.activeWorkspaceId != widget.tabScopeId) return false;
    final sessionId = scopedActiveSessionId(
      context.read<WorkbenchCubit>(),
      widget.tabScopeId,
    );
    if (sessionId == null || sessionId.isEmpty) return false;
    return _sessionForState(prev, sessionId)?.folders !=
        _sessionForState(next, sessionId)?.folders;
  }

  AppSession? _sessionForState(ChatState state, String sessionId) {
    final workspaceId = widget.workspace.workspaceId;
    for (final session in state.sessions) {
      if (session.sessionId == sessionId &&
          session.workspaceId == workspaceId) {
        return session;
      }
    }
    return null;
  }

  void _scheduleSync() {
    if (!_routeActive) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_sync(context.read<ChatCubit>()));
    });
  }

  @override
  void initState() {
    super.initState();
    _scheduleSync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = _routeActive;
    if (active && !_wasRouteActive) {
      _scheduleSync();
    }
    _wasRouteActive = active;
  }

  @override
  void didUpdateWidget(covariant WorkspaceToolsScopeSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    final cwdChanged = widget.cwd != oldWidget.cwd;
    final workspaceChanged = widget.workspace != oldWidget.workspace;
    if (cwdChanged || workspaceChanged) {
      _lastSyncKey = null;
      _scheduleSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    // The bar is the single session-identity source: rebuild (and resync) when
    // the scoped center-active session changes, so the tools plane recomputes
    // on session switch without the removed ChatState mirror.
    final barActiveSessionId = context.select<WorkbenchCubit, String?>(
      (workbench) => scopedActiveSessionId(workbench, widget.tabScopeId),
    );
    if (barActiveSessionId != _lastBarActiveSessionId) {
      _lastBarActiveSessionId = barActiveSessionId;
      _scheduleSync();
    }

    final scopeChild =
        BlocBuilder<WorkspaceToolsScopeCubit, WorkspaceToolsScopeState>(
          builder: (context, scopeState) =>
              WorkspaceToolsScope(state: scopeState, child: widget.child),
        );

    if (!_routeActive) {
      return scopeChild;
    }

    return BlocListener<ChatCubit, ChatState>(
      listenWhen: (prev, next) =>
          _chatAffectsToolsPlane(context.read<ChatCubit>(), prev, next),
      listener: (context, _) => unawaited(_sync(context.read<ChatCubit>())),
      child: scopeChild,
    );
  }
}
