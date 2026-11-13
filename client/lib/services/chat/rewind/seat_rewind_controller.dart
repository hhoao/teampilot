import 'package:uuid/uuid.dart';

import '../../../models/app_session.dart';
import '../../../models/team_config.dart';
import '../../../repositories/session_repository.dart';
import '../../../utils/logging/logger.dart';
import 'edit/edit_operation.dart';
import 'rewind_fork_service.dart';
import 'rewind_work_gate.dart';
import 'seat_branches.dart';
import 'seat_rewind_paths.dart';
import 'seat_rewind_policy.dart';
import 'seat_rewind_store.dart';

/// Narrow host surface the rewind controller needs from ChatCubit.
///
/// Keeping this explicit avoids moving ChatCubit's private tabs/launch/history
/// state into the controller while still taking the rewind algorithms out of
/// the cubit.
abstract interface class SeatRewindHost {
  bool get rewindIsClosed;
  AppSession? rewindSessionFor(String sessionId);
  CliTool rewindCliFor(AppSession session, String memberId);
  bool rewindIsAcp(AppSession session, String memberId);
  SeatProcess rewindSeatProcess(AppSession session, String memberId);
  ForkSessionCreator rewindForkCreator(
    SessionRepository repo,
    String fixedSessionId,
  );
  SessionRepository? get rewindRepository;
  Iterable<AppSession> get rewindSessions;
  Future<void> rewindAwaitSeatReady(String sessionId);
  Future<bool> rewindDeliverEdited({
    required String sessionId,
    required String memberId,
    required String message,
  });
  Future<AppSession?> rewindHydrate(String workspaceId, String sessionId);
  void rewindSetInProgress(String sessionId, bool value);
  void rewindPublishHistory(String sessionId);
  void rewindMarkHistoryStale(String sessionId);
}

/// Loads branch versions and runs switch/edit/fork for one seat.
///
/// ChatCubit owns the state and UI callbacks; this class owns the rewind
/// workflow so entry points stay small and testable.
final class SeatRewindController {
  SeatRewindController({
    required this.host,
    required this.policy,
    required this.forkService,
    required this.gate,
  });

  final SeatRewindHost host;
  final SeatRewindPolicy policy;
  final RewindForkService forkService;
  final RewindWorkGate gate;

  static const _uuid = Uuid();

  SeatRewindEligibility _eligibility(AppSession session, String memberId) {
    // Direct controller actions may target a mixed seat so the feature can be
    // tested/enabled later; UI and checkpoint entry points still read the
    // public kMixedSeatRewindEnabled gate.
    return policy.evaluate(
      session: session,
      memberId: memberId,
      cli: host.rewindCliFor(session, memberId),
      acp: host.rewindIsAcp(session, memberId),
      allowMixed: true,
    );
  }

  Future<SeatBranches> loadBranches({
    required AppSession session,
    required String memberId,
  }) async {
    final eligibility = _eligibility(session, memberId);
    final store = eligibility.store;
    if (store == null || !await store.repoExists()) {
      return const SeatBranches.empty();
    }
    return readSeatBranches(store: store);
  }

  Future<void> switchVersion({
    required String sessionId,
    required String memberId,
    required String commit,
  }) async {
    final session = host.rewindSessionFor(sessionId);
    if (session == null) return;
    final eligibility = _eligibility(session, memberId);
    final store = eligibility.store;
    if (store == null) {
      appLogger.d(
        '[rewind] switch skipped session=$sessionId '
        'denial=${eligibility.denial}',
      );
      return;
    }
    host.rewindSetInProgress(sessionId, true);
    try {
      // Resolve the tip only after any in-flight snapshot settles; a
      // checkpoint landing in between would otherwise leave a stale tip.
      await gate.waitForSnapshot(store.gitDir);
      final tip = await store.branchTip(commit);
      await forkService.rewind(
        store: store,
        seat: host.rewindSeatProcess(session, memberId),
        commit: tip,
      );
      host.rewindMarkHistoryStale(sessionId);
      host.rewindPublishHistory(sessionId);
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[rewind] switchSeatVersion failed session=$sessionId: $error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      if (!host.rewindIsClosed) {
        host.rewindSetInProgress(sessionId, false);
      }
    }
  }

  /// Restore the turn before [userMessageId] and resend [text].
  ///
  /// [onPhase] reports each step so the coordinator can show progress; the
  /// caller stops the operation from a compose Stop by flipping [aborted],
  /// which is only honoured between phases.
  Future<void> editTurn({
    required String sessionId,
    required String memberId,
    required String userMessageId,
    required String text,
    void Function(EditPhase phase)? onPhase,
    bool Function()? aborted,
  }) async {
    final session = host.rewindSessionFor(sessionId);
    if (session == null) {
      throw StateError('Session not found');
    }
    final store = _eligibility(session, memberId).store;
    if (store == null) {
      throw StateError('Seat is not rewind-capable');
    }
    if (aborted?.call() ?? false) {
      throw const SeatEditCancelled();
    }
    // Read the graph only after any in-flight checkpoint settles; otherwise
    // the parent and the previous checked-out tip can be one turn stale.
    await gate.waitForSnapshot(store.gitDir);
    RewindCheckpoint? target;
    for (final turn in await store.checkpoints()) {
      if (turn.userMessageId == userMessageId) {
        target = turn;
        break;
      }
    }
    if (target == null) {
      throw StateError('No checkpoint for the edited user message');
    }
    final before = await store.checkedOut();
    // Only roll back when the parent restore actually ran; a refused restore
    // (e.g. a turn latched) must not be force-rewound, which would stop the
    // running turn.
    var restored = false;
    host.rewindSetInProgress(sessionId, true);
    try {
      onPhase?.call(EditPhase.restoring);
      await forkService.rewind(
        store: store,
        seat: host.rewindSeatProcess(session, memberId),
        commit: target.parentCommit.isEmpty
            ? await store.root()
            : target.parentCommit,
        onRestored: () => restored = true,
      );
      if (aborted?.call() ?? false) throw const SeatEditCancelled();
      // The relaunch reconnects the seat asynchronously; a prompt delivered
      // while that connect is still in flight is rejected.
      onPhase?.call(EditPhase.relaunching);
      await host.rewindAwaitSeatReady(sessionId);
      if (aborted?.call() ?? false) throw const SeatEditCancelled();
      onPhase?.call(EditPhase.delivering);
      final delivered = await host.rewindDeliverEdited(
        sessionId: sessionId,
        memberId: memberId,
        message: text,
      );
      if (!delivered) {
        throw StateError('The edited message was not delivered');
      }
    } on SeatEditCancelled {
      appLogger.d(
        '[rewind] editTurn cancelled session=$sessionId restored=$restored',
      );
      if (restored && before != null) {
        try {
          await forkService.rewind(
            store: store,
            seat: host.rewindSeatProcess(session, memberId),
            commit: before,
            allowTurnInFlight: true,
          );
        } on Object catch (rollbackError, rollbackStack) {
          appLogger.e(
            '[rewind] edit cancel rollback failed session=$sessionId: '
            '$rollbackError',
            error: rollbackError,
            stackTrace: rollbackStack,
          );
        }
      }
      host.rewindMarkHistoryStale(sessionId);
      host.rewindPublishHistory(sessionId);
      rethrow;
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[rewind] editTurn failed session=$sessionId: $error',
        error: error,
        stackTrace: stackTrace,
      );
      if (restored && before != null) {
        try {
          // The send already failed, so a latched turn must not keep the seat
          // on the parent branch. Only this rollback skips the guard.
          await forkService.rewind(
            store: store,
            seat: host.rewindSeatProcess(session, memberId),
            commit: before,
            allowTurnInFlight: true,
          );
        } on Object catch (rollbackError, rollbackStack) {
          appLogger.e(
            '[rewind] edit rollback failed session=$sessionId: '
            '$rollbackError',
            error: rollbackError,
            stackTrace: rollbackStack,
          );
        }
      }
      // Surface whichever branch the seat is actually on now: the rollback
      // target after a failed send, or the unchanged parent after a refused
      // restore.
      host.rewindMarkHistoryStale(sessionId);
      host.rewindPublishHistory(sessionId);
      rethrow;
    } finally {
      if (!host.rewindIsClosed) {
        host.rewindSetInProgress(sessionId, false);
      }
    }
    // Success: refresh only after the send landed, so a refresh failure
    // cannot revert a good edit.
    host.rewindMarkHistoryStale(sessionId);
    host.rewindPublishHistory(sessionId);
  }

  Future<AppSession?> forkFrom({
    required String sessionId,
    required String memberId,
    required String commit,
  }) async {
    final source = host.rewindSessionFor(sessionId);
    if (source == null) return null;
    final store = _eligibility(source, memberId).store;
    final repo = host.rewindRepository;
    if (store == null || repo == null) return null;
    host.rewindSetInProgress(sessionId, true);
    try {
      final created = await _forkUnlocked(
        source: source,
        store: store,
        repo: repo,
        memberId: memberId,
        commit: commit,
      );
      if (created != null) host.rewindPublishHistory(sessionId);
      return created;
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[rewind] forkFrom failed session=$sessionId: $error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      if (!host.rewindIsClosed) {
        host.rewindSetInProgress(sessionId, false);
      }
    }
  }

  Future<AppSession?> _forkUnlocked({
    required AppSession source,
    required SeatRewindStore store,
    required SessionRepository repo,
    required String memberId,
    required String commit,
  }) async {
    final cli = host.rewindCliFor(source, memberId);
    final newId = _uuid.v4();
    final acp = host.rewindIsAcp(source, memberId);
    final destTarget = resolveSeatRewindTarget(
      personal: true,
      acp: acp,
      tool: cli.value,
    );
    final ctx = policy.contextForSession(source, memberId);
    if (ctx == null) {
      throw StateError('work-plane context not resolved for fork');
    }
    final dest = SeatRewindStore.forContext(
      context: ctx,
      workspaceId: source.workspaceId,
      sessionId: newId,
      target: destTarget,
    );
    final createdId = await forkService.fork(
      source: store,
      commit: commit,
      destTarget: destTarget,
      destGitDir: dest.gitDir,
      destWorkTree: dest.workTree,
      sessions: host.rewindForkCreator(repo, newId),
      workspaceId: source.workspaceId,
      cli: cli,
      display: '${source.display} fork',
      workingDirectory: source.firstFolderPath,
    );
    for (final session in host.rewindSessions) {
      if (session.sessionId == createdId) return session;
    }
    return host.rewindHydrate(source.workspaceId, createdId);
  }
}
