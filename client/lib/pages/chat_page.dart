import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/identity_cubit.dart';
import '../models/team_config.dart';
import 'chat/chat_page_shell.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({
    required this.cwd,
    this.sessionId,
    this.isPersonalWorkspace = false,
    this.workspaceId,
    super.key,
  });

  final String? sessionId;

  /// Working directory the file tree / git tools operate on, supplied by the
  /// caller (e.g. workspace path on the v2 workspace page). [ChatPage] never
  /// derives it from session state.
  final String cwd;

  /// When true, the embedded workbench runs without a selected [TeamIdentity].
  final bool isPersonalWorkspace;

  /// Owning workspace id; scopes the workspace terminal + right-tools selection.
  /// Null on chat routes without a workspace context.
  final String? workspaceId;

  @override
  Widget build(BuildContext context) {
    if (isPersonalWorkspace) {
      return _PersonalChatPage(
        cwd: cwd,
        sessionId: sessionId,
        workspaceId: workspaceId,
      );
    }
    return _TeamChatPage(
      cwd: cwd,
      sessionId: sessionId,
      workspaceId: workspaceId,
    );
  }
}

class _PersonalChatPage extends StatelessWidget {
  const _PersonalChatPage({
    required this.cwd,
    this.sessionId,
    this.workspaceId,
  });

  final String cwd;
  final String? sessionId;
  final String? workspaceId;

  @override
  Widget build(BuildContext context) {
    return ChatPageShell(
      cwd: cwd,
      sessionId: sessionId,
      isPersonalWorkspace: true,
      workspaceId: workspaceId,
      team: null,
    );
  }
}

class _TeamChatPage extends StatelessWidget {
  const _TeamChatPage({
    required this.cwd,
    this.sessionId,
    this.workspaceId,
  });

  final String cwd;
  final String? sessionId;
  final String? workspaceId;

  @override
  Widget build(BuildContext context) {
    final team = context.select<IdentityCubit, TeamIdentity?>(
      (c) => c.state.selectedTeam,
    );

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ChatPageShell(
      cwd: cwd,
      sessionId: sessionId,
      isPersonalWorkspace: false,
      workspaceId: workspaceId,
      team: team,
    );
  }
}
