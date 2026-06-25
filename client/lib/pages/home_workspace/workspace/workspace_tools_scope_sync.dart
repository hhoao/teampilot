import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../models/app_session.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_folder.dart';
import '../../../services/git/git_worktree_service.dart';
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

  AppSession? _activeSessionForWorkspace(ChatCubit chat) {
    final activeId = chat.state.activeSessionId;
    if (activeId == null || activeId.isEmpty) return null;
    for (final session in chat.state.sessions) {
      if (session.sessionId == activeId &&
          session.workspaceId == widget.workspace.workspaceId) {
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
    final session = _activeSessionForWorkspace(chat);
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
    if (_lastWorktreeTargetId != tools.targetId) {
      _lastWorktreeTargetId = tools.targetId;
      context.read<WorktreeCubit>().bindWorktreeService(
        GitWorktreeService.forContext(tools.context),
      );
    }
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
      listenWhen: (prev, next) =>
          prev.activeSessionId != next.activeSessionId ||
          !listEquals(prev.sessions, next.sessions),
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
