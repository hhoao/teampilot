import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

import '../../../models/app_project.dart';
import '../../../models/app_session.dart';
import '../../../models/ssh_profile.dart';
import '../../../models/team_config.dart';
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
typedef CliExecutableResolver = String Function(TeamCli cli);

class ChatState extends Equatable {
  const ChatState({
    this.tabs = const [],
    this.activeTabIndex = 0,
    this.projects = const [],
    this.sessions = const [],
    this.visibleProjects = const [],
    this.visibleSessions = const [],
    this.activeSessionId,
    this.selectedMemberId = '',
    this.stateVersion = 0,
    this.snackbarMessage,
    this.sessionConnectingId,
    this.sessionLaunchError,
  });

  final List<ChatTabInfo> tabs;
  final int activeTabIndex;
  final List<AppProject> projects;
  final List<AppSession> sessions;
  final List<AppProject> visibleProjects;
  final List<AppSession> visibleSessions;
  final String? activeSessionId;
  final String selectedMemberId;
  final int stateVersion;
  final String? snackbarMessage;

  /// Session id while prepareLaunch / terminal spawn is in progress.
  final String? sessionConnectingId;

  /// Launch error when connect fails before a tab exists (empty workbench).
  final String? sessionLaunchError;

  ChatState copyWith({
    List<ChatTabInfo>? tabs,
    int? activeTabIndex,
    List<AppProject>? projects,
    List<AppSession>? sessions,
    List<AppProject>? visibleProjects,
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
  }) {
    return ChatState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
      projects: projects ?? this.projects,
      sessions: sessions ?? this.sessions,
      visibleProjects: visibleProjects ?? this.visibleProjects,
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
    );
  }

  /// Working directory of the active session tab (its cwd), or empty when no
  /// tab is open. Used by chat routes that scope the tools to the active
  /// session rather than a fixed project.
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
    projects,
    sessions,
    visibleProjects,
    visibleSessions,
    activeSessionId,
    selectedMemberId,
    stateVersion,
    snackbarMessage,
    sessionConnectingId,
    sessionLaunchError,
  ];
}
