import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/launch_profile_cubit.dart';
import '../models/team_config.dart';
import 'chat/chat_page_shell.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({
    required this.cwd,
    required this.workspaceId,
    this.tabScopeId,
    this.profileId,
    this.additionalPaths = const [],
    this.sessionId,
    this.isPersonalWorkspace = false,
    super.key,
  });

  final String? sessionId;

  /// Working directory the file tree / git tools operate on, supplied by the
  /// caller (e.g. workspace path on the v2 workspace page). [ChatPage] never
  /// derives it from session state.
  final String cwd;

  /// Extra workspace folders for the multi-root file tree / source control.
  final List<String> additionalPaths;

  /// When true, the embedded workbench runs without a selected [TeamProfile].
  final bool isPersonalWorkspace;

  /// Owning workspace id for persisted sessions and the file tree.
  final String workspaceId;

  /// Scopes workspace terminals and right-tools selection; defaults to [workspaceId].
  final String? tabScopeId;

  /// Launch identity for team resolution.
  final String? profileId;

  String get _tabScopeId => tabScopeId ?? workspaceId;

  @override
  Widget build(BuildContext context) {
    if (isPersonalWorkspace) {
      return _PersonalChatPage(
        cwd: cwd,
        additionalPaths: additionalPaths,
        sessionId: sessionId,
        workspaceId: workspaceId,
        tabScopeId: _tabScopeId,
      );
    }
    return _TeamChatPage(
      cwd: cwd,
      additionalPaths: additionalPaths,
      sessionId: sessionId,
      workspaceId: workspaceId,
      tabScopeId: _tabScopeId,
      profileId: profileId,
    );
  }
}

class _PersonalChatPage extends StatelessWidget {
  const _PersonalChatPage({
    required this.cwd,
    required this.workspaceId,
    required this.tabScopeId,
    this.additionalPaths = const [],
    this.sessionId,
  });

  final String cwd;
  final String workspaceId;
  final String tabScopeId;
  final List<String> additionalPaths;
  final String? sessionId;

  @override
  Widget build(BuildContext context) {
    return ChatPageShell(
      cwd: cwd,
      additionalPaths: additionalPaths,
      sessionId: sessionId,
      isPersonalWorkspace: true,
      workspaceId: workspaceId,
      tabScopeId: tabScopeId,
      team: null,
    );
  }
}

class _TeamChatPage extends StatelessWidget {
  const _TeamChatPage({
    required this.cwd,
    required this.workspaceId,
    required this.tabScopeId,
    this.profileId,
    this.additionalPaths = const [],
    this.sessionId,
  });

  final String cwd;
  final String workspaceId;
  final String tabScopeId;
  final String? profileId;
  final List<String> additionalPaths;
  final String? sessionId;

  TeamProfile? _team(BuildContext context) {
    final id = profileId?.trim() ?? '';
    if (id.isNotEmpty) {
      final profile = context.read<LaunchProfileCubit>().byId(id);
      if (profile is TeamProfile) return profile;
    }
    return context.select<LaunchProfileCubit, TeamProfile?>(
      (c) => c.state.selectedTeam,
    );
  }

  @override
  Widget build(BuildContext context) {
    final team = _team(context);

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ChatPageShell(
      cwd: cwd,
      additionalPaths: additionalPaths,
      sessionId: sessionId,
      isPersonalWorkspace: false,
      workspaceId: workspaceId,
      tabScopeId: tabScopeId,
      team: team,
    );
  }
}
