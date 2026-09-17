import '../../../cubits/chat/chat_tab_store.dart';
import '../../../cubits/chat/model/session_open_request.dart';
import '../../../models/workspace.dart';
import '../../../utils/logging/logger.dart';
import '../contracts/launch_outcome.dart';
import '../tab/session_tab_surface_coordinator.dart';
import 'session_launch_open_validator.dart';

/// Validates an open request and routes it to the tab surface.
///
/// Extracted from `SessionLaunchPipeline` so that both the pipeline (Flow A:
/// create/open a session) and `MemberConnectStage` (Flow B: connect a seat) can
/// depend on it. Flow B's existing-session connect needs to re-open a tab, and
/// having it call back into the pipeline's private `_runOpen` was what kept the
/// two flows tangled in one class.
class SessionOpenRouter {
  SessionOpenRouter({
    required ChatTabStore tabStore,
    required SessionTabSurfaceCoordinator tabSurface,
    required Workspace? Function(String workspaceId) workspaceById,
  }) : _tabStore = tabStore,
       _tabSurface = tabSurface,
       _workspaceById = workspaceById;

  final ChatTabStore _tabStore;
  final SessionTabSurfaceCoordinator _tabSurface;
  final Workspace? Function(String workspaceId) _workspaceById;

  Future<LaunchOpened> run(SessionOpenRequest request) async {
    final session = request.session;
    final isPersonal = request.isPersonal;
    appLogger.d(
      '[session-launch] pipeline open start '
      'session=${session.sessionId} personal=$isPersonal '
      'member=${request.member?.id ?? ''} team=${request.team?.id ?? ''} '
      'connectImmediately=${request.connectImmediately}',
    );

    final blocked = validateSessionOpenRequest(
      request: request,
      session: session,
      workspaceById: _workspaceById,
    );
    if (blocked != null) return LaunchOpened(blocked);

    final existing = _tabStore.openTabBySessionId(session.sessionId);
    if (existing != null) {
      final status = _tabSurface.surfaceExistingTab(
        request: request.withSession(session),
        existing: existing,
      );
      return LaunchOpened(status);
    }
    final status = _tabSurface.surfaceNewTab(
      request: request.withSession(session),
      session: session,
    );
    return LaunchOpened(status);
  }
}
