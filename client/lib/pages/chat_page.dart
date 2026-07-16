import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/launch_profile_cubit.dart';
import '../utils/workspace/workspace_active_context.dart';
import 'chat/chat_page_shell.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({
    required this.cwd,
    required this.workspaceId,
    this.tabScopeId,
    this.additionalPaths = const [],
    this.sessionId,
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

  String get _tabScopeId => tabScopeId ?? workspaceId;

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatCubit>();
    final launchProfiles = context.watch<LaunchProfileCubit>();
    final active = WorkspaceActiveContext.resolve(
      chat: chat,
      launchProfiles: launchProfiles,
      tabScopeId: _tabScopeId,
    );

    return ChatPageShell(
      cwd: cwd,
      additionalPaths: additionalPaths,
      sessionId: sessionId ?? active.activeSessionId,
      workspaceId: workspaceId,
      tabScopeId: _tabScopeId,
    );
  }
}
