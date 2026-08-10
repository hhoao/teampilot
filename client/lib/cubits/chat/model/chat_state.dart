import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

import '../../../models/workspace.dart';
import '../../../models/app_session.dart';
import '../../../models/ssh_profile.dart';
import '../../../models/team_config.dart';
import '../../../services/team/team_config_launch_validator.dart';
import '../../../services/terminal/terminal_session.dart';

typedef TerminalSessionFactory =
    TerminalSession Function({required String executable, int scrollbackLines});

TerminalSession defaultTerminalSessionFactory({
  required String executable,
  int scrollbackLines = 10000,
}) {
  return TerminalSession(
    executable: executable,
    scrollbackLines: scrollbackLines,
  );
}

typedef PostFrameScheduler = void Function(VoidCallback callback);
typedef SshActiveProfileResolver = SshProfile? Function();
typedef SshProfileByIdResolver = SshProfile? Function(String profileId);
typedef CliExecutableResolver = String Function(CliTool cli);

class ChatState extends Equatable {
  const ChatState({
    this.workspaces = const [],
    this.sessions = const [],
    this.visibleWorkspaces = const [],
    this.visibleSessions = const [],
    this.activeSessionId,
    this.selectedMemberId = '',
    this.stateVersion = 0,
    this.snackbarMessage,
    this.sessionLaunchError,
    this.teamConfigValidation,
    this.workingSessionIds = const {},
  });

  final List<Workspace> workspaces;
  final List<AppSession> sessions;
  final List<Workspace> visibleWorkspaces;
  final List<AppSession> visibleSessions;
  final String? activeSessionId;
  final String selectedMemberId;
  final int stateVersion;
  final String? snackbarMessage;

  /// Launch error when connect fails before a tab exists (empty workbench).
  final String? sessionLaunchError;

  /// Set when a team session opens with incomplete provider/model/CLI config;
  /// the workbench surfaces a "go configure" dialog. Launch is not blocked.
  final TeamConfigValidation? teamConfigValidation;

  /// Session ids with at least one member currently in a turn (TeamBus truth).
  /// Drives the working spinner on session tabs and sidebar list items. Only
  /// open, bus-backed (mixed) sessions appear here.
  final Set<String> workingSessionIds;

  ChatState copyWith({
    List<Workspace>? workspaces,
    List<AppSession>? sessions,
    List<Workspace>? visibleWorkspaces,
    List<AppSession>? visibleSessions,
    String? activeSessionId,
    String? selectedMemberId,
    bool clearActiveSessionId = false,
    int? stateVersion,
    String? snackbarMessage,
    bool clearSnackbarMessage = false,
    String? sessionLaunchError,
    bool clearSessionLaunchError = false,
    TeamConfigValidation? teamConfigValidation,
    bool clearTeamConfigValidation = false,
    Set<String>? workingSessionIds,
  }) {
    return ChatState(
      workspaces: workspaces ?? this.workspaces,
      sessions: sessions ?? this.sessions,
      visibleWorkspaces: visibleWorkspaces ?? this.visibleWorkspaces,
      visibleSessions: visibleSessions ?? this.visibleSessions,
      activeSessionId: clearActiveSessionId
          ? null
          : (activeSessionId ?? this.activeSessionId),
      selectedMemberId: selectedMemberId ?? this.selectedMemberId,
      stateVersion: stateVersion ?? this.stateVersion,
      snackbarMessage: clearSnackbarMessage
          ? null
          : (snackbarMessage ?? this.snackbarMessage),
      sessionLaunchError: clearSessionLaunchError
          ? null
          : (sessionLaunchError ?? this.sessionLaunchError),
      teamConfigValidation: clearTeamConfigValidation
          ? null
          : (teamConfigValidation ?? this.teamConfigValidation),
      workingSessionIds: workingSessionIds ?? this.workingSessionIds,
    );
  }

  @override
  List<Object?> get props => [
    workspaces,
    sessions,
    visibleWorkspaces,
    visibleSessions,
    activeSessionId,
    selectedMemberId,
    stateVersion,
    snackbarMessage,
    sessionLaunchError,
    teamConfigValidation,
    workingSessionIds,
  ];
}
