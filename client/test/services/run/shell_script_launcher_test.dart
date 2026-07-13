import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/models/run/run_ui_intent.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/host/host_interactive_shell.dart';
import 'package:teampilot/services/run/process_run_executor.dart';
import 'package:teampilot/services/run/shell_script_launcher.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
import 'package:teampilot/services/terminal/workspace_shell_connector.dart';
import 'package:teampilot/services/terminal/workspace_terminal_connect_coordinator.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';
import 'package:teampilot/services/terminal/workspace_terminal_run_service.dart';
import 'package:teampilot/services/terminal/workspace_terminal_session_ops.dart';

const _folder = WorkspaceFolder(path: '/proj');

OwnedLaunchConfiguration _owned({
  required Map<String, Object?> extras,
  String id = 'cfg',
  String name = 'Run me',
}) {
  return OwnedLaunchConfiguration(
    owner: _folder,
    configuration: LaunchConfiguration(
      id: id,
      name: name,
      type: 'shellScript',
      extras: extras,
    ),
  );
}

class _FakeTerminalRunService extends WorkspaceTerminalRunService {
  _FakeTerminalRunService(this.entry);

  final WorkspaceTerminalEntry entry;
  final openCalls = <Map<String, Object?>>[];
  var waitForReadyCalls = 0;
  var injectCalls = 0;
  var interruptCalls = 0;
  String? lastInjectLine;
  final registeredSessions = <String, String>{};

  @override
  Future<WorkspaceTerminalEntry> openForRun({
    required String workspaceId,
    required String selectionKey,
    required String? runSessionId,
    required bool allowMultipleInstances,
    required String cwd,
    required String targetId,
    required String title,
    required WorkspaceTerminalGroup group,
    required WorkspaceShellConnector connector,
    required WorkspaceTerminalConnectCoordinator connectCoordinator,
    required WorkspaceTerminalSessionOps ops,
    required TerminalTheme theme,
    required String sshConnectFailedMessage,
    VoidCallback? onStateChanged,
    bool Function()? mounted,
  }) async {
    openCalls.add({
      'workspaceId': workspaceId,
      'selectionKey': selectionKey,
      'runSessionId': runSessionId,
      'allowMultipleInstances': allowMultipleInstances,
      'cwd': cwd,
      'targetId': targetId,
      'title': title,
      'sshConnectFailedMessage': sshConnectFailedMessage,
    });
    return entry;
  }

  @override
  Future<void> waitForReady(
    WorkspaceTerminalEntry entry, {
    Duration timeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(milliseconds: 50),
  }) async {
    waitForReadyCalls++;
  }

  @override
  void inject(WorkspaceTerminalEntry entry, String line) {
    injectCalls++;
    lastInjectLine = line;
  }

  @override
  void interrupt(WorkspaceTerminalEntry entry) {
    interruptCalls++;
  }

  @override
  void registerSessionEntry({
    required String sessionId,
    required String entryId,
  }) {
    registeredSessions[sessionId] = entryId;
  }
}

class _RecordingConnector extends WorkspaceShellConnector {
  _RecordingConnector()
    : super(
        transportFactory: TerminalTransportFactory(
          sshProfileRepository: SshProfileRepository(),
          sshCredentialStore: InMemorySshCredentialStore(),
          sshKnownHostRepository: InMemorySshKnownHostRepository(),
        ),
        sshProfileRepository: SshProfileRepository(),
      );

  @override
  TerminalSession createSession(WorkspaceTerminalSessionSpec spec) {
    return TerminalSession(
      executable: 'sh',
      validateLaunch: false,
      parseExecutable: false,
    );
  }

  @override
  Future<String> labelForSpec(WorkspaceTerminalSessionSpec spec) async =>
      'label';
}

class _RecordingProcessHandle implements ProcessRunHandle {
  _RecordingProcessHandle();

  final exit = Completer<int>();
  var killCount = 0;

  @override
  Future<int> get exitCode => exit.future;

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  void kill() => killCount++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WorkspaceTerminalRegistry registry;
  late _RecordingConnector connector;
  late WorkspaceTerminalSessionOps ops;
  late WorkspaceTerminalEntry entry;
  late _FakeTerminalRunService runService;
  late TerminalRunDepsResolver depsResolver;

  setUp(() {
    registry = WorkspaceTerminalRegistry();
    connector = _RecordingConnector();
    ops = WorkspaceTerminalSessionOps();
    // Lightweight entry — never connect; avoid dispose hang in unit tests.
    entry = WorkspaceTerminalEntry(
      id: 'entry-1',
      cwd: '/proj',
      spec: const WorkspaceTerminalWorkspaceTargetSpec('local'),
      session: TerminalSession(
        executable: 'sh',
        validateLaunch: false,
        parseExecutable: false,
      ),
    );
    runService = _FakeTerminalRunService(entry);
    depsResolver = TerminalRunDepsResolver()
      ..setDeps(
        TerminalRunDeps(
          registry: registry,
          connector: connector,
          ops: ops,
          runService: runService,
          resolveTheme: () => TerminalTheme.defaults,
          resolveSshConnectFailedMessage: () => 'ssh failed',
        ),
      );
  });

  test('terminal branch opens, waits, injects; stop interrupts', () async {
    final intents = <RunUiIntent>[];
    final bound = <({String entryId, String sessionId})>[];
    final launcher = RunShellScriptLauncher(
      workspaceId: 'ws-1',
      terminalRunDeps: depsResolver,
      emitUiIntent: intents.add,
      registerTerminalSession: ({
        required String entryId,
        required String sessionId,
      }) {
        bound.add((entryId: entryId, sessionId: sessionId));
      },
      processExecutor: ProcessRunExecutor(
        spawner:
            ({
              required executable,
              required arguments,
              required workingDirectory,
              environment,
              runInShell = false,
              includeParentEnvironment = true,
            }) async {
              fail('ProcessRunExecutor must not be called in terminal mode');
            },
      ),
    );

    final handle = await launcher.launch(
      sessionId: 'sess-1',
      owned: _owned(
        extras: {
          'execute': 'scriptText',
          'scriptText': 'echo hi',
          'interpreterPath': '/bin/bash',
          'cwd': '/proj',
          'executeInTerminal': true,
        },
      ),
      onOutput: (_) {},
    );

    expect(runService.openCalls, hasLength(1));
    expect(runService.openCalls.single['workspaceId'], 'ws-1');
    expect(runService.openCalls.single['selectionKey'], 'local|/proj|cfg');
    expect(runService.openCalls.single['title'], 'Run me');
    expect(runService.openCalls.single['cwd'], '/proj');
    expect(runService.openCalls.single['sshConnectFailedMessage'], 'ssh failed');
    expect(runService.waitForReadyCalls, 1);
    expect(runService.injectCalls, 1);
    expect(runService.lastInjectLine, "cd '/proj' && '/bin/bash' -c 'echo hi'");
    expect(runService.registeredSessions['sess-1'], 'entry-1');
    expect(bound, [(entryId: 'entry-1', sessionId: 'sess-1')]);
    expect(intents, [
      const RunUiIntent(
        surface: RunToolSurface.terminal,
        activateToolWindow: true,
        focusToolWindow: false,
        terminalEntryId: 'entry-1',
      ),
    ]);

    var exitCompleted = false;
    unawaited(handle.exitCode.then((_) => exitCompleted = true));
    await Future<void>.delayed(Duration.zero);
    expect(exitCompleted, isFalse);

    await handle.stop();
    expect(runService.interruptCalls, 1);
  });

  test('non-terminal branch delegates to ProcessRunExecutor', () async {
    final spawned = <Map<String, Object?>>[];
    final intents = <RunUiIntent>[];
    final processHandle = _RecordingProcessHandle();
    final launcher = RunShellScriptLauncher(
      workspaceId: 'ws-1',
      terminalRunDeps: depsResolver,
      emitUiIntent: intents.add,
      processExecutor: ProcessRunExecutor(
        spawner:
            ({
              required executable,
              required arguments,
              required workingDirectory,
              environment,
              runInShell = false,
              includeParentEnvironment = true,
            }) async {
              spawned.add({
                'executable': executable,
                'arguments': arguments,
                'workingDirectory': workingDirectory,
                'runInShell': runInShell,
              });
              return processHandle;
            },
      ),
    );

    final handle = await launcher.launch(
      sessionId: 'sess-2',
      owned: _owned(
        extras: {
          'execute': 'scriptFile',
          'scriptPath': './a.sh',
          'interpreterPath': '/bin/bash',
          'cwd': '/proj',
          'executeInTerminal': false,
          'activateToolWindow': false,
          'focusToolWindow': true,
        },
      ),
      onOutput: (_) {},
    );

    expect(runService.openCalls, isEmpty);
    expect(spawned, hasLength(1));
    expect(spawned.single['executable'], HostInteractiveShell.defaultExecutable());
    expect(spawned.single['runInShell'], isTrue);
    final args = spawned.single['arguments']! as List<String>;
    expect(args.first, '-c');
    expect(args[1], contains("./a.sh"));
    expect(intents, [
      const RunUiIntent(
        surface: RunToolSurface.run,
        activateToolWindow: false,
        focusToolWindow: true,
      ),
    ]);

    processHandle.exit.complete(0);
    expect(await handle.exitCode, 0);
    await handle.stop();
    expect(processHandle.killCount, 1);
  });
}
