import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/workbench/workbench_cubit.dart';
import '../widgets/workspace_terminal_panel.dart';
import 'chat/chat_page_shell.dart';
import 'home_workspace/workspace/workspace_route_active_scope.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({
    required this.cwd,
    required this.workspaceId,
    this.tabScopeId,
    this.additionalPaths = const [],
    this.sessionId,
    this.holdHandle,
    super.key,
  });

  final String? sessionId;

  /// Working directory the file tree / git tools operate on, supplied by the
  /// caller (e.g. workspace path on the v2 workspace page). [ChatPage] never
  /// derives it from session state.
  final String cwd;

  /// Extra workspace folders for the multi-root file tree / source control.
  final List<String> additionalPaths;

  /// Owning workspace id for persisted sessions and the file tree.
  final String workspaceId;

  /// Scopes workspace terminals and right-tools selection; defaults to [workspaceId].
  final String? tabScopeId;

  final WorkspaceTerminalHoldHandle? holdHandle;

  String get _tabScopeId => tabScopeId ?? workspaceId;

  @override
  Widget build(BuildContext context) {
    // Select only activeSessionId — ChatPageShell owns its own BlocBuilder
    // with buildWhen, so this widget must not rebuild on every ChatState emit.
    final activeSessionId = context.select<WorkbenchCubit, String?>(
      (w) => w.centerActiveId(_tabScopeId)?.sessionId,
    );

    final routeActive = WorkspaceRouteActiveScope.routeActiveOf(context);
    return ChatPageShell(
      cwd: cwd,
      additionalPaths: additionalPaths,
      sessionId: sessionId ?? activeSessionId,
      workspaceId: workspaceId,
      tabScopeId: _tabScopeId,
      routeActive: routeActive,
      holdHandle: holdHandle,
    );
  }
}
