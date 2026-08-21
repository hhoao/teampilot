import 'dart:async';

import '../../cubits/progress_activity_cubit.dart';
import '../../models/install_job/install_cancel_policy.dart';
import '../../models/install_job/install_job_cancelled_exception.dart';
import '../../models/install_job/install_job_context.dart';
import '../../models/install_job/install_job_key.dart';
import '../../models/install_job/install_job_snapshot.dart';
import '../../models/install_job/install_job_spec.dart';
import '../../models/progress_activity.dart';
import 'install_job_activity_kind.dart';
import 'install_job_runner_registry.dart';

final class InstallJobRegistry {
  InstallJobRegistry({
    required ProgressActivityCubit progressCubit,
    InstallJobRunnerRegistry? runnerRegistry,
  }) : _progressCubit = progressCubit,
       _runnerRegistry = runnerRegistry;

  final ProgressActivityCubit _progressCubit;
  final InstallJobRunnerRegistry? _runnerRegistry;

  InstallJobRunnerRegistry? get runnerRegistry => _runnerRegistry;
  final Map<InstallJobKey, _ActiveJob> _active = {};
  final Map<InstallJobKey, StreamController<InstallJobSnapshot>> _watchers =
      {};

  Future<T> enqueue<T>(InstallJobSpec<T> spec) {
    final existing = _active[spec.key];
    if (existing != null && !existing.isTerminal) {
      return existing.future.then((value) => value as T);
    }

    final completer = Completer<Object?>();
    final activityId = spec.key.activityId;
    final ctx = InstallJobContext(
      reportPhase: (label, {detail, fraction}) {
        final subtitle = detail == null ? label : '$label — $detail';
        _progressCubit.update(
          activityId,
          subtitle: subtitle,
          fraction: fraction,
        );
        _emitSnapshot(
          spec.key,
          InstallJobPhase.running,
          subtitle: subtitle,
          fraction: fraction,
        );
      },
      reportItems: ({required completed, required total}) {
        final fraction = total > 0 ? completed / total : null;
        _progressCubit.update(
          activityId,
          completedItems: completed,
          totalItems: total,
          fraction: fraction,
        );
        _emitSnapshot(
          spec.key,
          InstallJobPhase.running,
          fraction: fraction,
        );
      },
    );

    final job = _ActiveJob(
      key: spec.key,
      ctx: ctx,
      completer: completer,
      cancelPolicy: spec.cancelPolicy,
      historyTitle: spec.historyTitle,
      run: (ctx) => spec.run(ctx),
      onSucceeded: spec.onSucceeded == null
          ? null
          : (result) async {
              await (spec.onSucceeded as dynamic)(result);
            },
      onFailed: spec.onFailed,
      historyMessageFor: spec.historyMessageFor == null
          ? null
          : (result) => (spec.historyMessageFor as dynamic)(result) as String?,
    );
    _active[spec.key] = job;

    _progressCubit.startForInstallJob(
      jobKey: spec.key,
      title: spec.title,
      subtitle: spec.subtitle,
      workspaceId: spec.workspaceId,
      kind: activityKindForInstall(spec.key.kind),
      onCancelRequested: () => _handleCancelRequest(spec.key),
    );
    _emitSnapshot(
      spec.key,
      InstallJobPhase.running,
      subtitle: spec.subtitle,
    );

    unawaited(_runJob(job));
    return completer.future.then((value) => value as T);
  }

  bool isRunning(InstallJobKey key) {
    final job = _active[key];
    return job != null && !job.isTerminal;
  }

  void requestCancel(InstallJobKey key) {
    _handleCancelRequest(key);
    _progressCubit.requestCancel(key.activityId);
  }

  Stream<InstallJobSnapshot> watch(InstallJobKey key) {
    return _controllerFor(key).stream;
  }

  void dispose() {
    for (final controller in _watchers.values) {
      unawaited(controller.close());
    }
    _watchers.clear();
  }

  void _handleCancelRequest(InstallJobKey key) {
    final job = _active[key];
    if (job == null || job.isTerminal) return;

    _emitSnapshot(key, InstallJobPhase.cancelling);

    if (job.cancelPolicy == InstallCancelPolicy.forceKill) {
      unawaited(job.ctx.forceKill());
      return;
    }
    job.ctx.requestCancel();
  }

  Future<void> _runJob(_ActiveJob job) async {
    final activityId = job.key.activityId;
    try {
      final result = await job.run(job.ctx);
      if (job.ctx.isCancelled) {
        await _completeCancelled(job);
        return;
      }

      await job.onSucceeded?.call(result);
      _progressCubit.complete(
        activityId,
        outcome: ProgressActivityPhase.succeeded,
        historyTitle: job.historyTitle,
        historyMessage: job.historyMessageFor?.call(result),
      );
      _emitSnapshot(job.key, InstallJobPhase.succeeded);
      job.markTerminal();
      job.completer.complete(result);
    } on InstallJobCancelledException {
      await _completeCancelled(job);
    } catch (error, stackTrace) {
      await job.onFailed?.call(error);
      _progressCubit.complete(
        activityId,
        outcome: ProgressActivityPhase.failed,
        errorMessage: error.toString(),
        historyTitle: job.historyTitle,
      );
      _emitSnapshot(job.key, InstallJobPhase.failed);
      job.markTerminal();
      job.completer.completeError(error, stackTrace);
    } finally {
      _active.remove(job.key);
    }
  }

  Future<void> _completeCancelled(_ActiveJob job) async {
    _progressCubit.complete(
      job.key.activityId,
      outcome: ProgressActivityPhase.cancelled,
      historyTitle: job.historyTitle,
    );
    _emitSnapshot(job.key, InstallJobPhase.cancelled);
    job.markTerminal();
    job.completer.completeError(InstallJobCancelledException(job.key));
  }

  StreamController<InstallJobSnapshot> _controllerFor(InstallJobKey key) {
    return _watchers.putIfAbsent(
      key,
      () => StreamController<InstallJobSnapshot>.broadcast(),
    );
  }

  void _emitSnapshot(
    InstallJobKey key,
    InstallJobPhase phase, {
    String? subtitle,
    double? fraction,
  }) {
    final controller = _watchers[key];
    if (controller == null || controller.isClosed) return;
    controller.add(
      InstallJobSnapshot(
        key: key,
        phase: phase,
        subtitle: subtitle,
        fraction: fraction,
      ),
    );
  }
}

final class _ActiveJob {
  _ActiveJob({
    required this.key,
    required this.ctx,
    required this.completer,
    required this.cancelPolicy,
    required this.historyTitle,
    required this.run,
    required this.onSucceeded,
    required this.onFailed,
    required this.historyMessageFor,
  });

  final InstallJobKey key;
  final InstallJobContext ctx;
  final Completer<Object?> completer;
  final InstallCancelPolicy cancelPolicy;
  final String? historyTitle;
  final Future<Object?> Function(InstallJobContext ctx) run;
  final FutureOr<void> Function(Object? result)? onSucceeded;
  final FutureOr<void> Function(Object error)? onFailed;
  final String? Function(Object? result)? historyMessageFor;
  bool _terminal = false;

  Future<Object?> get future => completer.future;

  bool get isTerminal => _terminal;

  void markTerminal() => _terminal = true;
}
