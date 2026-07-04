import 'dart:async';

import 'package:collection/collection.dart';

import '../../models/automation.dart';
import '../../models/automation_tab_scope.dart';
import '../../repositories/automation_repository.dart';
import '../../utils/logger.dart';
import 'automation_dispatcher.dart';
import 'automation_schedule_calculator.dart';

int _automationSchedulerDefaultNowMs() => DateTime.now().millisecondsSinceEpoch;

class AutomationScheduler {
  AutomationScheduler({
    required AutomationRepository repository,
    required AutomationDispatcher dispatcher,
    required AutomationScheduleCalculator scheduleCalculator,
    Duration tickInterval = const Duration(seconds: 30),
    int Function()? nowMs,
  }) : _repository = repository,
       _dispatcher = dispatcher,
       _scheduleCalculator = scheduleCalculator,
       _tickInterval = tickInterval,
       _nowMs = nowMs ?? _automationSchedulerDefaultNowMs;

  final AutomationRepository _repository;
  final AutomationDispatcher _dispatcher;
  final AutomationScheduleCalculator _scheduleCalculator;
  final Duration _tickInterval;
  final int Function() _nowMs;
  void Function()? onAfterTick;

  Timer? _timer;
  Future<void> _operationQueue = Future<void>.value();
  bool _missedRunsProcessed = false;

  void start() {
    if (_timer != null) return;
    unawaited(_enqueue(_processMissedRuns));
    _timer = Timer.periodic(_tickInterval, (_) => unawaited(_enqueue(_tick)));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Waits until all enqueued scheduler work has finished.
  Future<void> waitForIdle() => _operationQueue;

  Future<void> runNow(AutomationTabScope scope, String automationId) {
    return _enqueue(() async {
      final automations = await _repository.listForTabScope(scope);
      final automation = automations
          .where((a) => a.id == automationId)
          .firstOrNull;
      if (automation == null || automation.isRunLimitReached) return;
      await _dispatchClaimed(automation, trigger: AutomationRunTrigger.manual);
      onAfterTick?.call();
    });
  }

  Future<void> _enqueue(Future<void> Function() work) {
    final next = _operationQueue.then((_) => work());
    _operationQueue = next.catchError((Object _, StackTrace __) {});
    return next;
  }

  Future<void> _tick() async {
    try {
      if (!_missedRunsProcessed) {
        await _processMissedRuns();
      }
      await _dispatchDueAutomations();
      onAfterTick?.call();
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[automations] scheduler tick failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _processMissedRuns() async {
    _missedRunsProcessed = true;
    final now = _nowMs();
    final automations = await _repository.listAll();
    for (final automation in automations) {
      if (!automation.enabled || automation.isRunLimitReached) continue;
      final dueAt = automation.nextRunAtMs;
      if (dueAt == null || dueAt >= now) continue;

      final graceMs = automation.missedRunGraceMinutes * 60 * 1000;
      if (now - dueAt <= graceMs) {
        await _dispatchClaimed(automation);
        continue;
      }

      final skippedRun = AutomationRun(
        id: '${automation.id}-missed-$dueAt',
        automationId: automation.id,
        workspaceId: automation.workspaceId,
        scheduledForMs: dueAt,
        status: AutomationRunStatus.skippedMissed,
        trigger: AutomationRunTrigger.scheduled,
        startedAtMs: now,
        completedAtMs: now,
        error: 'missed_run_grace_exceeded',
      );
      await _repository.upsertRun(automation.tabScope, skippedRun);
      final advanced = automation.copyWith(
        lastRunAtMs: now,
        nextRunAtMs: _scheduleCalculator.computeNextRunAtMs(
          automation,
          afterMs: now,
        ),
        updatedAtMs: now,
      );
      await _repository.upsert(advanced);
    }
  }

  Future<void> _dispatchDueAutomations() async {
    final now = _nowMs();
    final automations = await _repository.listAll();
    final due = automations
        .where(
          (a) =>
              a.enabled &&
              !a.isRunLimitReached &&
              a.nextRunAtMs != null &&
              a.nextRunAtMs! <= now,
        )
        .toList(growable: false);
    for (final automation in due) {
      await _dispatchClaimed(automation);
    }
  }

  Future<void> _dispatchClaimed(
    Automation automation, {
    AutomationRunTrigger trigger = AutomationRunTrigger.scheduled,
  }) async {
    if (automation.isRunLimitReached) return;
    final now = _nowMs();
    final claimed = automation.copyWith(
      nextRunAtMs: automation.enabled
          ? _scheduleCalculator.computeNextRunAtMs(automation, afterMs: now)
          : automation.nextRunAtMs,
      updatedAtMs: now,
    );
    await _repository.upsert(claimed);
    await _dispatcher.dispatch(automation, trigger: trigger);
  }
}
