import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_shell_launch_plan.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/team_bus/bus_user_line_capture.dart';
import 'package:teampilot/services/terminal/pending_user_message.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport.dart';

import '../../support/flush_terminal_engine.dart';
import '../../support/rust_lib_test_init.dart';

class _FakeTransport implements TerminalTransport {
  final outputController = StreamController<Uint8List>();
  Completer<int> doneCompleter = Completer<int>();
  final writes = <Uint8List>[];

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
    writes.add(data);
  }
}

String get _ptyTestExecutable {
  if (Platform.isWindows) {
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    return '$root\\System32\\cmd.exe';
  }
  for (final candidate in ['/usr/bin/true', '/bin/true', '/bin/sh']) {
    if (File(candidate).existsSync()) return candidate;
  }
  return Platform.resolvedExecutable;
}

Uint8List _osc997() =>
    Uint8List.fromList([0x1b, 0x5d, 0x39, 0x39, 0x37, 0x3b, 0x31, 0x07, 0x41]);

Uint8List _oscTitle(String title) =>
    Uint8List.fromList(utf8.encode('\x1b]0;$title\x07'));

void main() {
  setUpAll(initRustLibForTests);

  late _FakeTransport transport;
  late TerminalSession session;

  setUp(() {
    transport = _FakeTransport();
    session = TerminalSession(
      executable: _ptyTestExecutable,
      confirmFallback: const Duration(milliseconds: 50),
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
  });

  tearDown(() async {
    session.dispose();
    await transport.outputController.close();
  });

  Future<void> waitUntilTransportReady() async {
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(session.transportReadyForIo, isTrue);
  }

  test('CLI connect binds Cursor OSC title attention', () async {
    final attention = AgentAttentionCubit(pruneInterval: null);
    addTearDown(attention.close);

    session.connect(
      workingDirectory: Directory.systemTemp.path,
      observation: TerminalObservationAttach(
        sessionId: 's1',
        memberId: 'm1',
        cli: CliTool.cursor,
        attention: attention,
        skipPermissions: () => false,
      ),
    );
    await waitUntilTransportReady();
    transport.outputController.add(_oscTitle('Cursor - action required'));
    await flushTerminalEngine(session.engine);

    expect(
      attention.state.attentionFor(sessionId: 's1', memberId: 'm1'),
      AgentSeatAttention.waiting,
    );
  });

  test('CLI connect strips OSC 997 on engine→PTY path', () async {
    session.connect(
      workingDirectory: Directory.systemTemp.path,
      observation: const TerminalObservationAttach(
        sessionId: 's1',
        memberId: 'm1',
        cli: CliTool.cursor,
      ),
    );
    await waitUntilTransportReady();

    session.engine.write(_osc997());
    await Future<void>.delayed(Duration.zero);

    expect(transport.writes, [
      Uint8List.fromList([0x41]),
    ]);
  });

  test('workspace shell does not bind Cursor OSC or strip 997', () async {
    final attention = AgentAttentionCubit(pruneInterval: null);
    addTearDown(attention.close);

    session.connectWorkspaceShell(
      plan: WorkspaceShellLaunchPlan(
        executable: _ptyTestExecutable,
        arguments: const [],
        workingDirectory: Directory.systemTemp.path,
        useWslPaths: false,
        inheritHostEnvironment: false,
        runtimeTarget: RuntimeTarget.local(),
        usesRemoteTransport: false,
      ),
    );
    await waitUntilTransportReady();
    transport.outputController.add(_oscTitle('Cursor - action required'));
    await flushTerminalEngine(session.engine);
    expect(
      attention.state.attentionFor(sessionId: 's1', memberId: 'm1'),
      isNull,
    );

    session.engine.write(_osc997());
    await Future<void>.delayed(Duration.zero);
    expect(transport.writes, [_osc997()]);
  });

  test('CLI connect captures user lines from engine input', () async {
    final lines = <String>[];
    session.connect(
      workingDirectory: Directory.systemTemp.path,
      onEveryUserLineSubmitted: lines.add,
    );
    await waitUntilTransportReady();

    session.engine.write(Uint8List.fromList(utf8.encode('hello\r')));
    await Future<void>.delayed(Duration.zero);

    expect(lines, ['hello']);
  });

  test('CLI connect parks TeamBus intercept submits', () async {
    expect(
      session.parkedUserSubmissions,
      emits(
        isA<PendingUserMessage>()
            .having((m) => m.id, 'id', 'parked-1')
            .having((m) => m.content, 'content', 'hello'),
      ),
    );

    session.connect(
      workingDirectory: Directory.systemTemp.path,
      busUserInputRouting: BusUserInputRouting(
        shouldIntercept: () => true,
        onTurnStart: () {},
        onUserLine: (_) => 'parked-1',
        isUnread: (id) => id == 'parked-1',
      ),
    );
    await waitUntilTransportReady();

    session.engine.write(Uint8List.fromList(utf8.encode('hello\r')));
    await Future<void>.delayed(Duration.zero);

    expect(session.isUnreadParkedMessage('parked-1'), isTrue);
    expect(session.isUnreadParkedMessage('other'), isFalse);
  });

  test('disconnect clears intercept unread lookup', () async {
    session.connect(
      workingDirectory: Directory.systemTemp.path,
      busUserInputRouting: BusUserInputRouting(
        shouldIntercept: () => true,
        onTurnStart: () {},
        onUserLine: (_) => 'parked-1',
        isUnread: (_) => true,
      ),
    );
    await waitUntilTransportReady();
    session.disconnect();
    expect(session.isUnreadParkedMessage('parked-1'), isFalse);
  });
}
