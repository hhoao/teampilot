import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../models/progress_activity.dart';
import 'progress_activity_cubit.dart';
import '../services/io/filesystem.dart';
import '../services/workspace/repo_clone_service.dart';
import '../utils/logging/logger.dart';

/// Lifecycle of a single clone task tracked by [RepoCloneCubit].
enum RepoCloneTaskPhase { cloning, succeeded, failed, cancelled }

/// One `git clone` task: state mirror + the data Task 4/5/6 UIs need.
class RepoCloneTask extends Equatable {
  const RepoCloneTask({
    required this.id,
    required this.url,
    required this.targetId,
    required this.destPath,
    required this.dirName,
    required this.phase,
    this.errorDetail,
    this.createdAt,
  });

  /// Doubles as the [ProgressActivity] id.
  final String id;
  final String url;
  final String targetId;

  /// Absolute on the target. Provisional (`parentDir/dirName`) until the
  /// service reports the canonical path.
  final String destPath;
  final String dirName;
  final RepoCloneTaskPhase phase;

  /// Git stderr tail, or a stable marker (`dest-exists` / `git-missing` /
  /// `precheck-skipped`) — markers are translated to plain English for
  /// history records by the cubit; full l10n stays in the UI layers.
  final String? errorDetail;
  final DateTime? createdAt;

  RepoCloneTask copyWith({
    String? destPath,
    RepoCloneTaskPhase? phase,
    String? errorDetail,
  }) {
    return RepoCloneTask(
      id: id,
      url: url,
      targetId: targetId,
      destPath: destPath ?? this.destPath,
      dirName: dirName,
      phase: phase ?? this.phase,
      errorDetail: errorDetail ?? this.errorDetail,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    url,
    targetId,
    destPath,
    dirName,
    phase,
    errorDetail,
    createdAt,
  ];
}

class RepoCloneState extends Equatable {
  const RepoCloneState({this.tasks = const [], this.pendingChoice = const []});

  final List<RepoCloneTask> tasks;

  /// Succeeded clones awaiting the user's new-vs-add choice (Task 6).
  final List<RepoCloneTask> pendingChoice;

  @override
  List<Object?> get props => [tasks, pendingChoice];
}

/// Maps repository clones onto [ProgressActivityCubit] activities.
///
/// Owns task state ([RepoCloneTask]) and cancellation flags; the actual clone
/// runs through the injected [RepoCloneGateway] (defaulting to
/// [RepoCloneService]). All user-facing strings stay raw (repo names, English
/// defaults for history records) — l10n happens in the UI layers.
class RepoCloneCubit extends Cubit<RepoCloneState> {
  RepoCloneCubit({
    required ProgressActivityCubit progressActivityCubit,
    RepoCloneGateway? service,
    String Function()? uuid,
    Future<Filesystem> Function(String targetId)? cleanupFs,
  }) : _progressActivityCubit = progressActivityCubit,
       _service = service,
       _uuid = uuid ?? _defaultUuid,
       _cleanupFs = cleanupFs ?? _cleanupFsFromService(service),
       super(const RepoCloneState());

  static String _defaultUuid() => const Uuid().v4();

  /// Default second-pass cleanup seam: the real service's host runner. Fakes
  /// (and a null service) get no second pass unless one is injected.
  static Future<Filesystem> Function(String targetId)? _cleanupFsFromService(
    RepoCloneGateway? service,
  ) {
    if (service is RepoCloneService) {
      final hostRunner = service.hostRunner;
      return (targetId) => hostRunner.filesystemFor(targetId);
    }
    return null;
  }

  final ProgressActivityCubit _progressActivityCubit;
  final RepoCloneGateway? _service;
  final String Function() _uuid;
  final Future<Filesystem> Function(String targetId)? _cleanupFs;

  final Map<String, bool> _cancelFlags = {};

  /// Pre-check failures (`dest-exists` / `git-missing`) and cancels that
  /// bypassed the pre-check entirely (`precheck-skipped`): the destination
  /// may be a pre-existing user directory — the second cleanup pass must
  /// skip them (the service itself also never cleans those up).
  static const Set<String> _precheckMarkers = {
    'dest-exists',
    'git-missing',
    'precheck-skipped',
  };

  /// Marker → plain-English history message (the cubit cannot read context
  /// l10n): internal markers must never surface raw in the notification
  /// history. Non-marker stderr tails pass through verbatim. The friendly
  /// l10n keys (`cloneRepositoryDestExists` / `cloneRepositoryGitMissing`)
  /// remain for a future UI-layer mapping of [RepoCloneTask.errorDetail].
  static const Map<String, String> _markerHistoryMessages = {
    'dest-exists': 'Destination folder already exists and is not empty',
    'git-missing': 'git was not found on the selected target machine',
  };

  /// Git's "fatal: destination path ... already exists and is not an empty
  /// directory" — belt-and-braces twin of the service's pre-existing-dir guard:
  /// when the raced dir appeared between the pre-check and the clone, the
  /// error text says so and the second cleanup pass must preserve it (same
  /// string the service matches on).
  static const String _alreadyExistsNeedle = 'already exists';

  /// Fire-and-forget: start a clone; errors land in [state] as a failed task.
  void startClone(RepoCloneRequest request) {
    final id = _uuid();
    final now = DateTime.now();
    final task = RepoCloneTask(
      id: id,
      url: request.url,
      targetId: request.targetId,
      destPath: _provisionalDestPath(request.parentDir, request.dirName),
      dirName: request.dirName,
      phase: RepoCloneTaskPhase.cloning,
      createdAt: now,
    );
    _cancelFlags[id] = false;
    // Preserve pending choices from earlier succeeded clones (M1): a new
    // clone must not wipe them.
    emit(
      RepoCloneState(
        tasks: [...state.tasks, task],
        pendingChoice: state.pendingChoice,
      ),
    );
    _progressActivityCubit.start(
      ProgressActivity(
        id: id,
        kind: ProgressActivityKind.repoClone,
        // Raw repo name — the activity UI localizes kind labels (Task 1).
        title: request.dirName,
        phase: ProgressActivityPhase.running,
        cancellable: true,
        createdAt: now,
        updatedAt: now,
      ),
      onCancelRequested: () {
        _cancelFlags[id] = true;
      },
    );
    unawaited(_run(task, request));
  }

  /// Remove a succeeded task from the new-vs-add choice list only.
  void dismissChoice(String taskId) {
    if (!state.pendingChoice.any((task) => task.id == taskId)) return;
    emit(
      RepoCloneState(
        tasks: state.tasks,
        pendingChoice: [
          for (final task in state.pendingChoice)
            if (task.id != taskId) task,
        ],
      ),
    );
  }

  RepoCloneTask? taskById(String taskId) {
    for (final task in state.tasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }

  Future<void> _run(RepoCloneTask task, RepoCloneRequest request) async {
    // startClone is fire-and-forget: nothing may escape this future. If the
    // cubit closed mid-clone (page dispose) the state emit is skipped but the
    // app-scoped progress activity is still completed below so the
    // notification history and activity lifecycle finish cleanly.
    try {
      await _runGuarded(task, request);
    } catch (error, stackTrace) {
      appLogger.d(
        '[RepoClone] task ${task.id} unexpected failure: $error\n$stackTrace',
      );
      try {
        _progressActivityCubit.complete(
          task.id,
          outcome: ProgressActivityPhase.failed,
          errorMessage: error.toString(),
          historyTitle: 'Clone failed',
          historyMessage: error.toString(),
        );
      } catch (completeError) {
        appLogger.d(
          '[RepoClone] task ${task.id} activity completion failed: '
          '$completeError',
        );
      }
    }
  }

  Future<void> _runGuarded(RepoCloneTask task, RepoCloneRequest request) async {
    final gateway = _service;
    if (gateway == null) {
      _finish(
        task,
        RepoCloneResult(
          outcome: RepoCloneOutcome.failed,
          destPath: task.destPath,
          errorDetail: 'no clone service configured',
        ),
      );
      return;
    }
    final RepoCloneResult result;
    try {
      result = await gateway.clone(
        request,
        onProgress: (progress) {
          _progressActivityCubit.update(
            task.id,
            fraction: progress.fraction,
            subtitle: progress.subtitle,
          );
        },
        isCancelled: () => _cancelFlags[task.id] ?? false,
      );
    } catch (error) {
      // startClone is fire-and-forget: gateway failures become state.
      appLogger.d('[RepoClone] task ${task.id} crashed: $error');
      _finish(
        task,
        RepoCloneResult(
          outcome: RepoCloneOutcome.failed,
          destPath: task.destPath,
          errorDetail: error.toString(),
        ),
      );
      return;
    }

    // Second best-effort cleanup pass (the service already did its own).
    // Pre-check markers (`dest-exists` / `git-missing`) may point at
    // pre-existing user directories; a raced "already exists" git failure
    // means someone else created the dir after our pre-check — both must be
    // preserved.
    if (result.outcome != RepoCloneOutcome.succeeded &&
        !_precheckMarkers.contains(result.errorDetail) &&
        !(result.errorDetail?.contains(_alreadyExistsNeedle) ?? false)) {
      await _cleanupPartial(task.targetId, result.destPath);
    }

    _finish(task, result);
  }

  void _finish(RepoCloneTask task, RepoCloneResult result) {
    final phase = switch (result.outcome) {
      RepoCloneOutcome.succeeded => RepoCloneTaskPhase.succeeded,
      RepoCloneOutcome.failed => RepoCloneTaskPhase.failed,
      RepoCloneOutcome.cancelled => RepoCloneTaskPhase.cancelled,
    };
    final finished = task.copyWith(
      destPath: result.destPath,
      phase: phase,
      errorDetail: result.errorDetail,
    );
    _emitFinished(
      finished,
      appendToChoice: phase == RepoCloneTaskPhase.succeeded,
    );

    // The activity cubit is app-scoped and outlives this cubit: complete it
    // even when we are closed (the emit above was skipped) so the
    // notification history and activity lifecycle finish cleanly.
    final friendlyDetail = _friendlyErrorDetail(result.errorDetail);
    _progressActivityCubit.complete(
      task.id,
      outcome: switch (result.outcome) {
        RepoCloneOutcome.succeeded => ProgressActivityPhase.succeeded,
        RepoCloneOutcome.failed => ProgressActivityPhase.failed,
        RepoCloneOutcome.cancelled => ProgressActivityPhase.cancelled,
      },
      errorMessage: friendlyDetail,
      historyTitle: switch (result.outcome) {
        RepoCloneOutcome.succeeded => 'Cloned ${task.dirName}',
        RepoCloneOutcome.failed => 'Clone failed',
        RepoCloneOutcome.cancelled => 'Clone cancelled',
      },
      historyMessage: switch (result.outcome) {
        RepoCloneOutcome.succeeded => result.destPath,
        RepoCloneOutcome.failed => friendlyDetail ?? result.destPath,
        RepoCloneOutcome.cancelled => result.destPath,
      },
    );

    _cancelFlags.remove(task.id);
  }

  /// Internal markers → plain-English history strings (I1): raw markers must
  /// never reach the notification history. Everything else (stderr tails,
  /// spawn errors) is already user-legible and passes through verbatim.
  String? _friendlyErrorDetail(String? errorDetail) {
    if (errorDetail == null) return null;
    return _markerHistoryMessages[errorDetail] ?? errorDetail;
  }

  void _emitFinished(RepoCloneTask finished, {required bool appendToChoice}) {
    // Closed cubit: bloc throws StateError on post-close emits. The caller
    // still completes the progress activity; only the state mirror is lost.
    if (isClosed) return;
    emit(
      RepoCloneState(
        tasks: [
          for (final task in state.tasks)
            if (task.id == finished.id) finished else task,
        ],
        pendingChoice: appendToChoice
            ? [...state.pendingChoice, finished]
            : state.pendingChoice,
      ),
    );
  }

  Future<void> _cleanupPartial(String targetId, String destPath) async {
    final cleanupFs = _cleanupFs;
    if (cleanupFs == null) return;
    try {
      final fs = await cleanupFs(targetId);
      final stat = await fs.stat(destPath);
      if (stat.exists) {
        await fs.removeRecursive(destPath);
        appLogger.d('[RepoClone] second-pass cleanup removed $destPath');
      }
    } catch (error) {
      // Log-only: the service's internal pass already ran best-effort.
      appLogger.d(
        '[RepoClone] second-pass cleanup failed for $destPath: $error',
      );
    }
  }

  String _provisionalDestPath(String parentDir, String dirName) {
    if (parentDir.isEmpty) return dirName;
    if (parentDir.endsWith('/') || parentDir.endsWith('\\')) {
      return '$parentDir$dirName';
    }
    return '$parentDir/$dirName';
  }

  @override
  Future<void> close() {
    // Closing implies cancel-requested for every in-flight clone: their
    // `isCancelled` polls keep reporting true (and a cancel requested before
    // close is not forgotten). The map dies with the object anyway.
    for (final id in _cancelFlags.keys.toList()) {
      _cancelFlags[id] = true;
    }
    return super.close();
  }
}
