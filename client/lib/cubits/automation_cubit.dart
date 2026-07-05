import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/automation.dart';
import '../models/automation_list_scope.dart';
import '../models/automation_tab_scope.dart';
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
  }) : _repository = repository,
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
    emit(
      state.copyWith(
        status: AutomationLoadStatus.loading,
        listScope: const AutomationListScope.all(),
        clearError: true,
      ),
    );
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
    final scope = AutomationListScope.workspace(workspaceId);
    emit(
      state.copyWith(
        status: AutomationLoadStatus.loading,
        listScope: scope,
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

  Future<void> loadForTabScope(
    AutomationTabScope tabScope, {
    String? sessionId,
  }) async {
    final scope = AutomationListScope.tab(tabScope, sessionId: sessionId);
    emit(
      state.copyWith(
        status: AutomationLoadStatus.loading,
        listScope: scope,
        clearError: true,
      ),
    );
    try {
      final automations = await _repository.listForTabScope(tabScope);
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
    await _reloadPreservingScope();
  }

  Future<void> delete(AutomationTabScope scope, String automationId) async {
    await _repository.delete(scope, automationId);
    await _reloadPreservingScope();
  }

  Future<void> toggleEnabled(
    AutomationTabScope scope,
    String automationId,
  ) async {
    final automations = await _repository.listForTabScope(scope);
    final automation = automations
        .where((a) => a.id == automationId)
        .firstOrNull;
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
    await _reloadPreservingScope();
  }

  Future<void> runNow(AutomationTabScope scope, String automationId) async {
    await _scheduler.runNow(scope, automationId);
    await reloadPreservingScope();
  }

  Future<void> reloadPreservingScope() => _reloadPreservingScope();

  Future<void> _reloadPreservingScope() async {
    final scope = state.listScope;
    if (scope == null) {
      await load();
      return;
    }
    if (scope.isWorkspace) {
      await loadForWorkspace(scope.workspaceId!);
      return;
    }
    if (scope.isTab) {
      await loadForTabScope(
        scope.tabScope!,
        sessionId: scope.sessionId,
      );
      return;
    }
    await load();
  }

  Future<Map<String, List<AutomationRun>>> _loadRunsByAutomation(
    List<Automation> automations,
  ) async {
    if (automations.isEmpty) return const {};
    final byScope = <AutomationTabScope, List<Automation>>{};
    for (final automation in automations) {
      byScope
          .putIfAbsent(automation.tabScope, () => <Automation>[])
          .add(automation);
    }

    final runsByAutomationId = <String, List<AutomationRun>>{};
    for (final entry in byScope.entries) {
      final runs = await _repository.runsForTabScope(entry.key);
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
    unawaited(_reloadPreservingScope());
  }
}
