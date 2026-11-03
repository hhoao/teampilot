import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/rewind/rewind_work_gate.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_paths.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_store.dart';

/// One local seat process that rewind can stop and relaunch.
abstract interface class SeatProcess {
  bool get turnInFlight;
  bool get localRuntime;
  Future<void> stopAndWait();
  Future<void> recordNativeSessionId(String? nativeSessionId);
  Future<void> relaunch();
}

/// Creates and deletes the personal session that a fork copies into.
abstract interface class ForkSessionCreator {
  Future<String> createPersonal({
    required String workspaceId,
    required CliTool cli,
    required String display,
    required String? workingDirectory,
    required String? nativeSessionId,
  });
  Future<void> deleteSession(String sessionId);
}

/// Stops a seat around [SeatRewindStore.restore] and creates a session around
/// [SeatRewindStore.forkAt]. Does not shell out to Git.
final class RewindForkService {
  RewindForkService({RewindWorkGate? gate}) : gate = gate ?? RewindWorkGate();

  final RewindWorkGate gate;

  /// Restore [commit] into [store] after stopping [seat], then relaunch.
  Future<void> rewind({
    required SeatRewindStore store,
    required SeatProcess seat,
    required String commit,
  }) async {
    if (seat.turnInFlight) {
      throw StateError('Cannot rewind while a turn is in flight');
    }
    if (!seat.localRuntime) {
      throw StateError('Cannot rewind a remote runtime');
    }
    await gate.waitForSnapshot(store.gitDir);
    if (gate.isInProgress(store.gitDir)) {
      throw StateError('Cannot rewind while another rewind or fork is running');
    }
    gate.begin(store.gitDir);
    try {
      await seat.stopAndWait();
      await store.restore(commit);
      String? nativeSessionId;
      for (final checkpoint in await store.checkpoints()) {
        if (checkpoint.commit == commit) {
          nativeSessionId = checkpoint.nativeSessionId;
          break;
        }
      }
      await seat.recordNativeSessionId(nativeSessionId);
      await seat.relaunch();
    } finally {
      gate.end(store.gitDir);
    }
  }

  /// Create a personal session, then copy [commit] from [source] into it.
  Future<String> fork({
    required SeatRewindStore source,
    required String commit,
    required SeatRewindTarget destTarget,
    required String destGitDir,
    required String destWorkTree,
    required ForkSessionCreator sessions,
    required String workspaceId,
    required CliTool cli,
    required String display,
    required String? workingDirectory,
  }) async {
    await gate.waitForSnapshot(source.gitDir);
    if (gate.isInProgress(source.gitDir)) {
      throw StateError('Cannot fork while another rewind or fork is running');
    }
    gate.begin(source.gitDir);
    try {
      String? nativeSessionId;
      for (final checkpoint in await source.checkpoints()) {
        if (checkpoint.commit == commit) {
          nativeSessionId = checkpoint.nativeSessionId;
          break;
        }
      }
      final sessionId = await sessions.createPersonal(
        workspaceId: workspaceId,
        cli: cli,
        display: display,
        workingDirectory: workingDirectory,
        nativeSessionId: nativeSessionId,
      );
      try {
        await source.forkAt(
          commit: commit,
          destGitDir: destGitDir,
          destWorkTree: destWorkTree,
          destTarget: destTarget,
        );
      } catch (_) {
        await sessions.deleteSession(sessionId);
        rethrow;
      }
      return sessionId;
    } finally {
      gate.end(source.gitDir);
    }
  }
}
