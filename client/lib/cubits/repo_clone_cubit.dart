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

  /// Git stderr tail, or a stable marker (`dest-exists` / `git-missing`) —
  /// mapped to l10n by the UI, never localized here.
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

  /// Pre-check failures (`dest-exists` / `git-missing`): the destination may
  /// be a pre-existing user directory — the second cleanup pass must skip
  /// them (the service itself also never cleans those up).
  static const Set<String> _precheckMarkers = {'dest-exists', 'git-missing'};

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
    emit(RepoCloneState(tasks: [...state.tasks, task]));
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
    if (result.outcome != RepoCloneOutcome.succeeded &&
        !_precheckMarkers.contains(result.errorDetail)) {
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

    _progressActivityCubit.complete(
      task.id,
      outcome: switch (result.outcome) {
        RepoCloneOutcome.succeeded => ProgressActivityPhase.succeeded,
        RepoCloneOutcome.failed => ProgressActivityPhase.failed,
        RepoCloneOutcome.cancelled => ProgressActivityPhase.cancelled,
      },
      errorMessage: result.errorDetail,
      historyTitle: switch (phase) {
        RepoCloneTaskPhase.succeeded => 'Cloned ${task.dirName}',
        RepoCloneTaskPhase.failed => 'Clone failed',
        RepoCloneTaskPhase.cancelled => 'Clone cancelled',
        RepoCloneTaskPhase.cloning => 'Cloning ${task.dirName}',
      },
      historyMessage: switch (phase) {
        RepoCloneTaskPhase.succeeded => result.destPath,
        RepoCloneTaskPhase.failed => result.errorDetail ?? result.destPath,
        RepoCloneTaskPhase.cancelled => result.destPath,
        RepoCloneTaskPhase.cloning => result.destPath,
      },
    );

    _cancelFlags.remove(task.id);
  }

  void _emitFinished(RepoCloneTask finished, {required bool appendToChoice}) {
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
    _cancelFlags.clear();
    return super.close();
  }
}
