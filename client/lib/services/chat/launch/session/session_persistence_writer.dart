import '../../host/chat_state_port.dart';
import '../../host/launch_environment_port.dart';
import '../../host/session_repository_port.dart';
import '../../host/tab_port.dart';
import '../../model/chat_tab.dart';
import '../../session/session_continue_overrides_controller.dart';
import '../../session/session_data_store.dart';
import '../../host/session_launch_host.dart';
import '../../../../models/app_session.dart';
import '../../../../models/session_member_binding.dart';
import '../../../../models/team_config.dart';
import '../../../../repositories/session_repository.dart';
import '../../../../utils/logging/logger.dart';
import '../../session/session_preset_follow_sync.dart';
import '../../session/shell_launch_spec.dart';

/// Session-row persistence performed during a seat connect.
///
/// These three operations — syncing a followed preset, recording the CLI's
/// native session id, and marking a session launched — used to live on
/// `SessionShellConnector`. They write repository rows, the tab's cached
/// session, and the cubit snapshot, none of which is the shell connector's
/// job. Keeping them here leaves the connector focused on spawning the PTY.
class SessionPersistenceWriter {
  SessionPersistenceWriter({
    required SessionRepositoryPort repository,
    required SessionSnapshotPort snapshots,
    required ChatStatePort chatState,
    required TabPort tabs,
    required LaunchEnvironmentPort environment,
    required SessionDataStore dataStore,
  }) : _repository = repository,
       _snapshots = snapshots,
       _chatState = chatState,
       _tabs = tabs,
       _environment = environment,
       _dataStore = dataStore;

  final SessionRepositoryPort _repository;
  final SessionSnapshotPort _snapshots;
  final ChatStatePort _chatState;
  final TabPort _tabs;
  final LaunchEnvironmentPort _environment;
  final SessionDataStore _dataStore;

  /// Re-syncs a session whose preset changed while it was disconnected.
  ///
  /// Returns [session] unchanged when nothing is stale.
  Future<AppSession> syncFollowedPresetOnConnect({
    required AppSession session,
    required ChatTab tab,
    required bool isPersonal,
    required String memberId,
    CliTool? lockedCli,
  }) async {
    final presets = _environment.lifecycle.globalPresets;
    final patched = isPersonal
        ? staleFollowingSimpleSession(session: session, presets: presets)
        : staleFollowingTeamSession(
            session: session,
            memberId: memberId,
            presets: presets,
            lockedCli: lockedCli,
          );
    if (patched == null) return session;
    final repo = _repository.sessionRepository;
    if (repo != null) {
      await persistFollowedSession(
        repo: repo,
        patched: patched,
        isSimple: isPersonal,
      );
    }
    if (_chatState.isClosed) return patched;
    _snapshots.replaceSessionSnapshot(patched);
    final cached = tab.persistedSession;
    if (cached != null && cached.sessionId == patched.sessionId) {
      tab.persistedSession =
          SessionContinueOverridesController.mergeOntoTabCache(
            cached: cached,
            patched: patched,
          );
    }
    return patched;
  }

  /// Records the CLI-native session id from [plan] against the session row.
  ///
  /// No-op when there is nothing to persist (no repo, no native id, no tool, or
  /// a still-unsaved `local-` session).
  Future<void> persistNativeSessionId({
    required ChatTab tab,
    required AppSession session,
    required SessionMemberBinding? binding,
    required LaunchPlan plan,
    SessionRepository? repo,
  }) async {
    final id = plan.nativeSessionIdToPersist?.trim() ?? '';
    final tool = plan.toolValue?.trim() ?? '';
    final r = repo ?? _repository.sessionRepository;
    if (r == null ||
        id.isEmpty ||
        tool.isEmpty ||
        session.sessionId.startsWith('local-')) {
      return;
    }

    AppSession applyNative(AppSession s) {
      if (binding != null) {
        return s.copyWith(
          members: [
            for (final m in s.members)
              if (m.rosterMemberId == binding.rosterMemberId)
                m.withNativeSessionId(tool, id)
              else
                m,
          ],
        );
      }
      return s.withNativeSessionId(tool, id);
    }

    final current = tab.persistedSession ?? session;
    if (identical(applyNative(current), current)) return;

    try {
      await r.recordNativeSessionId(
        session.sessionId,
        tool: tool,
        nativeId: id,
        rosterMemberId: binding?.rosterMemberId,
      );
    } on Object catch (e, st) {
      appLogger.w(
        '[session] persist native session id failed: $e',
        error: e,
        stackTrace: st,
      );
      return;
    }
    if (_chatState.isClosed) return;

    tab.persistedSession = applyNative(current);
    final state = _chatState.state;
    final sessions = state.sessions
        .map((s) => s.sessionId == session.sessionId ? applyNative(s) : s)
        .toList();
    _snapshots.emitSnapshot(
      _dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
    );
  }

  /// Marks [sessionId] launched in the repository and in memory.
  Future<void> persistSessionStarted(
    String sessionId, {
    SessionRepository? repo,
  }) async {
    final r = repo ?? _repository.sessionRepository;
    if (r == null) return;
    await r.markSessionLaunched(sessionId);
    if (_chatState.isClosed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final state = _chatState.state;
    final sessions = state.sessions.map((s) {
      if (s.sessionId != sessionId) return s;
      return s.copyWith(
        launchState: AppSessionLaunchState.started,
        updatedAt: now,
      );
    }).toList();
    // Keep the open tab's cached session in sync — history-review reconnect
    // reads tab.persistedSession for previouslyLaunched / resume decisions.
    final tab = _tabs.tabStore.openTabBySessionId(sessionId);
    final cached = tab?.persistedSession;
    if (tab != null && cached != null && cached.sessionId == sessionId) {
      tab.persistedSession = cached.copyWith(
        launchState: AppSessionLaunchState.started,
        updatedAt: now,
      );
    }
    _snapshots.emitSnapshot(
      _dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
    );
  }
}
