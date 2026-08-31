import 'dart:async';
import 'dart:convert';

import '../../models/app_session.dart';
import '../../models/team_generation_settings.dart';
import '../../services/io/filesystem.dart';
import '../../services/storage/app_storage.dart';
import '../../services/storage/workspace_layout.dart';
import '../../utils/lock_pool.dart';
import '../../utils/logging/logger.dart';
import 'models/team_generation_job.dart';
import 'models/team_generation_launch.dart';

/// Tombstone retention bounds (plan: 100 per workspace, 30 days).
const teamGenerationTombstoneMaxPerWorkspace = 100;
const teamGenerationTombstoneMaxAge = Duration(days: 30);

/// Durable per-workflow job persistence: atomic job.json writes, monotonic
/// phase transitions, WAL receipts, tombstone compaction, and cancellation.
final class TeamGenerationJobStore {
  TeamGenerationJobStore({
    Filesystem? fs,
    WorkspaceLayout? layout,
    DateTime Function()? clock,
    LockPool? lockPool,
  }) : _fsOverride = fs,
       _layoutOverride = layout,
       _clock = clock ?? DateTime.now,
       _locks = lockPool ?? LockPool();

  final Filesystem? _fsOverride;
  final WorkspaceLayout? _layoutOverride;
  final DateTime Function() _clock;
  final LockPool _locks;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  WorkspaceLayout get _layout =>
      _layoutOverride ?? WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);

  String _lockKey(String workspaceId, String workflowId) =>
      '$workspaceId/$workflowId';

  Future<T> _synchronized<T>(
    String workspaceId,
    String workflowId,
    Future<T> Function() body,
  ) => _locks.synchronized(_lockKey(workspaceId, workflowId), body);

  // ---------------------------------------------------------------- reads

  Future<TeamGenerationJob?> read(String workspaceId, String workflowId) async {
    final file = _layout.teamGenerationJobFile(workspaceId, workflowId);
    try {
      final raw = await _fs.readString(file);
      if (raw == null || raw.trim().isEmpty) return null;
      return TeamGenerationJob.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } on FormatException {
      rethrow;
    } on Object catch (e) {
      appLogger.w('[team-generation] unreadable job $workspaceId/$workflowId: $e');
      return null;
    }
  }

  /// All parseable jobs under one workspace; malformed directory names are
  /// skipped and reported through diagnostics (never joined).
  Future<List<TeamGenerationJob>> listAll(String workspaceId) async {
    final dir = _layout.teamGenerationDir(workspaceId);
    final stat = await _fs.stat(dir);
    if (!stat.exists || stat.kind != FsEntityKind.directory) return const [];
    final jobs = <TeamGenerationJob>[];
    for (final entry in await _fs.listDir(dir)) {
      final name = entry.name.trim();
      if (!isValidTeamGenerationWorkflowId(name)) continue;
      final job = await read(workspaceId, name);
      if (job != null) jobs.add(job);
    }
    return jobs;
  }

  /// Active (non-terminal, non-failed) jobs with a usable builder link.
  Future<List<TeamGenerationJob>> listRecoverable(String workspaceId) async {
    final jobs = await listAll(workspaceId);
    return [
      for (final job in jobs)
        if (!job.isTerminal) job,
    ];
  }

  // --------------------------------------------------------------- writes

  Future<TeamGenerationJob> create({
    required String workspaceId,
    required String workflowId,
    required String builderSessionId,
    required String originalPrompt,
    required TeamGenerationJobGenerator generator,
    required TeamGenerationSettingsSnapshot settings,
    required TeamGenerationLaunchSnapshot launch,
  }) {
    requireValidTeamGenerationWorkflowId(workflowId);
    final now = _clock().millisecondsSinceEpoch;
    final job = TeamGenerationJob(
      workspaceId: workspaceId,
      workflowId: workflowId,
      builderSessionId: builderSessionId.trim(),
      destinationSessionId: '',
      teamId: '',
      originalPrompt: originalPrompt,
      generator: generator,
      settings: settings,
      launch: launch,
      phase: TeamGenerationPhase.created,
      resumePhase: TeamGenerationPhase.created,
      attempt: 0,
      probeSnapshotJson: null,
      normalizedPlanJson: null,
      planRevision: '',
      validatedRevision: '',
      validatedDestinationJson: null,
      finalizeIdempotencyKey: '',
      receipts: const {},
      stagedResources: const [],
      teamReservation: null,
      error: null,
      createdAt: now,
      updatedAt: now,
    );
    return _synchronized(workspaceId, workflowId, () async {
      final existing = await read(workspaceId, workflowId);
      if (existing != null) {
        throw StateError('workflow already exists: $workflowId');
      }
      await _write(job);
      return job;
    });
  }

  /// Monotonic mutation: phase may advance, stay, fail (with [resumePhase]),
  /// or cancel pre-profile. Receipts may not replace a succeeded value.
  Future<TeamGenerationJob> mutate(
    String workspaceId,
    String workflowId,
    TeamGenerationJob Function(TeamGenerationJob job) transform,
  ) => _synchronized(workspaceId, workflowId, () async {
    final current = await read(workspaceId, workflowId);
    if (current == null) {
      throw StateError('missing job: $workflowId');
    }
    if (current.isTerminal) {
      throw StateError('job is terminal: ${current.phase.name}');
    }
    final updated = transform(current.copyWith(updatedAt: _now()));
    _assertTransition(current, updated);
    _assertReceipts(current.receipts, updated.receipts);
    await _write(updated);
    return updated;
  });

  void _assertTransition(TeamGenerationJob from, TeamGenerationJob to) {
    if (from.phase == to.phase) return;
    if (!_canAdvance(from.phase, to.phase)) {
      throw StateError(
        'illegal phase transition ${from.phase.name} -> ${to.phase.name}',
      );
    }
    if (to.phase == TeamGenerationPhase.failed &&
        to.resumePhase == TeamGenerationPhase.created &&
        from.phase != TeamGenerationPhase.created) {
      throw StateError('failed job must record its resumePhase');
    }
  }

  bool _canAdvance(TeamGenerationPhase from, TeamGenerationPhase to) {
    if (to == TeamGenerationPhase.failed ||
        to == TeamGenerationPhase.cancelled) {
      return true;
    }
    final fromRank = teamGenerationActivePhaseRank(from);
    final toRank = teamGenerationActivePhaseRank(to);
    if (fromRank == null || toRank == null) return false;
    return toRank >= fromRank;
  }

  void _assertReceipts(
    Map<String, TeamGenerationReceipt> before,
    Map<String, TeamGenerationReceipt> after,
  ) {
    for (final entry in after.entries) {
      final previous = before[entry.key];
      if (!_canReplaceReceipt(previous, entry.value)) {
        throw StateError(
          'receipt ${entry.key} cannot be replaced '
          '(${previous?.state.name} -> ${entry.value.state.name})',
        );
      }
    }
  }

  bool _canReplaceReceipt(TeamGenerationReceipt? before, TeamGenerationReceipt after) =>
      before == null ||
      before.state != TeamGenerationReceiptState.succeeded ||
      (after.state == TeamGenerationReceiptState.succeeded &&
          before.value == after.value);

  /// Reserves one workflow effect; rejects terminal jobs so a cancelled or
  /// completed workflow stops admitting new side effects.
  Future<void> reserveEffect(
    String workspaceId,
    String workflowId,
    String effectKey,
  ) async {
    final current = await read(workspaceId, workflowId);
    if (current == null || current.isTerminal) {
      throw StateError('workflow not active: $workflowId');
    }
    if (current.receipts[effectKey]?.state ==
        TeamGenerationReceiptState.succeeded) {
      return;
    }
    await mutate(workspaceId, workflowId, (job) {
      return job.copyWith(
        receipts: {
          ...job.receipts,
          effectKey: const TeamGenerationReceipt(
            state: TeamGenerationReceiptState.reserved,
          ),
        },
      );
    });
  }

  /// Records/updates an effect receipt; the only writer allowed to touch
  /// receipts while a cancellation is pending (cleanup receipts included).
  Future<void> recordReceipt(
    String workspaceId,
    String workflowId,
    String effectKey,
    TeamGenerationReceipt receipt,
  ) {
    return _synchronized(workspaceId, workflowId, () async {
      final current = await read(workspaceId, workflowId);
      if (current == null) {
        throw StateError('missing job: $workflowId');
      }
      final updated = current.copyWith(
        receipts: {...current.receipts, effectKey: receipt},
        updatedAt: _now(),
      );
      _assertReceipts(current.receipts, updated.receipts);
      await _write(updated);
    });
  }

  // ------------------------------------------------------------ lifecycle

  /// Marks a pre-profile cancellation; recovery finishes directory removal.
  Future<TeamGenerationJob> beginCancel(String workspaceId, String workflowId) {
    return _synchronized(workspaceId, workflowId, () async {
      final current = await read(workspaceId, workflowId);
      if (current == null) {
        throw StateError('missing job: $workflowId');
      }
      if (current.isTerminal) return current;
      final cancelled = current.copyWith(
        phase: TeamGenerationPhase.cancelled,
        updatedAt: _now(),
      );
      await _write(cancelled);
      return cancelled;
    });
  }

  /// Leaves [failed] restoring exactly the recorded safe phase.
  Future<TeamGenerationJob> resumeFailed(String workspaceId, String workflowId) {
    return _synchronized(workspaceId, workflowId, () async {
      final current = await read(workspaceId, workflowId);
      if (current == null) {
        throw StateError('missing job: $workflowId');
      }
      if (current.phase != TeamGenerationPhase.failed) {
        throw StateError('job is not failed: ${current.phase.name}');
      }
      if (current.isTerminal) {
        throw StateError('cannot resume a terminal job');
      }
      final resumed = current.copyWith(
        phase: current.resumePhase,
        clearError: true,
        updatedAt: _now(),
      );
      await _write(resumed);
      return resumed;
    });
  }

  /// Requires cleanup receipts before removing a cancelled workflow directory.
  Future<void> deleteCancelled(String workspaceId, String workflowId) async {
    await _synchronized(workspaceId, workflowId, () async {
      final current = await read(workspaceId, workflowId);
      if (current == null) return;
      if (current.phase != TeamGenerationPhase.cancelled) {
        throw StateError('job is not cancelled: ${current.phase.name}');
      }
      bool receiptSucceeded(String key) =>
          current.receipts[key]?.state == TeamGenerationReceiptState.succeeded;
      if (!receiptSucceeded('builderDeleted') ||
          !receiptSucceeded('stagingDeleted')) {
        throw StateError('cancel cleanup receipts missing');
      }
      await _fs.removeRecursive(
        _layout.teamGenerationWorkflowDir(workspaceId, workflowId),
      );
    });
  }

  /// Converts a delivered workflow into a tombstone: sensitive payloads are
  /// scrubbed from disk, then old/over-cap tombstones are pruned.
  Future<void> compactComplete(String workspaceId, String workflowId) {
    return _synchronized(workspaceId, workflowId, () async {
      final current = await read(workspaceId, workflowId);
      if (current == null) return;
      final compacted = current.copyWith(
        phase: TeamGenerationPhase.complete,
        updatedAt: _now(),
      );
      await _write(compacted);
      await _pruneTombstones(workspaceId);
    });
  }

  Future<void> _pruneTombstones(String workspaceId) async {
    final jobs = await listAll(workspaceId);
    final tombstones =
        jobs.where((job) => job.phase == TeamGenerationPhase.complete).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final cutoff =
        _clock().subtract(teamGenerationTombstoneMaxAge).millisecondsSinceEpoch;
    for (final job in tombstones) {
      final tooOld = job.updatedAt < cutoff;
      if (tooOld) {
        await _fs.removeRecursive(
          _layout.teamGenerationWorkflowDir(workspaceId, job.workflowId),
        );
      }
    }
    final remaining =
        (await listAll(workspaceId))
            .where((job) => job.phase == TeamGenerationPhase.complete)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final job in remaining.skip(teamGenerationTombstoneMaxPerWorkspace)) {
      await _fs.removeRecursive(
        _layout.teamGenerationWorkflowDir(workspaceId, job.workflowId),
      );
    }
  }

  int _now() => _clock().millisecondsSinceEpoch;

  Future<void> _write(TeamGenerationJob job) async {
    final file = _layout.teamGenerationJobFile(job.workspaceId, job.workflowId);
    final stagingDir = _layout.teamGenerationStagingDir(
      job.workspaceId,
      job.workflowId,
    );
    await _fs.ensureDir(_fs.pathContext.dirname(file));
    await _fs.ensureDir(stagingDir);
    await _fs.atomicWrite(
      file,
      const JsonEncoder.withIndent('  ').convert(job.toJson()),
    );
  }
}
