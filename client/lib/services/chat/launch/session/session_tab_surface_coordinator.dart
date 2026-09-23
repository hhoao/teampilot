import '../../session/chat_tab_store.dart';
import '../../session/chat_tab.dart';
import '../../session/chat_tab_info.dart';
import '../../session/session_open_request.dart';
import '../../session/session_workbench_view.dart';
import '../connect/launch_generation_store.dart';
import '../session_launch_host.dart';
import '../../../../models/app_session.dart';
import '../../../../models/workspace.dart';
import '../../../../utils/logging/logger.dart';
import '../../../../utils/team/team_member_naming.dart';

/// The tab identity produced by one synchronous surface operation.
final class SessionTabSurfaceResult {
  const SessionTabSurfaceResult({
    required this.tab,
    required this.session,
    required this.generation,
    required this.workspace,
    required this.connect,
    required this.reused,
  });

  final ChatTab tab;
  final AppSession session;
  final int generation;
  final Workspace? workspace;

  /// Whether the caller should enqueue a connection for this generation.
  final bool connect;
  final bool reused;
}

/// Owns only synchronous session-tab registration, reuse, and activation.
class SessionTabSurfaceCoordinator {
  SessionTabSurfaceCoordinator({
    required SessionLaunchHost host,
    required ChatTabStore tabStore,
    LaunchGenerationStore? generations,
    this.onSessionTabOpened,
  }) : _host = host,
       _tabStore = tabStore,
       _generations = generations ?? LaunchGenerationStore();

  /// Single domain → bar handshake for a surfaced session tab.
  final void Function(
    String workspaceId,
    String sessionId, {
    bool preview,
    bool activate,
  })?
  onSessionTabOpened;

  final SessionLaunchHost _host;
  final ChatTabStore _tabStore;
  final LaunchGenerationStore _generations;

  SessionTabSurfaceResult surfaceExistingTab({
    required SessionOpenRequest request,
    required ChatTab existing,
    required Workspace? workspace,
    required bool connect,
  }) {
    var session = request.session;
    final persisted = existing.persistedSession;
    if (!request.isPersonal &&
        session.cliTeamName.isEmpty &&
        persisted != null &&
        persisted.cliTeamName.isNotEmpty) {
      session = persisted;
    }
    existing.persistedSession = session;
    appLogger.d(
      '[session-launch] reuse existing tab session=${session.sessionId}',
    );

    final memberId = request.isPersonal
        ? existing.selectedMemberId
        : (request.member?.id ?? existing.selectedMemberId);
    if (memberId.isNotEmpty) {
      _host.assignSelectedMember(existing, memberId);
    }

    final sessionConnectAlreadyScheduled = _host.isSessionConnecting(
      session.sessionId,
    );
    final memberConnectAlreadyScheduled =
        sessionConnectAlreadyScheduled &&
        memberId.isNotEmpty &&
        (existing.membersPendingConnect.contains(memberId) ||
            existing.memberShells[memberId]?.isConnecting == true);
    final generation = sessionConnectAlreadyScheduled
        ? _generations.current(session.sessionId)
        : _generations.bump(session.sessionId);
    onSessionTabOpened?.call(
      existing.workspaceId,
      session.sessionId,
      preview:
          request.preview ??
          (!request.connectImmediately && !existing.isRunning),
      activate: true,
    );
    _host.refreshActiveWorkspaceTabs();

    if (request.connectImmediately && !request.preserveWorkbenchView) {
      _host.setPodView(existing.info.id, SessionWorkbenchView.terminal);
    }
    if (connect && memberConnectAlreadyScheduled) {
      appLogger.d(
        '[session-launch] skip duplicate connect session=${session.sessionId} '
        'member=$memberId',
      );
    }
    return SessionTabSurfaceResult(
      tab: existing,
      session: session,
      generation: generation,
      workspace: workspace,
      connect: connect && !memberConnectAlreadyScheduled,
      reused: true,
    );
  }

  SessionTabSurfaceResult surfaceNewTab({
    required SessionOpenRequest request,
    required AppSession session,
    required Workspace? workspace,
    required bool connect,
  }) {
    final placeholderMemberId = request.isPersonal
        ? ''
        : (request.member?.id ?? TeamMemberNaming.teamLeadName);
    final info = ChatTabInfo(
      id: session.sessionId,
      title: session.resolveDisplayTitle(request.emptyDisplayTitleFallback),
      subtitle: session.firstFolderPath,
    );
    final tab =
        ChatTab(
            info: info,
            cliTeamName: session.cliTeamName,
            workspaceId: session.workspaceId,
          )
          ..persistedSession = session
          ..selectedMemberId = placeholderMemberId;
    final generation = _generations.bump(session.sessionId);

    _tabStore.registerSession(tab);
    _host.sessionRuntime.ensureIdleWatch();
    onSessionTabOpened?.call(
      session.workspaceId,
      tab.info.id,
      preview: request.preview ?? !request.connectImmediately,
      activate: true,
    );
    _host.refreshActiveWorkspaceTabs();
    if (request.connectImmediately && !request.preserveWorkbenchView) {
      _host.setPodView(tab.info.id, SessionWorkbenchView.terminal);
    }

    return SessionTabSurfaceResult(
      tab: tab,
      session: session,
      generation: generation,
      workspace: workspace,
      connect: connect,
      reused: false,
    );
  }
}
