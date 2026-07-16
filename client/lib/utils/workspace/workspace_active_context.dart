import '../../cubits/chat_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../models/app_session.dart';
import '../../models/landing_launch_context.dart';
import '../../models/team_config.dart';
import '../session/workspace_tab_session_scope.dart';

/// Resolved UI context for a workspace tab: active session team, or landing fallback.
class WorkspaceActiveContext {
  const WorkspaceActiveContext({
    required this.isPersonal,
    this.team,
    this.activeSessionId,
  });

  final bool isPersonal;
  final TeamProfile? team;
  final String? activeSessionId;

  static WorkspaceActiveContext resolve({
    required ChatCubit chat,
    required LaunchProfileCubit launchProfiles,
    required String tabScopeId,
    LandingLaunchContext? landingFallback,
  }) {
    final activeTab = scopedActiveChatTab(chat, tabScopeId);
    final sessionId = activeTab?.info.id;
    if (sessionId != null && sessionId.isNotEmpty) {
      final session = _sessionById(chat.state.sessions, sessionId);
      if (session != null) {
        return _fromSession(session, launchProfiles, sessionId);
      }
    }
    if (landingFallback != null) {
      return _fromLanding(landingFallback, launchProfiles);
    }
    return idle;
  }

  /// No session and no landing context — hide team chrome.
  static const idle = WorkspaceActiveContext(isPersonal: true);

  static WorkspaceActiveContext _fromSession(
    AppSession session,
    LaunchProfileCubit launchProfiles,
    String sessionId,
  ) {
    final teamId = session.sessionTeam.trim();
    if (teamId.isEmpty) {
      return WorkspaceActiveContext(
        isPersonal: true,
        activeSessionId: sessionId,
      );
    }
    final team = launchProfiles.byId(teamId);
    if (team is TeamProfile) {
      return WorkspaceActiveContext(
        isPersonal: false,
        team: team,
        activeSessionId: sessionId,
      );
    }
    return WorkspaceActiveContext(
      isPersonal: false,
      activeSessionId: sessionId,
    );
  }

  static WorkspaceActiveContext _fromLanding(
    LandingLaunchContext landing,
    LaunchProfileCubit launchProfiles,
  ) {
    if (landing.isPersonal) {
      return const WorkspaceActiveContext(isPersonal: true);
    }
    final teamId = landing.teamId?.trim() ?? '';
    if (teamId.isEmpty) {
      return const WorkspaceActiveContext(isPersonal: false);
    }
    final team = launchProfiles.byId(teamId);
    if (team is TeamProfile) {
      return WorkspaceActiveContext(isPersonal: false, team: team);
    }
    return const WorkspaceActiveContext(isPersonal: false);
  }

  static AppSession? _sessionById(List<AppSession> sessions, String sessionId) {
    for (final session in sessions) {
      if (session.sessionId == sessionId) return session;
    }
    return null;
  }
}
