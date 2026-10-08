@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/protocol.dart'
    show
        SSHChannelRequestType,
        SSHMessage,
        SSH_Message_Channel_Failure,
        SSH_Message_Channel_Request,
        SSH_Message_Channel_Success;
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';

/// Fake pty recording resizes and signals, producing output only when the
/// test pushes it.
class _FakePty implements SSHServerPty {
  final _stdout = StreamController<Uint8List>.broadcast();
  final _stdin = StreamController<List<int>>();
  final resized = <String>[];
  final signaled = <String>[];

  @override
  void resize(int columns, int rows) => resized.add('$columns x $rows');

  @override
  void signal(String name) => signaled.add(name);

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => const Stream.empty();

  @override
  StreamSink<List<int>> get stdin => _stdin.sink;

  @override
  Future<int> get exitCode => Completer<int>().future;

  @override
  void kill() {}
}

/// Fake process that never exits, so the channel it serves stays alive until
/// the test tears it down.
class _HangingProcess implements SSHServerProcess {
  final _stdin = StreamController<List<int>>();
  final _stdout = StreamController<Uint8List>();

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => const Stream.empty();

  @override
  StreamSink<List<int>> get stdin => _stdin.sink;

  @override
  Future<int> get exitCode => Completer<int>().future;

  @override
  void kill() {}
}

void main() {
  test('shell request with pty spawns pty, echoes, resizes, signals', () async {
    final pty = _FakePty();
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      ptyFactory: (initial) async {
        expect(initial.columns, 120);
        expect(initial.rows, 40);
        expect(initial.environment['TERM'], 'xterm-256color');
        // `env` requests the client sent before the shell are accumulated
        // into the pty environment.
        expect(initial.environment['FOO'], 'bar');
        return pty;
      },
    );
    final session = await client.shell(
      pty: const SSHPtyConfig(width: 120, height: 40),
      environment: const {'FOO': 'bar'},
    );
    // The server wires the pipes one turn after its success reply; let that
    // land before producing output, or the broadcast stream has no listener.
    await pumpEventQueue();

    pty._stdout.add(Uint8List.fromList(utf8.encode('hello')));
    expect(utf8.decoder.bind(session.stdout).first, completion('hello'));

    session.resizeTerminal(200, 50);
    await pumpEventQueue();
    expect(pty.resized, contains('200 x 50'));

    // The fork's SSHSession.kill sends the signal by its RFC 4254 §6.9
    // name; the server hands that name to the pty unchanged.
    session.kill(SSHSignal.INT);
    await pumpEventQueue();
    expect(pty.signaled, contains('INT'));

    client.close();
    await server.close();
  });

  test('shell without ptyFactory fails the request', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
    );
    await expectLater(
      client.shell(pty: const SSHPtyConfig(width: 80, height: 24)),
      throwsA(anything),
    );
    client.close();
    await server.close();
  });

  test('shell without a prior pty-req is refused', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      ptyFactory: (initial) async => _FakePty(),
    );
    // A bare shell has no stashed dimensions to spawn the pty with — and
    // this server only serves pty sessions — so it is refused and the
    // factory never runs.
    final controller = await openClientSessionChannel(client);
    expect(await controller.sendShell(), isFalse);
    client.close();
    await server.close();
  });

  test('a second lifecycle request on a session channel is refused', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      processFactory: (argv, cwd, env) async => _HangingProcess(),
    );
    final controller = await openClientSessionChannel(client);
    expect(
      await controller.sendExec(
        TpExecCodec.encode(const SSHExecRequest(argv: ['claude'])),
      ),
      isTrue,
    );
    // A session channel serves one program (RFC 4254 §6.5): the second exec
    // is refused, and the channel is closed after its failure reply.
    expect(
      await controller.sendExec(
        TpExecCodec.encode(const SSHExecRequest(argv: ['claude'])),
      ),
      isFalse,
    );
    await controller.channel.done;
    client.close();
    await server.close();
  });

  // Protocol honesty: `window-change` and `signal` are no-ops with no live
  // pty on the channel, and a client that asks for a reply must not get a
  // success ack for one.
  //
  // The verdict is not observable over the dual pair: the fork's
  // `SSH_Message_Channel_Request.decode` hard-codes `wantReply: false` for
  // both request types, so no wire reply is ever sent for them whatever the
  // session layer answers. The session layer is therefore driven directly,
  // on a hand-built channel wired exactly like SSHServerConnection wires it,
  // with the outgoing packets captured.
  test('signal and window-change without a live pty reply channel failure',
      () async {
    final sentIds = <int>[];
    final channel = _buildSessionChannel(
      config: SSHServerConfig(
        hostKeyPair: testHostKey,
        expectedUsername: 'user',
        authenticate: (_) async => true,
        ptyFactory: (initial) async => _FakePty(),
      ),
      onSendPacket: (payload) => sentIds.add(SSHMessage.readMessageId(payload)),
    );

    channel.handleRequest(
      SSH_Message_Channel_Request(
        recipientChannel: 0,
        requestType: SSHChannelRequestType.signal,
        wantReply: true,
        signalName: 'INT',
      ),
    );
    await pumpEventQueue();
    expect(sentIds, [SSH_Message_Channel_Failure.messageId]);

    channel.handleRequest(
      SSH_Message_Channel_Request(
        recipientChannel: 0,
        requestType: SSHChannelRequestType.windowChange,
        wantReply: true,
        termWidth: 100,
        termHeight: 50,
        termPixelWidth: 0,
        termPixelHeight: 0,
      ),
    );
    await pumpEventQueue();
    expect(sentIds, [
      SSH_Message_Channel_Failure.messageId,
      SSH_Message_Channel_Failure.messageId,
    ]);

    channel.detach();
  });

  test('signal and window-change with a live pty succeed', () async {
    final pty = _FakePty();
    final sentIds = <int>[];
    final channel = _buildSessionChannel(
      config: SSHServerConfig(
        hostKeyPair: testHostKey,
        expectedUsername: 'user',
        authenticate: (_) async => true,
        ptyFactory: (initial) async => pty,
      ),
      onSendPacket: (payload) => sentIds.add(SSHMessage.readMessageId(payload)),
    );

    // pty-req stashes the dimensions; shell spawns the pty they describe.
    channel.handleRequest(
      SSH_Message_Channel_Request(
        recipientChannel: 0,
        requestType: SSHChannelRequestType.pty,
        wantReply: true,
        termType: 'xterm-256color',
        termWidth: 80,
        termHeight: 24,
        termPixelWidth: 0,
        termPixelHeight: 0,
        termModes: Uint8List(0),
      ),
    );
    channel.handleRequest(
      SSH_Message_Channel_Request(
        recipientChannel: 0,
        requestType: SSHChannelRequestType.shell,
        wantReply: true,
      ),
    );
    await pumpEventQueue();
    expect(sentIds, [
      SSH_Message_Channel_Success.messageId,
      SSH_Message_Channel_Success.messageId,
    ]);

    // With the pty live, both requests are applied and acknowledged.
    channel.handleRequest(
      SSH_Message_Channel_Request(
        recipientChannel: 0,
        requestType: SSHChannelRequestType.windowChange,
        wantReply: true,
        termWidth: 200,
        termHeight: 50,
        termPixelWidth: 0,
        termPixelHeight: 0,
      ),
    );
    await pumpEventQueue();
    expect(pty.resized, contains('200 x 50'));
    channel.handleRequest(
      SSH_Message_Channel_Request(
        recipientChannel: 0,
        requestType: SSHChannelRequestType.signal,
        wantReply: true,
        signalName: 'INT',
      ),
    );
    await pumpEventQueue();
    expect(pty.signaled, contains('INT'));
    expect(sentIds, everyElement(SSH_Message_Channel_Success.messageId));
    expect(sentIds, hasLength(4));

    channel.detach();
  });
}

/// A session channel built by hand, wired exactly like SSHServerConnection
/// wires the channels it confirms, with every outgoing packet handed to
/// [onSendPacket] instead of a transport.
SSHServerChannel _buildSessionChannel({
  required SSHServerConfig config,
  required void Function(Uint8List payload) onSendPacket,
}) {
  final channel = SSHServerChannel(
    recipientChannel: 0,
    ourChannel: 0,
    channelType: 'session',
    peerInitialWindowSize: 1024,
    peerMaximumPacketSize: 32768,
    sendPacket: onSendPacket,
    onClosed: (_) {},
  );
  channel.onRequest = (channel, request) =>
      handleSessionRequest(channel, request, config: config);
  return channel;
}
