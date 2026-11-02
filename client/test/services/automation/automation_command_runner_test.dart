import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/automation/automation_command_runner.dart';
import 'package:teampilot/services/host/process_run_handle.dart';
import 'package:teampilot/services/run/process_run_executor.dart';
import 'package:teampilot/services/run/run_target_resolver.dart';

class _FakeHandle implements ProcessRunHandle {
  _FakeHandle({
    this.exit = 0,
    this.stdoutChunks = const [],
    this.stderrChunks = const [],
  });

  final int exit;
  final List<String> stdoutChunks;
  final List<String> stderrChunks;
  bool killed = false;

  @override
  Future<int> get exitCode async => exit;

  @override
  Stream<List<int>> get stdout =>
      Stream.fromIterable(stdoutChunks.map((c) => c.codeUnits));

  @override
  Stream<List<int>> get stderr =>
      Stream.fromIterable(stderrChunks.map((c) => c.codeUnits));

  @override
  void kill() => killed = true;
}

Workspace _workspace(List<WorkspaceFolder> folders) => Workspace(
  workspaceId: 'ws1',
  folders: folders,
  display: 'ws1',
  defaultProfileId: '',
  createdAt: 0,
);

class _RecordingExecutor extends ProcessRunExecutor {
  String? capturedCommand;
  List<String>? capturedArgs;
  bool? capturedShell;

  @override
  Future<ProcessRunResult> start({
    required String sessionId,
    required String command,
    required List<String> args,
    required RunTargetPlan plan,
    Map<String, String>? env,
    bool shell = false,
    required void Function(ProcessRunOutput output) onOutput,
  }) async {
    capturedCommand = command;
    capturedArgs = args;
    capturedShell = shell;
    return ProcessRunResult(exitCode: Future<int>.value(0), stop: () async {});
  }
}

class _FixedPlanResolver extends RunTargetResolver {
  _FixedPlanResolver(this.plan)
    : super(homeTarget: () => RuntimeTarget.local());

  final RunTargetPlan plan;

  @override
  RunTargetPlan resolve({
    required WorkspaceFolder owner,
    String? cwd,
    Map<String, String> env = const {},
  }) => plan;
}

void main() {
  test('captures exit code and output tail', () async {
    final runner = HostAutomationCommandRunner(
      workspaceById: (_) => _workspace([const WorkspaceFolder(path: '/repo')]),
      resolver: RunTargetResolver(homeTarget: () => RuntimeTarget.local()),
      executor: ProcessRunExecutor(
        spawner:
            ({
              required executable,
              required arguments,
              required workingDirectory,
              environment,
              runInShell = false,
              includeParentEnvironment = true,
            }) async => _FakeHandle(
              exit: 2,
              stdoutChunks: const ['built ok'],
              stderrChunks: const ['boom'],
            ),
      ),
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(
        workspaceId: 'ws1',
        command: 'make',
        workingDirectoryPath: '/repo',
      ),
    );

    expect(outcome.exitCode, 2);
    expect(outcome.stdoutTail, 'built ok');
    expect(outcome.stderrTail, 'boom');
    expect(outcome.timedOut, isFalse);
    expect(outcome.status, AutomationRunStatus.failed);
  });

  test('kills the process on timeout', () async {
    final handle = _HungHandle();
    final runner = HostAutomationCommandRunner(
      workspaceById: (_) => _workspace([const WorkspaceFolder(path: '/repo')]),
      resolver: RunTargetResolver(homeTarget: () => RuntimeTarget.local()),
      executor: ProcessRunExecutor(
        spawner:
            ({
              required executable,
              required arguments,
              required workingDirectory,
              environment,
              runInShell = false,
              includeParentEnvironment = true,
            }) async => handle,
      ),
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(
        workspaceId: 'ws1',
        command: 'sleep 999',
        timeoutSeconds: 1,
      ),
    );

    expect(outcome.timedOut, isTrue);
    expect(outcome.status, AutomationRunStatus.timedOut);
    expect(handle.killed, isTrue);
  });

  test('waits for late output before reading the tail', () async {
    final runner = HostAutomationCommandRunner(
      workspaceById: (_) => _workspace([const WorkspaceFolder(path: '/repo')]),
      resolver: RunTargetResolver(homeTarget: () => RuntimeTarget.local()),
      executor: ProcessRunExecutor(
        spawner:
            ({
              required executable,
              required arguments,
              required workingDirectory,
              environment,
              runInShell = false,
              includeParentEnvironment = true,
            }) async => _DelayedOutputHandle(),
      ),
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(workspaceId: 'ws1', command: 'make'),
    );

    expect(outcome.exitCode, 3);
    expect(outcome.stdoutTail, 'late error line');
  });

  test('runs SSH commands through sh -c', () async {
    final executor = _RecordingExecutor();
    final runner = HostAutomationCommandRunner(
      workspaceById: (_) => _workspace([const WorkspaceFolder(path: '/repo')]),
      resolver: _FixedPlanResolver(
        RunTargetPlan(
          workingDirectory: '/repo',
          runtimeTarget: RuntimeTarget.ssh('profile-1', label: 'server'),
          targetId: 'ssh:profile-1',
          useWslPaths: false,
        ),
      ),
      executor: executor,
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(
        workspaceId: 'ws1',
        command: 'bash scripts/backup.sh',
      ),
    );

    expect(outcome.exitCode, 0);
    expect(executor.capturedCommand, 'sh');
    expect(executor.capturedArgs, ['-c', 'bash scripts/backup.sh']);
    expect(executor.capturedShell, isFalse);
  });

  test('runs local commands as a raw shell line', () async {
    final executor = _RecordingExecutor();
    final runner = HostAutomationCommandRunner(
      workspaceById: (_) => _workspace([const WorkspaceFolder(path: '/repo')]),
      resolver: RunTargetResolver(homeTarget: () => RuntimeTarget.local()),
      executor: executor,
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(
        workspaceId: 'ws1',
        command: 'bash scripts/backup.sh',
      ),
    );

    expect(outcome.exitCode, 0);
    expect(executor.capturedCommand, 'bash scripts/backup.sh');
    expect(executor.capturedArgs, isEmpty);
    expect(executor.capturedShell, isTrue);
  });

  test('rejects a working directory outside the workspace', () async {
    final runner = HostAutomationCommandRunner(
      workspaceById: (_) => _workspace([const WorkspaceFolder(path: '/repo')]),
      resolver: RunTargetResolver(homeTarget: () => RuntimeTarget.local()),
      executor: ProcessRunExecutor(spawner: _unexpectedSpawner),
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(
        workspaceId: 'ws1',
        command: 'make',
        workingDirectoryPath: '/elsewhere',
      ),
    );

    expect(outcome.error, 'working_directory_invalid');
    expect(outcome.status, AutomationRunStatus.dispatchFailed);
  });

  test('reports a missing workspace', () async {
    final runner = HostAutomationCommandRunner(
      workspaceById: (_) => null,
      resolver: RunTargetResolver(homeTarget: () => RuntimeTarget.local()),
      executor: ProcessRunExecutor(spawner: _unexpectedSpawner),
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(workspaceId: 'ws1', command: 'make'),
    );

    expect(outcome.error, 'workspace_unavailable');
  });
}

Future<ProcessRunHandle> _unexpectedSpawner({
  required String executable,
  required List<String> arguments,
  required String workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  bool includeParentEnvironment = true,
}) {
  throw StateError('spawner must not be called');
}

/// Exits immediately; its stdout chunk arrives only afterwards.
class _DelayedOutputHandle implements ProcessRunHandle {
  @override
  Future<int> get exitCode async => 3;

  @override
  Stream<List<int>> get stdout => Stream<List<int>>.fromFuture(
    Future<List<int>>.delayed(
      const Duration(milliseconds: 50),
      () => 'late error line'.codeUnits,
    ),
  );

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  void kill() {}
}

class _HungHandle implements ProcessRunHandle {
  final Completer<int> _exit = Completer<int>();
  bool killed = false;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  void kill() {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(-1);
  }
}
