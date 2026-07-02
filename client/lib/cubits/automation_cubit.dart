import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/automation.dart';
import '../repositories/automation_repository.dart';
import '../services/automation/automation_schedule_calculator.dart';
import '../services/automation/automation_scheduler.dart';
import 'automation_state.dart';

int _automationCubitDefaultNowMs() => DateTime.now().millisecondsSinceEpoch;

class AutomationCubit extends Cubit<AutomationState> {
  AutomationCubit({
    required AutomationRepository repository,
    required AutomationScheduler scheduler,
    required AutomationScheduleCalculator scheduleCalculator,
    int Function()? nowMs,
  })  : _repository = repository,
        _scheduler = scheduler,
        _scheduleCalculator = scheduleCalculator,
        _nowMs = nowMs ?? _automationCubitDefaultNowMs,
        super(const AutomationState()) {
    _scheduler.onAfterTick = _handleSchedulerTick;
  }

  final AutomationRepository _repository;
  final AutomationScheduler _scheduler;
  final AutomationScheduleCalculator _scheduleCalculator;
  final int Function() _nowMs;

  Future<void> load() async {
    emit(state.copyWith(status: AutomationLoadStatus.loading, clearError: true));
    try {
      final automations = await _repository.listAll();
      final runsByAutomationId = await _loadRunsByAutomation(automations);
      emit(
        state.copyWith(
          automations: automations,
          runsByAutomationId: runsByAutomationId,
          status: AutomationLoadStatus.ready,
        ),
      );
    } on Object catch (error) {
      emit(
        state.copyWith(
          status: AutomationLoadStatus.error,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> loadForWorkspace(String workspaceId) async {
    emit(
      state.copyWith(
        status: AutomationLoadStatus.loading,
        filterWorkspaceId: workspaceId,
        clearFilterSessionId: true,
        clearError: true,
      ),
    );
    try {
      final automations = await _repository.listForWorkspace(workspaceId);
      final runsByAutomationId = await _loadRunsByAutomation(automations);
      emit(
        state.copyWith(
          automations: automations,
          runsByAutomationId: runsByAutomationId,
          status: AutomationLoadStatus.ready,
        ),
      );
    } on Object catch (error) {
      emit(
        state.copyWith(
          status: AutomationLoadStatus.error,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> save(Automation automation) async {
    automation.validate();
    final now = _nowMs();
    var next = automation.copyWith(
      createdAtMs: automation.createdAtMs > 0 ? automation.createdAtMs : now,
      updatedAtMs: now,
    );
    if (next.enabled) {
      if (next.isRunLimitReached) {
        next = next.copyWith(enabled: false, clearNextRunAtMs: true);
      } else {
        next = next.copyWith(
          nextRunAtMs: _scheduleCalculator.computeNextRunAtMs(
            next,
            afterMs: now,
          ),
        );
      }
    } else {
      next = next.copyWith(clearNextRunAtMs: true);
    }
    await _repository.upsert(next);
    await _reloadPreservingFilters();
  }

  Future<void> delete(String workspaceId, String automationId) async {
    await _repository.delete(workspaceId, automationId);
    await _reloadPreservingFilters();
  }

  Future<void> toggleEnabled(String workspaceId, String automationId) async {
    final automations = await _repository.listForWorkspace(workspaceId);
    final automation = automations.where((a) => a.id == automationId).firstOrNull;
    if (automation == null) return;
    final now = _nowMs();
    final enabled = !automation.enabled;
    if (enabled && automation.isRunLimitReached) return;
    var next = automation.copyWith(enabled: enabled, updatedAtMs: now);
    if (enabled) {
      next = next.copyWith(
        nextRunAtMs: _scheduleCalculator.computeNextRunAtMs(next, afterMs: now),
      );
    } else {
      next = next.copyWith(clearNextRunAtMs: true);
    }
    await _repository.upsert(next);
    await _reloadPreservingFilters();
  }

  Future<void> runNow(String workspaceId, String automationId) async {
    await _scheduler.runNow(workspaceId, automationId);
    await reloadPreservingFilters();
  }

  Future<void> reloadPreservingFilters() => _reloadPreservingFilters();

  Future<void> _reloadPreservingFilters() async {
    final workspaceId = state.filterWorkspaceId;
    if (workspaceId != null && workspaceId.isNotEmpty) {
      await loadForWorkspace(workspaceId);
    } else {
      await load();
    }
  }

  Future<Map<String, List<AutomationRun>>> _loadRunsByAutomation(
    List<Automation> automations,
  ) async {
    if (automations.isEmpty) return const {};
    final byWorkspace = <String, List<Automation>>{};
    for (final automation in automations) {
      byWorkspace
          .putIfAbsent(automation.workspaceId, () => <Automation>[])
          .add(automation);
    }

    final runsByAutomationId = <String, List<AutomationRun>>{};
    for (final entry in byWorkspace.entries) {
      final runs = await _repository.runsForWorkspace(entry.key);
      final grouped = <String, List<AutomationRun>>{};
      for (final run in runs) {
        grouped.putIfAbsent(run.automationId, () => <AutomationRun>[]).add(run);
      }
      for (final automation in entry.value) {
        runsByAutomationId[automation.id] =
            grouped[automation.id] ?? const <AutomationRun>[];
      }
    }
    return runsByAutomationId;
  }

  void _handleSchedulerTick() {
    if (isClosed) return;
    unawaited(_reloadPreservingFilters());
  }
}
