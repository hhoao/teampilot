import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

import '../../../models/workspace.dart';
import '../../../models/app_session.dart';
import '../../../models/session_activity.dart';
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
    this.provisionVersion = 0,
    this.podViewVersion = 0,
    this.memberSelectionVersion = 0,
    this.snackbarMessage,
    this.sessionLaunchError,
    this.teamConfigValidation,
    this.sessionActivities = const {},
  });

  final List<Workspace> workspaces;
  final List<AppSession> sessions;
  final List<Workspace> visibleWorkspaces;
  final List<AppSession> visibleSessions;

  /// Bumped on every remote provision progress update so the remote-provision UI
  /// (ChatWorkbench) rebuilds without a catch-all state version.
  final int provisionVersion;

  /// Bumped when [SessionPod.setView] changes the workbench view (chat↔terminal).
  /// Widgets that read [ChatTab.workbenchView] (or the equivalent pod view) use
  /// this to stay in sync without depending on the removed stateVersion.
  final int podViewVersion;

  /// Bumped when [ChatCubit.selectMember] / [ChatCubit.syncTeam] rewrite the
  /// active tab's selected member. Widgets that render the member highlight
  /// from [ChatTab.selectedMemberId] (right-tools members panel) use this to
  /// rebuild without a catch-all state version.
  final int memberSelectionVersion;

  final String? snackbarMessage;

  /// Launch error when connect fails before a tab exists (empty workbench).
  final String? sessionLaunchError;

  /// Set when a team session opens with incomplete provider/model/CLI config;
  /// the workbench surfaces a "go configure" dialog. Launch is not blocked.
  final TeamConfigValidation? teamConfigValidation;

  /// Per-open-session activity snapshot (reasons + turn disposition).
  /// Missing key means idle with no turn. Spinner consumers use [isBusy];
  /// idle-notify uses [SessionActivity.isReadyToChat].
  final Map<String, SessionActivity> sessionActivities;

  Set<String> get busySessionIds => {
    for (final e in sessionActivities.entries)
      if (e.value.isBusy) e.key,
  };

  bool isSessionBusy(String id) => sessionActivities[id]?.isBusy ?? false;

  ChatState copyWith({
    List<Workspace>? workspaces,
    List<AppSession>? sessions,
    List<Workspace>? visibleWorkspaces,
    List<AppSession>? visibleSessions,
    int? provisionVersion,
    int? podViewVersion,
    int? memberSelectionVersion,
    String? snackbarMessage,
    bool clearSnackbarMessage = false,
    String? sessionLaunchError,
    bool clearSessionLaunchError = false,
    TeamConfigValidation? teamConfigValidation,
    bool clearTeamConfigValidation = false,
    Map<String, SessionActivity>? sessionActivities,
  }) {
    return ChatState(
      workspaces: workspaces ?? this.workspaces,
      sessions: sessions ?? this.sessions,
      visibleWorkspaces: visibleWorkspaces ?? this.visibleWorkspaces,
      visibleSessions: visibleSessions ?? this.visibleSessions,
      provisionVersion: provisionVersion ?? this.provisionVersion,
      podViewVersion: podViewVersion ?? this.podViewVersion,
      memberSelectionVersion:
          memberSelectionVersion ?? this.memberSelectionVersion,
      snackbarMessage: clearSnackbarMessage
          ? null
          : (snackbarMessage ?? this.snackbarMessage),
      sessionLaunchError: clearSessionLaunchError
          ? null
          : (sessionLaunchError ?? this.sessionLaunchError),
      teamConfigValidation: clearTeamConfigValidation
          ? null
          : (teamConfigValidation ?? this.teamConfigValidation),
      sessionActivities: sessionActivities ?? this.sessionActivities,
    );
  }

  @override
  List<Object?> get props => [
    workspaces,
    sessions,
    visibleWorkspaces,
    visibleSessions,
    provisionVersion,
    podViewVersion,
    memberSelectionVersion,
    snackbarMessage,
    sessionLaunchError,
    teamConfigValidation,
    sessionActivities,
  ];
}
