import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

import '../../../models/workspace.dart';
import '../../../models/app_session.dart';
import '../../../models/ssh_profile.dart';
import '../../../models/team_config.dart';
import '../../../services/team/team_config_launch_validator.dart';
import '../../../services/terminal/terminal_session.dart';
import 'chat_tab_info.dart';

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
    this.tabs = const [],
    this.activeTabIndex = 0,
    this.workspaces = const [],
    this.sessions = const [],
    this.visibleWorkspaces = const [],
    this.visibleSessions = const [],
    this.activeSessionId,
    this.selectedMemberId = '',
    this.stateVersion = 0,
    this.snackbarMessage,
    this.sessionConnectingId,
    this.sessionLaunchError,
    this.teamConfigValidation,
    this.workingSessionIds = const {},
  });

  final List<ChatTabInfo> tabs;
  final int activeTabIndex;
  final List<Workspace> workspaces;
  final List<AppSession> sessions;
  final List<Workspace> visibleWorkspaces;
  final List<AppSession> visibleSessions;
  final String? activeSessionId;
  final String selectedMemberId;
  final int stateVersion;
  final String? snackbarMessage;

  /// Session id while prepareLaunch / terminal spawn is in progress.
  final String? sessionConnectingId;

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
    List<ChatTabInfo>? tabs,
    int? activeTabIndex,
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
    String? sessionConnectingId,
    bool clearSessionConnectingId = false,
    String? sessionLaunchError,
    bool clearSessionLaunchError = false,
    TeamConfigValidation? teamConfigValidation,
    bool clearTeamConfigValidation = false,
    Set<String>? workingSessionIds,
  }) {
    return ChatState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
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
      sessionConnectingId: clearSessionConnectingId
          ? null
          : (sessionConnectingId ?? this.sessionConnectingId),
      sessionLaunchError: clearSessionLaunchError
          ? null
          : (sessionLaunchError ?? this.sessionLaunchError),
      teamConfigValidation: clearTeamConfigValidation
          ? null
          : (teamConfigValidation ?? this.teamConfigValidation),
      workingSessionIds: workingSessionIds ?? this.workingSessionIds,
    );
  }

  /// Working directory of the active session tab (its cwd), or empty when no
  /// tab is open. Used by chat routes that scope the tools to the active
  /// session rather than a fixed workspace.
  String get activeCwd {
    if (activeTabIndex >= 0 && activeTabIndex < tabs.length) {
      return tabs[activeTabIndex].subtitle;
    }
    return '';
  }

  bool get isActiveSessionConnecting {
    final id = sessionConnectingId;
    final active = activeSessionId;
    if (id == null || id.isEmpty) return false;
    if (id == 'pending') return true;
    if (active == null || active.isEmpty) return true;
    return id == active;
  }

  @override
  List<Object?> get props => [
    tabs,
    activeTabIndex,
    workspaces,
    sessions,
    visibleWorkspaces,
    visibleSessions,
    activeSessionId,
    selectedMemberId,
    stateVersion,
    snackbarMessage,
    sessionConnectingId,
    sessionLaunchError,
    teamConfigValidation,
    workingSessionIds,
  ];
}
