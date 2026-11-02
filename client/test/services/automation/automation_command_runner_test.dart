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
  RunTargetPlan? capturedPlan;

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
    capturedPlan = plan;
    return ProcessRunResult(exitCode: Future<int>.value(0), stop: () async {});
  }
}

class _HangingStartExecutor extends ProcessRunExecutor {
  @override
  Future<ProcessRunResult> start({
    required String sessionId,
    required String command,
    required List<String> args,
    required RunTargetPlan plan,
    Map<String, String>? env,
    bool shell = false,
    required void Function(ProcessRunOutput output) onOutput,
  }) {
    return Completer<ProcessRunResult>().future;
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

  test('runs local POSIX commands through sh -c', () async {
    final executor = _RecordingExecutor();
    final runner = HostAutomationCommandRunner(
      workspaceById: (_) => _workspace([const WorkspaceFolder(path: '/repo')]),
      resolver: RunTargetResolver(homeTarget: () => RuntimeTarget.local()),
      executor: executor,
      isWindows: () => false,
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

  test('runs local Windows commands through cmd.exe /c', () async {
    final executor = _RecordingExecutor();
    final runner = HostAutomationCommandRunner(
      workspaceById: (_) => _workspace([const WorkspaceFolder(path: '/repo')]),
      resolver: RunTargetResolver(homeTarget: () => RuntimeTarget.local()),
      executor: executor,
      isWindows: () => true,
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(
        workspaceId: 'ws1',
        command: 'npm ci && npm run build',
      ),
    );

    expect(outcome.exitCode, 0);
    expect(executor.capturedCommand, 'cmd.exe');
    expect(executor.capturedArgs, ['/c', 'npm ci && npm run build']);
    expect(executor.capturedShell, isFalse);
  });

  test('WSL argv keeps the command line as one sh -c argument', () async {
    String? spawnedExecutable;
    List<String>? spawnedArguments;
    final runner = HostAutomationCommandRunner(
      workspaceById: (_) => _workspace([const WorkspaceFolder(path: '/repo')]),
      resolver: _FixedPlanResolver(
        RunTargetPlan(
          workingDirectory: '/repo',
          runtimeTarget: RuntimeTarget.wsl('Ubuntu'),
          targetId: 'wsl:Ubuntu',
          useWslPaths: true,
        ),
      ),
      executor: ProcessRunExecutor(
        spawner:
            ({
              required executable,
              required arguments,
              required workingDirectory,
              environment,
              runInShell = false,
              includeParentEnvironment = true,
            }) async {
              spawnedExecutable = executable;
              spawnedArguments = arguments;
              return _FakeHandle();
            },
      ),
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(
        workspaceId: 'ws1',
        command: 'npm ci && npm run build',
      ),
    );

    expect(outcome.exitCode, 0);
    expect(spawnedExecutable, 'wsl.exe');
    expect(spawnedArguments, [
      '-d',
      'Ubuntu',
      '--cd',
      '/repo',
      'sh',
      '-c',
      'npm ci && npm run build',
    ]);
  });

  test('SSH argv keeps the command line as one sh -c argument', () async {
    String? capturedShellCommand;
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
      executor: ProcessRunExecutor(
        sshSpawner: ({required sshProfileId, required shellCommand}) async {
          capturedShellCommand = shellCommand;
          return _FakeHandle();
        },
      ),
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(
        workspaceId: 'ws1',
        command: 'npm ci && npm run build',
      ),
    );

    expect(outcome.exitCode, 0);
    expect(
      capturedShellCommand,
      "cd '/repo' && 'sh' '-c' 'npm ci && npm run build'",
    );
  });

  test('reports an SSH exit-code failure as target_unreachable', () async {
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
      executor: ProcessRunExecutor(
        sshSpawner: ({required sshProfileId, required shellCommand}) async =>
            _ErrorExitHandle(),
      ),
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(workspaceId: 'ws1', command: 'make'),
    );

    expect(outcome.error, 'target_unreachable');
    expect(outcome.status, AutomationRunStatus.dispatchFailed);
  });

  test('reports a local exit-code failure as spawn_failed', () async {
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
            }) async => _ErrorExitHandle(),
      ),
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(workspaceId: 'ws1', command: 'make'),
    );

    expect(outcome.error, 'spawn_failed');
  });

  test('times out when start() never returns so the queue can drain', () async {
    final runner = HostAutomationCommandRunner(
      workspaceById: (_) => _workspace([const WorkspaceFolder(path: '/repo')]),
      resolver: RunTargetResolver(homeTarget: () => RuntimeTarget.local()),
      executor: _HangingStartExecutor(),
      timeoutGrace: const Duration(milliseconds: 50),
    );

    final outcome = await runner
        .run(
          const AutomationCommandRequest(
            workspaceId: 'ws1',
            command: 'sleep 999',
            timeoutSeconds: 1,
          ),
        )
        .timeout(const Duration(seconds: 5));

    expect(outcome.timedOut, isTrue);
    expect(outcome.status, AutomationRunStatus.timedOut);
  });

  test('picks the longest matching folder path', () async {
    final executor = _RecordingExecutor();
    final runner = HostAutomationCommandRunner(
      workspaceById: (_) => _workspace(const [
        WorkspaceFolder(path: '/repo'),
        WorkspaceFolder(path: '/repo/svc', targetId: 'ssh:profile-2'),
      ]),
      resolver: RunTargetResolver(homeTarget: () => RuntimeTarget.local()),
      executor: executor,
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(
        workspaceId: 'ws1',
        command: 'make',
        workingDirectoryPath: '/repo/svc',
      ),
    );

    expect(outcome.exitCode, 0);
    expect(executor.capturedPlan?.targetId, 'ssh:profile-2');
    expect(executor.capturedPlan?.workingDirectory, '/repo/svc');
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

/// A transport that dropped before reporting an exit status (SSH disconnect).
class _ErrorExitHandle implements ProcessRunHandle {
  @override
  Future<int> get exitCode => Future<int>.error(StateError('disconnected'));

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  void kill() {}
}
