import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../models/app_session.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_folder.dart';
import '../../../services/git/git_command_runner.dart';
import '../../../services/git/git_worktree_service.dart';
import '../../../services/storage/runtime_context.dart';
import '../../../services/workspace/workspace_tools_scope.dart';

/// Keeps [WorkspaceToolsScopeCubit] and [WorktreeCubit]'s git runner aligned
/// with cwd, workspace folders, and the active session.
class WorkspaceToolsScopeSync extends StatefulWidget {
  const WorkspaceToolsScopeSync({
    required this.workspace,
    required this.cwd,
    required this.child,
    super.key,
  });

  final Workspace workspace;
  final String cwd;
  final Widget child;

  @override
  State<WorkspaceToolsScopeSync> createState() =>
      _WorkspaceToolsScopeSyncState();
}

class _WorkspaceToolsScopeSyncState extends State<WorkspaceToolsScopeSync> {
  String? _lastSyncKey;
  String? _lastWorktreeTargetId;

  AppSession? _activeSession(ChatState chat) {
    final activeId = chat.activeSessionId;
    if (activeId == null || activeId.isEmpty) return null;
    final workspaceId = widget.workspace.workspaceId;
    for (final session in chat.sessions) {
      if (session.sessionId == activeId &&
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
    final session = _activeSession(chat.state);
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
    // Git worktree list is per storage target; session cwd selection is handled
    // separately via WorktreeCubit.syncCurrentForSessionPath on tab open.
    if (_lastWorktreeTargetId != tools.targetId) {
      _lastWorktreeTargetId = tools.targetId;
      context.read<WorktreeCubit>().bindWorktreeService(
        _worktreeServiceFor(context, tools.context),
        repoPath: widget.workspace.firstFolderPath,
        preferCurrentPath: session?.firstFolderPath,
      );
    }
  }

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

  bool _chatAffectsToolsPlane(ChatState prev, ChatState next) {
    if (prev.activeSessionId != next.activeSessionId) return true;
    return _activeSession(prev)?.folders != _activeSession(next)?.folders;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_sync(context.read<ChatCubit>()));
    });
  }

  @override
  void didUpdateWidget(covariant WorkspaceToolsScopeSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    final cwdChanged = widget.cwd != oldWidget.cwd;
    final workspaceChanged = widget.workspace != oldWidget.workspace;
    if (cwdChanged || workspaceChanged) {
      _lastSyncKey = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_sync(context.read<ChatCubit>()));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ChatCubit, ChatState>(
      listenWhen: _chatAffectsToolsPlane,
      listener: (context, _) => unawaited(_sync(context.read<ChatCubit>())),
      child: BlocBuilder<WorkspaceToolsScopeCubit, WorkspaceToolsScopeState>(
        builder: (context, scopeState) => WorkspaceToolsScope(
          state: scopeState,
          child: widget.child,
        ),
      ),
    );
  }
}
