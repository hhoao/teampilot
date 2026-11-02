import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../models/automation.dart';
import '../../repositories/automation_repository.dart';
import '../../utils/logging/logger.dart';
import 'automation_command_runner.dart';
import 'automation_run_accounting.dart';

int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

/// Serializes command runs, prevents overlapping runs of the same automation,
/// and records the outcome as an [AutomationRun].
class AutomationCommandExecutor {
  AutomationCommandExecutor({
    required AutomationRepository repository,
    required AutomationRunAccounting accounting,
    required AutomationCommandRunner runner,
    int Function()? nowMs,
    String Function()? newId,
    this.onAfterRun,
  }) : _repository = repository,
       _accounting = accounting,
       _runner = runner,
       _nowMs = nowMs ?? _defaultNowMs,
       _newId = newId ?? (() => const Uuid().v4());

  static const _uuid = Uuid();

  final AutomationRepository _repository;
  final AutomationRunAccounting _accounting;
  final AutomationCommandRunner _runner;
  final int Function() _nowMs;
  final String Function() _newId;
  final void Function()? onAfterRun;

  final Set<String> _running = <String>{};
  Future<void> _queue = Future<void>.value();

  bool isRunning(String automationId) => _running.contains(automationId);

  Future<void> waitForIdle() => _queue;

  Future<AutomationRun?> enqueue(
    Automation automation, {
    AutomationRunTrigger trigger = AutomationRunTrigger.scheduled,
  }) {
    if (_running.contains(automation.id)) {
      // Overlap bookkeeping touches the same `automations.json` as the
      // in-flight run's read-modify-write, so it must ride the same serial
      // queue instead of racing it.
      return _enqueueSerial(
        () => _recordOverlap(automation, trigger: trigger),
      );
    }
    _running.add(automation.id);
    final next = _queue.then((_) => _run(automation, trigger: trigger));
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next.whenComplete(() => _running.remove(automation.id));
  }

  Future<T> _enqueueSerial<T>(Future<T> Function() work) {
    final next = _queue.then((_) => work());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<AutomationRun> _recordOverlap(
    Automation automation, {
    required AutomationRunTrigger trigger,
  }) async {
    final now = _nowMs();
    final run = AutomationRun(
      id: _uuid.v4(),
      automationId: automation.id,
      workspaceId: automation.workspaceId,
      scheduledForMs: automation.nextRunAtMs ?? now,
      status: AutomationRunStatus.skippedOverlap,
      trigger: trigger,
      startedAtMs: now,
      completedAtMs: now,
    );
    await _repository.upsertRun(automation.workspaceId, run);
    onAfterRun?.call();
    return run;
  }

  Future<AutomationRun> _run(
    Automation automation, {
    required AutomationRunTrigger trigger,
  }) async {
    final startedAtMs = _nowMs();
    final pending = AutomationRun(
      id: _newId(),
      automationId: automation.id,
      workspaceId: automation.workspaceId,
      scheduledForMs: automation.nextRunAtMs ?? startedAtMs,
      status: AutomationRunStatus.dispatching,
      trigger: trigger,
      startedAtMs: startedAtMs,
    );
    await _repository.upsertRun(automation.workspaceId, pending);

    final request = AutomationCommandRequest(
      workspaceId: automation.workspaceId,
      command: automation.command ?? '',
      workingDirectoryPath: automation.workingDirectoryPath,
      timeoutSeconds: automation.timeoutSeconds,
    );
    AutomationCommandOutcome outcome;
    try {
      outcome = await _runner.run(request);
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[automations] command runner failed for ${automation.id}: $error',
        error: error,
        stackTrace: stackTrace,
      );
      outcome = const AutomationCommandOutcome(error: 'runner_failed');
    }
    final finishedAtMs = _nowMs();
    final finished = pending.copyWith(
      status: outcome.status,
      exitCode: outcome.exitCode,
      clearExitCode: outcome.exitCode == null,
      stdoutTail: outcome.stdoutTail,
      stderrTail: outcome.stderrTail,
      outputTruncated: outcome.truncated,
      durationMs: outcome.durationMs,
      error: outcome.error,
      clearError: outcome.error == null,
      completedAtMs: finishedAtMs,
    );
    await _repository.upsertRun(automation.workspaceId, finished);

    // Re-read the row: a long run may overlap a user edit or a disable, and
    // advancing the snapshot captured at enqueue would revert it.
    final current = await _currentAutomation(automation);
    if (current == null) {
      // The automation was deleted while the command ran. Do not resurrect
      // it; drop the run so history does not reference a dead automation.
      await _repository.deleteRun(automation.workspaceId, finished.id);
      onAfterRun?.call();
      return finished;
    }
    var advanced = _accounting.advance(
      automation: current,
      lastRunAtMs: startedAtMs,
      nowMs: finishedAtMs,
    );
    // The scheduler already claimed the next slot before the run began.
    // Recomputing from the start time can rewrite it to an earlier slot that
    // is already due, firing a duplicate run.
    final claimedNextRunAtMs = current.nextRunAtMs;
    if (advanced.enabled &&
        claimedNextRunAtMs != null &&
        advanced.nextRunAtMs != null &&
        claimedNextRunAtMs > advanced.nextRunAtMs!) {
      advanced = advanced.copyWith(nextRunAtMs: claimedNextRunAtMs);
    }
    await _repository.upsert(advanced);
    onAfterRun?.call();
    return finished;
  }

  Future<Automation?> _currentAutomation(Automation fallback) async {
    final rows = await _repository.listForWorkspace(fallback.workspaceId);
    for (final row in rows) {
      if (row.id == fallback.id) return row;
    }
    return null;
  }
}
