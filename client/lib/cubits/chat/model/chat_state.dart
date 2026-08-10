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
    this.provisionVersion = 0,
    this.podViewVersion = 0,
    this.snackbarMessage,
    this.sessionLaunchError,
    this.teamConfigValidation,
    this.workingSessionIds = const {},
    this.newChatActive = true,
  });

  final List<ChatTabInfo> tabs;
  final int activeTabIndex;
  final List<Workspace> workspaces;
  final List<AppSession> sessions;
  final List<Workspace> visibleWorkspaces;
  final List<AppSession> visibleSessions;
  final String? activeSessionId;
  final String selectedMemberId;

  /// Bumped on every remote provision progress update so the remote-provision UI
  /// (ChatWorkbench) rebuilds without a catch-all state version.
  final int provisionVersion;

  /// Bumped when [SessionPod.setView] changes the workbench view (chat↔terminal).
  /// Widgets that read [ChatTab.workbenchView] (or the equivalent pod view) use
  /// this to stay in sync without depending on the removed stateVersion.
  final int podViewVersion;

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

  /// When true, the workbench shows new-chat landing instead of a session terminal.
  final bool newChatActive;

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
    int? provisionVersion,
    int? podViewVersion,
    String? snackbarMessage,
    bool clearSnackbarMessage = false,
    String? sessionLaunchError,
    bool clearSessionLaunchError = false,
    TeamConfigValidation? teamConfigValidation,
    bool clearTeamConfigValidation = false,
    Set<String>? workingSessionIds,
    bool? newChatActive,
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
      provisionVersion: provisionVersion ?? this.provisionVersion,
      podViewVersion: podViewVersion ?? this.podViewVersion,
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
      newChatActive: newChatActive ?? this.newChatActive,
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
    provisionVersion,
    podViewVersion,
    snackbarMessage,
    sessionLaunchError,
    teamConfigValidation,
    workingSessionIds,
    newChatActive,
  ];
}
