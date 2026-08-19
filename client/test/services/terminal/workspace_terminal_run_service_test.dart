import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
import 'package:teampilot/services/terminal/workspace_shell_connector.dart';
import 'package:teampilot/services/terminal/workspace_terminal_connect_coordinator.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';
import 'package:teampilot/services/terminal/workspace_terminal_run_service.dart';
import '../../support/rust_lib_test_init.dart';
import 'package:teampilot/services/terminal/workspace_terminal_session_ops.dart';

const _theme = TerminalTheme.defaults;

class _RecordingTransport implements TerminalTransport {
  final outputController = StreamController<Uint8List>();
  Completer<int> doneCompleter = Completer<int>();
  final writes = <String>[];

  @override
  Stream<Uint8List> get output => outputController.stream;

  @override
  Future<int> get done => doneCompleter.future;

  @override
  int? get pid => null;

  @override
  void close() {
    if (!doneCompleter.isCompleted) {
      doneCompleter.complete(0);
    }
  }

  @override
  void resize(int rows, int columns) {}

  @override
  void write(Uint8List data) {
    writes.add(utf8.decode(data));
  }

  void emit(String text) {
    outputController.add(Uint8List.fromList(utf8.encode(text)));
  }

  Future<void> dispose() async {
    close();
    await outputController.close();
  }
}

Future<({TerminalSession session, _RecordingTransport transport})>
_readySession() async {
  final transport = _RecordingTransport();
  final session = TerminalSession(
    executable: 'sh',
    validateLaunch: false,
    parseExecutable: false,
    confirmFallback: const Duration(milliseconds: 20),
    transportStarter:
        (
          executable, {
          required arguments,
          required workingDirectory,
          required columns,
          required rows,
          environment,
        }) {
          return Future.value(transport);
        },
  );
  session.connect(workingDirectory: Directory.systemTemp.path);
  session.onViewportResize(80, 24);
  transport.emit('ready\r\n');
  await Future<void>.delayed(Duration.zero);
  expect(session.transportReadyForIo, isTrue);
  return (session: session, transport: transport);
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

  final createdSpecs = <WorkspaceTerminalSessionSpec>[];

  @override
  TerminalSession createSession(WorkspaceTerminalSessionSpec spec) {
    createdSpecs.add(spec);
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

class _RecordingConnectCoordinator extends WorkspaceTerminalConnectCoordinator {
  _RecordingConnectCoordinator(WorkspaceShellConnector connector)
    : super(connector: connector);

  var connectCalls = 0;

  @override
  Future<void> connect({
    required WorkspaceTerminalGroup group,
    required WorkspaceTerminalEntry entry,
    required TerminalTheme theme,
    required String sshConnectFailedMessage,
    required void Function() onStateChanged,
    required bool Function() mounted,
  }) async {
    connectCalls++;
  }
}

Future<WorkspaceTerminalEntry> _open({
  required WorkspaceTerminalRunService service,
  required WorkspaceTerminalGroup group,
  required WorkspaceShellConnector connector,
  required WorkspaceTerminalConnectCoordinator connectCoordinator,
  required WorkspaceTerminalSessionOps ops,
  required String selectionKey,
  required bool allowMultipleInstances,
  String? runSessionId,
  String? preferEntryId,
  String workspaceId = 'ws-1',
  String cwd = '/ws',
  String targetId = 'local',
  String title = 'Run me',
}) {
  return service.openForRun(
    workspaceId: workspaceId,
    selectionKey: selectionKey,
    runSessionId: runSessionId,
    allowMultipleInstances: allowMultipleInstances,
    preferEntryId: preferEntryId,
    cwd: cwd,
    targetId: targetId,
    title: title,
    group: group,
    connector: connector,
    connectCoordinator: connectCoordinator,
    ops: ops,
    theme: _theme,
    sshConnectFailedMessage: 'ssh failed',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initRustLibForTests);

  late WorkspaceTerminalRunService service;
  late _RecordingConnector connector;
  late _RecordingConnectCoordinator connect;
  late WorkspaceTerminalSessionOps ops;
  late WorkspaceTerminalGroup group;

  setUp(() {
    service = WorkspaceTerminalRunService();
    connector = _RecordingConnector();
    connect = _RecordingConnectCoordinator(connector);
    ops = WorkspaceTerminalSessionOps();
    group = WorkspaceTerminalGroup();
  });

  tearDown(() {
    group.dispose();
  });

  test('reuses bind when allowMultipleInstances is false', () async {
    final first = await _open(
      service: service,
      group: group,
      connector: connector,
      connectCoordinator: connect,
      ops: ops,
      selectionKey: 'local|/ws|cfg-1',
      allowMultipleInstances: false,
      runSessionId: 'sess-a',
    );
    final second = await _open(
      service: service,
      group: group,
      connector: connector,
      connectCoordinator: connect,
      ops: ops,
      selectionKey: 'local|/ws|cfg-1',
      allowMultipleInstances: false,
      runSessionId: 'sess-b',
    );

    expect(second.id, first.id);
    expect(group.entries, hasLength(1));
    expect(group.activeId, first.id);
    // create + reconnect-on-reuse (coordinator no-ops if still running)
    expect(connect.connectCalls, 2);
    expect(connector.createdSpecs, [
      const WorkspaceTerminalWorkspaceTargetSpec('local'),
    ]);
  });

  test('reused disconnected entry triggers connect', () async {
    final first = await _open(
      service: service,
      group: group,
      connector: connector,
      connectCoordinator: connect,
      ops: ops,
      selectionKey: 'local|/ws|cfg-1',
      allowMultipleInstances: false,
      runSessionId: 'sess-a',
    );
    expect(connect.connectCalls, 1);

    first.connected = false;
    final reused = await _open(
      service: service,
      group: group,
      connector: connector,
      connectCoordinator: connect,
      ops: ops,
      selectionKey: 'local|/ws|cfg-1',
      allowMultipleInstances: false,
      runSessionId: 'sess-b',
    );

    expect(reused.id, first.id);
    expect(group.entries, hasLength(1));
    expect(connect.connectCalls, 2);
  });

  test('clears stale session bind when entry missing from group', () async {
    final entry = await _open(
      service: service,
      group: group,
      connector: connector,
      connectCoordinator: connect,
      ops: ops,
      selectionKey: 'stale-key',
      allowMultipleInstances: false,
      runSessionId: 'sess-stale',
    );
    expect(service.entryIdForSession('sess-stale'), entry.id);

    group.removeEntry(entry.id);
    await _open(
      service: service,
      group: group,
      connector: connector,
      connectCoordinator: connect,
      ops: ops,
      selectionKey: 'stale-key',
      allowMultipleInstances: false,
      runSessionId: 'sess-new',
    );

    expect(service.entryIdForSession('sess-stale'), isNull);
    expect(service.entryIdForSession('sess-new'), isNotNull);
  });

  test('creates new entry when allowMultipleInstances is true without '
      'overwriting prior session→entry bindings', () async {
    final first = await _open(
      service: service,
      group: group,
      connector: connector,
      connectCoordinator: connect,
      ops: ops,
      selectionKey: 'local|/ws|cfg-1',
      allowMultipleInstances: true,
      runSessionId: 'sess-a',
    );
    final second = await _open(
      service: service,
      group: group,
      connector: connector,
      connectCoordinator: connect,
      ops: ops,
      selectionKey: 'local|/ws|cfg-1',
      allowMultipleInstances: true,
      runSessionId: 'sess-b',
    );

    expect(second.id, isNot(first.id));
    expect(group.entries, hasLength(2));
    expect(service.entryIdForSession('sess-a'), first.id);
    expect(service.entryIdForSession('sess-b'), second.id);
  });

  test(
    'preferEntryId reuses that entry even when allowMultipleInstances is true',
    () async {
      final first = await _open(
        service: service,
        group: group,
        connector: connector,
        connectCoordinator: connect,
        ops: ops,
        selectionKey: 'local|/ws|cfg-1',
        allowMultipleInstances: true,
        runSessionId: 'sess-a',
      );
      final second = await _open(
        service: service,
        group: group,
        connector: connector,
        connectCoordinator: connect,
        ops: ops,
        selectionKey: 'local|/ws|cfg-1',
        allowMultipleInstances: true,
        runSessionId: 'sess-b',
      );
      expect(second.id, isNot(first.id));

      final reused = await _open(
        service: service,
        group: group,
        connector: connector,
        connectCoordinator: connect,
        ops: ops,
        selectionKey: 'local|/ws|cfg-1',
        allowMultipleInstances: true,
        preferEntryId: first.id,
        runSessionId: 'sess-restart',
      );

      expect(reused.id, first.id);
      expect(group.entries, hasLength(2));
      expect(group.activeId, first.id);
      expect(service.entryIdForSession('sess-restart'), first.id);
      expect(connect.connectCalls, 3);
    },
  );

  test('dual maps bindKey→entryId and sessionId→entryId', () async {
    final entry = await _open(
      service: service,
      group: group,
      connector: connector,
      connectCoordinator: connect,
      ops: ops,
      selectionKey: 'sel-key',
      allowMultipleInstances: false,
      runSessionId: null,
    );
    expect(
      service.entryIdForBind(workspaceId: 'ws-1', selectionKey: 'sel-key'),
      entry.id,
    );
    expect(service.entryIdForSession('later-sess'), isNull);

    service.registerSessionEntry(sessionId: 'later-sess', entryId: entry.id);
    expect(service.entryIdForSession('later-sess'), entry.id);
  });

  test('openForRun sets cwd, title, and workspace target spec', () async {
    final entry = await _open(
      service: service,
      group: group,
      connector: connector,
      connectCoordinator: connect,
      ops: ops,
      selectionKey: 'k',
      allowMultipleInstances: false,
      cwd: '/expanded/cwd',
      targetId: 'ssh:p1',
      title: 'My Script',
    );

    expect(entry.cwd, '/expanded/cwd');
    expect(entry.titleLabel, 'My Script');
    expect(entry.spec, const WorkspaceTerminalWorkspaceTargetSpec('ssh:p1'));
    expect(entry.followWorkspace, isFalse);
  });

  test('waitForReady resolves when transportReadyForIo becomes true', () async {
    final transport = _RecordingTransport();
    addTearDown(transport.dispose);
    final session = TerminalSession(
      executable: 'sh',
      validateLaunch: false,
      parseExecutable: false,
      confirmFallback: const Duration(milliseconds: 20),
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(transport);
          },
    );
    final entry = group.addEntry(
      cwd: '/tmp',
      spec: const WorkspaceTerminalLocalSpec('/bin/sh'),
      session: session,
      select: true,
    );

    final ready = service.waitForReady(
      entry,
      timeout: const Duration(seconds: 2),
      pollInterval: const Duration(milliseconds: 20),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    session.connect(workingDirectory: Directory.systemTemp.path);
    session.onViewportResize(80, 24);
    transport.emit('ready\r\n');
    await ready;
  });

  test('waitForReady times out when transport never ready', () async {
    final session = TerminalSession(
      executable: 'sh',
      validateLaunch: false,
      parseExecutable: false,
    );
    final entry = group.addEntry(
      cwd: '/tmp',
      spec: const WorkspaceTerminalLocalSpec('/bin/sh'),
      session: session,
      select: true,
    );

    await expectLater(
      service.waitForReady(
        entry,
        timeout: const Duration(milliseconds: 80),
        pollInterval: const Duration(milliseconds: 20),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('inject writes line + CR via input.writeToPty', () async {
    final ready = await _readySession();
    addTearDown(ready.transport.dispose);
    final entry = group.addEntry(
      cwd: '/tmp',
      spec: const WorkspaceTerminalLocalSpec('/bin/sh'),
      session: ready.session,
      select: true,
    );

    service.inject(entry, 'echo hello');
    expect(ready.transport.writes, ['echo hello\r']);
  });

  test('interrupt sends Ctrl+C', () async {
    final ready = await _readySession();
    addTearDown(ready.transport.dispose);
    final entry = group.addEntry(
      cwd: '/tmp',
      spec: const WorkspaceTerminalLocalSpec('/bin/sh'),
      session: ready.session,
      select: true,
    );

    service.interrupt(entry);
    expect(ready.transport.writes, ['\x03']);
  });

  test('handleEntryClosed clears binds and notifies listener', () async {
    final closed = <String>[];
    service = WorkspaceTerminalRunService(onEntryClosed: closed.add);
    final entry = await _open(
      service: service,
      group: group,
      connector: connector,
      connectCoordinator: connect,
      ops: ops,
      selectionKey: 'sel',
      allowMultipleInstances: false,
      runSessionId: 'sess-1',
    );

    service.handleEntryClosed(entry.id);

    expect(closed, [entry.id]);
    expect(
      service.entryIdForBind(workspaceId: 'ws-1', selectionKey: 'sel'),
      isNull,
    );
    expect(service.entryIdForSession('sess-1'), isNull);

    final next = await _open(
      service: service,
      group: group,
      connector: connector,
      connectCoordinator: connect,
      ops: ops,
      selectionKey: 'sel',
      allowMultipleInstances: false,
    );
    expect(next.id, isNot(entry.id));
    expect(connect.connectCalls, 2);
  });

  test('handleEntryClosed notifies addOnEntryClosedListener', () async {
    final closed = <String>[];
    service.addOnEntryClosedListener(closed.add);
    final entry = await _open(
      service: service,
      group: group,
      connector: connector,
      connectCoordinator: connect,
      ops: ops,
      selectionKey: 'sel',
      allowMultipleInstances: false,
      runSessionId: 'sess-1',
    );

    service.handleEntryClosed(entry.id);

    expect(closed, [entry.id]);
  });

  test('removeOnEntryClosedListener stops notifications', () async {
    final closed = <String>[];
    void listener(String entryId) => closed.add(entryId);
    service.addOnEntryClosedListener(listener);
    service.removeOnEntryClosedListener(listener);
    final entry = await _open(
      service: service,
      group: group,
      connector: connector,
      connectCoordinator: connect,
      ops: ops,
      selectionKey: 'sel',
      allowMultipleInstances: false,
    );

    service.handleEntryClosed(entry.id);

    expect(closed, isEmpty);
  });

  test('TerminalRunDepsResolver removeEntryClosedListener clears pending', () {
    final resolver = TerminalRunDepsResolver();
    final closed = <String>[];
    void listener(String entryId) => closed.add(entryId);
    resolver.addEntryClosedListener(listener);
    resolver.removeEntryClosedListener(listener);
    resolver.setDeps(
      TerminalRunDeps(
        registry: WorkspaceTerminalRegistry(),
        connector: connector,
        ops: ops,
        runService: service,
      ),
    );
    service.handleEntryClosed('gone');
    expect(closed, isEmpty);
  });

  test('TerminalRunDepsResolver removeEntryClosedListener clears live', () {
    final resolver = TerminalRunDepsResolver()
      ..setDeps(
        TerminalRunDeps(
          registry: WorkspaceTerminalRegistry(),
          connector: connector,
          ops: ops,
          runService: service,
        ),
      );
    final closed = <String>[];
    void listener(String entryId) => closed.add(entryId);
    resolver.addEntryClosedListener(listener);
    resolver.removeEntryClosedListener(listener);
    service.handleEntryClosed('gone');
    expect(closed, isEmpty);
  });
}
