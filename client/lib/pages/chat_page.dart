import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/team_cubit.dart';
import '../models/team_config.dart';
import 'chat/chat_page_shell.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({
    required this.cwd,
    this.sessionId,
    this.isPersonalProject = false,
    this.projectId,
    this.sessionTeamFilter = '',
    super.key,
  });

  final String? sessionId;

  /// Working directory the file tree / git tools operate on, supplied by the
  /// caller (e.g. project path on the v2 project page). [ChatPage] never
  /// derives it from session state.
  final String cwd;

  /// When true, the embedded workbench runs without a selected [TeamConfig].
  final bool isPersonalProject;

  /// Owning project id; scopes the workspace terminal + right-tools selection.
  /// Null on chat routes without a project context.
  final String? projectId;

  /// Filters sessions to this team id (empty string = personal/simple mode).
  final String sessionTeamFilter;

  @override
  Widget build(BuildContext context) {
    if (isPersonalProject) {
      return _PersonalChatPage(
        cwd: cwd,
        sessionId: sessionId,
        projectId: projectId,
        sessionTeamFilter: sessionTeamFilter,
      );
    }
    return _TeamChatPage(
      cwd: cwd,
      sessionId: sessionId,
      projectId: projectId,
      sessionTeamFilter: sessionTeamFilter,
    );
  }
}

class _PersonalChatPage extends StatelessWidget {
  const _PersonalChatPage({
    required this.cwd,
    this.sessionId,
    this.projectId,
    required this.sessionTeamFilter,
  });

  final String cwd;
  final String? sessionId;
  final String? projectId;
  final String sessionTeamFilter;

  @override
  Widget build(BuildContext context) {
    return ChatPageShell(
      cwd: cwd,
      sessionId: sessionId,
      isPersonalProject: true,
      projectId: projectId,
      team: null,
      sessionTeamFilter: sessionTeamFilter,
    );
  }
}

class _TeamChatPage extends StatelessWidget {
  const _TeamChatPage({
    required this.cwd,
    this.sessionId,
    this.projectId,
    required this.sessionTeamFilter,
  });

  final String cwd;
  final String? sessionId;
  final String? projectId;
  final String sessionTeamFilter;

  @override
  Widget build(BuildContext context) {
    final team = context.select<TeamCubit, TeamConfig?>(
      (c) => c.state.selectedTeam,
    );

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ChatPageShell(
      cwd: cwd,
      sessionId: sessionId,
      isPersonalProject: false,
      projectId: projectId,
      team: team,
      sessionTeamFilter: sessionTeamFilter,
    );
  }
}
