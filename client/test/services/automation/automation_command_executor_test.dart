import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/repositories/automation_repository.dart';
import 'package:teampilot/services/automation/automation_command_executor.dart';
import 'package:teampilot/services/automation/automation_command_runner.dart';
import 'package:teampilot/services/automation/automation_run_accounting.dart';
import 'package:teampilot/services/automation/automation_schedule_calculator.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('writes a completed run and advances the automation', () async {
    final env = await _TestEnv.build(
      const AutomationCommandOutcome(exitCode: 0, stdoutTail: 'ok'),
    );
    final run = await env.executor.enqueue(env.automation);

    expect(run!.status, AutomationRunStatus.completed);
    expect(run.exitCode, 0);
    expect(run.stdoutTail, 'ok');

    final stored = await env.repository.runsFor('ws1');
    expect(stored.single.status, AutomationRunStatus.completed);
    final automations = await env.repository.listForWorkspace('ws1');
    expect(automations.single.runCount, 1);
  });

  test('records skippedOverlap without advancing runCount', () async {
    final env = await _TestEnv.build(null);
    final first = env.executor.enqueue(env.automation);
    await env.runner.waitForStart();

    final second = await env.executor.enqueue(env.automation);
    expect(second!.status, AutomationRunStatus.skippedOverlap);

    env.runner.release();
    await first;
    final automations = await env.repository.listForWorkspace('ws1');
    expect(automations.single.runCount, 1);
  });

  test('runner failure records dispatchFailed and advances runCount', () async {
    final env = await _TestEnv.build(null, failOnRun: true);

    final run = await env.executor.enqueue(env.automation);

    expect(run!.status, AutomationRunStatus.dispatchFailed);
    expect(run.error, 'runner_failed');
    expect(run.completedAtMs, isNotNull);

    final stored = await env.repository.runsFor('ws1');
    expect(stored.single.status, AutomationRunStatus.dispatchFailed);
    expect(stored.single.error, 'runner_failed');
    final automations = await env.repository.listForWorkspace('ws1');
    expect(automations.single.runCount, 1);
  });
}

class _GatedRunner implements AutomationCommandRunner {
  _GatedRunner(this.outcome, {this.failOnRun = false});

  final AutomationCommandOutcome? outcome;
  final bool failOnRun;
  final Completer<void> _gate = Completer<void>();
  final Completer<void> _started = Completer<void>();

  Future<void> waitForStart() => _started.future;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<AutomationCommandOutcome> run(AutomationCommandRequest request) async {
    if (!_started.isCompleted) _started.complete();
    if (failOnRun) throw StateError('runner boom');
    if (outcome != null) return outcome!;
    await _gate.future;
    return const AutomationCommandOutcome(exitCode: 0);
  }
}

class _TestEnv {
  _TestEnv(this.repository, this.executor, this.runner, this.automation);

  final AutomationRepository repository;
  final AutomationCommandExecutor executor;
  final _GatedRunner runner;
  final Automation automation;

  static Future<_TestEnv> build(
    AutomationCommandOutcome? outcome, {
    bool failOnRun = false,
  }) async {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    final repository = AutomationRepository(
      fs: testHomeStorage.fs,
      layout: layout,
    );
    final automation = Automation(
      id: 'a1',
      name: 'nightly',
      action: AutomationAction.runCommand,
      workspaceId: 'ws1',
      command: 'echo hi',
      message: '',
      preset: AutomationSchedulePreset.daily,
      hourMinute: '02:00',
      timezone: 'Asia/Shanghai',
      dtstartMs: 0,
      createdAtMs: 0,
      updatedAtMs: 0,
    );
    await repository.upsert(automation);
    final runner = _GatedRunner(outcome, failOnRun: failOnRun);
    final executor = AutomationCommandExecutor(
      repository: repository,
      accounting: AutomationRunAccounting(AutomationScheduleCalculator()),
      runner: runner,
    );
    return _TestEnv(repository, executor, runner, automation);
  }
}
