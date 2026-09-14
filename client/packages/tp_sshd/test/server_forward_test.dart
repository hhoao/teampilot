@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHDisconnectError;
import 'package:dartssh2/protocol.dart'
    show
        SSHMessage,
        SSHMessageReader,
        SSH_Message_Channel_Confirmation,
        SSH_Message_Channel_Open,
        SSH_Message_Global_Request,
        SSH_Message_Request_Failure,
        SSH_Message_Request_Success;
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';

void main() {
  test('forwardRemote binds loopback and pumps bytes both ways', () async {
    // Real loopback sockets — the one place unit tests touch the network
    // stack, mirroring the fork's own test philosophy.
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      forwarding: _testForwardingConfig(bindServerSocket: _bindRealLoopback),
    );
    final forward = await client.forwardRemote(host: '127.0.0.1', port: 0);
    // The client learned the actually bound port from the Request_Success
    // payload (port 0 — an ephemeral port — was requested).
    expect(forward!.host, '127.0.0.1');
    expect(forward.port, greaterThan(0));

    // Something on the server host connects to the bound loopback port;
    // bytes must ride a forwarded-tcpip channel to the client side, and
    // replies must ride it back.
    final clientReceived = StringBuffer();
    final pingReceived = Completer<void>();
    forward.connections.listen((channel) {
      utf8.decoder.bind(channel.stream).listen((data) {
        clientReceived.write(data);
        if (!pingReceived.isCompleted &&
            clientReceived.toString().contains('ping')) {
          pingReceived.complete();
          channel.sink.add(utf8.encode('pong'));
        }
      });
    });
    final probe = await Socket.connect('127.0.0.1', forward.port);
    final probeReceived = StringBuffer();
    final pongReceived = Completer<void>();
    probe.listen((data) {
      probeReceived.write(utf8.decode(data));
      if (!pongReceived.isCompleted &&
          probeReceived.toString().contains('pong')) {
        pongReceived.complete();
      }
    });
    probe.add(utf8.encode('ping'));

    await pingReceived.future;
    await pongReceived.future;

    probe.destroy();
    await forward.close(); // cancel-tcpip-forward
    await client.close();
    await server.close();
  });

  group('open verdict policy for server-initiated channels', () {
    // sshd's channel_input_open_confirmation (channels.c:3636-3644) fatals
    // for any channel that is not still in its OPENING state —
    // `ssh_packet_disconnect("Received open confirmation for non-opening
    // channel %d.")` — and only a truly unknown id takes
    // channel_from_packet_id's nonexistent-channel disconnect. A dartssh2
    // client answers each server-initiated open exactly once, so a
    // duplicate verdict for a live channel is a misbehaving peer, not a
    // race tp_sshd must absorb.
    test(
      'a duplicate open confirmation for a live channel draws the '
      'non-opening disconnect',
      () async {
        final forwardedConnections = StreamController<ForwardConnection>();
        addTearDown(forwardedConnections.close);
        var successes = 0;
        Uint8List? openPayload;
        final opened = Completer<void>();
        final (connection, client) = await startRawAuthenticatedConnection(
          forwarding: SSHForwardingConfig(
            allowTcpForwarding: SshTcpForwardingMode.remote,
            dialSocket: (host, port) => throw StateError('no dial'),
            bindServerSocket: (address, port) async => _FakeServerSocketHandle(
              forwardedConnections.stream,
            ),
          ),
          onServerMessage: (payload) {
            switch (SSHMessage.readMessageId(payload)) {
              case SSH_Message_Request_Success.messageId:
                successes += 1;
              case SSH_Message_Channel_Open.messageId:
                openPayload = payload;
                if (!opened.isCompleted) opened.complete();
            }
          },
        );
        addTearDown(connection.close);
        addTearDown(client.close);

        // Bind a forwarded port, then feed the listener one accepted
        // connection: the server opens a forwarded-tcpip channel for it.
        client.sendPacket(
          SSH_Message_Global_Request.tcpipForward('127.0.0.1', 0).encode(),
        );
        await waitUntil(() => successes == 1);
        forwardedConnections.add(_IdleForwardConnection());
        await opened.future.timeout(const Duration(seconds: 5));
        final open = SSH_Message_Channel_Open.decode(openPayload!);
        final confirmation = SSH_Message_Channel_Confirmation(
          recipientChannel: open.senderChannel,
          senderChannel: 5000,
          initialWindowSize: 2 * 1024 * 1024,
          maximumPacketSize: 32768,
          data: Uint8List(0),
        );
        client.sendPacket(confirmation.encode());
        await waitUntil(() => connection.channels.isNotEmpty);

        // The stimulus: the same confirmation again — the channel it
        // created is still live, so sshd answers the non-opening fatal.
        client.sendPacket(confirmation.encode());
        final error = await client.done
            .timeout(const Duration(seconds: 5))
            .then<Object>(
              (value) =>
                  throw StateError('connection closed without a reason'),
              onError: (Object error, _) => error,
            );
        expect(error, isA<SSHDisconnectError>());
        expect(
          (error as SSHDisconnectError).reasonCode,
          2, // SSH_DISCONNECT_PROTOCOL_ERROR
        );
        expect(
          error.message,
          'Received open confirmation for non-opening channel '
          '${open.senderChannel}.',
        );
      },
    );

    // F5's never-existed class: a verdict for an id this server never
    // opened draws channel_from_packet_id's disconnect, unchanged.
    test(
      'an open confirmation for an id this server never opened draws the '
      'nonexistent-channel disconnect',
      () async {
        final (connection, client) = await startRawAuthenticatedConnection();
        addTearDown(connection.close);
        addTearDown(client.close);

        client.sendPacket(
          SSH_Message_Channel_Confirmation(
            recipientChannel: 99999,
            senderChannel: 5001,
            initialWindowSize: 2 * 1024 * 1024,
            maximumPacketSize: 32768,
            data: Uint8List(0),
          ).encode(),
        );
        final error = await client.done
            .timeout(const Duration(seconds: 5))
            .then<Object>(
              (value) =>
                  throw StateError('connection closed without a reason'),
              onError: (Object error, _) => error,
            );
        expect(error, isA<SSHDisconnectError>());
        expect(
          (error as SSHDisconnectError).message,
          'open confirmation packet referred to nonexistent channel 99999',
        );
      },
    );
  });

  test('a reset forwarded connection never leaks an unhandled error', () async {
    // F13: the pump must consume connection.done's error channel. A TCP
    // reset completes the socket's done future with a SocketException; the
    // pump used to drop the future returned by whenComplete, so the error
    // escaped into the embedder's zone as an unhandled exception.
    //
    // The channel, the connection and the pump are all created inside the
    // guarded zone: a future's error is routed through the zone it was
    // created in, so creating the connection outside would route the error
    // around the guard and the test would not see what the pump does.
    final debugLines = <String>[];
    final strayErrors = <Object>[];
    await runZonedGuarded(() async {
      final channel = SSHServerChannel(
        recipientChannel: 0,
        ourChannel: 7,
        channelType: 'forwarded-tcpip',
        peerInitialWindowSize: SSHServerChannel.initialReceiveWindow,
        peerMaximumPacketSize: SSHServerChannel.maximumPacketSize,
        sendPacket: (_) {},
        onClosed: (_) {},
      );
      final connection = _ResetForwardConnection();
      final pump = pumpForwardConnection(
        channel,
        connection,
        printDebug: (message) => debugLines.add(message ?? ''),
      );
      connection.reset();
      // The pump itself must finish normally — the reset is contained, not
      // propagated — and any would-be unhandled error surfaces in this
      // window.
      await pump.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // The channel still finished: the reset tears the forwarding down, it
      // does not hang it.
      expect(channel.isClosed, isTrue);
      await connection.close();
    }, (error, stackTrace) => strayErrors.add(error));

    expect(strayErrors, isEmpty);
    // The reset is diagnosed through the package's printDebug seam.
    expect(debugLines, isNotEmpty);
  });

  test('non-loopback bind requests are refused without consulting the seam',
      () async {
    // A permissive seam that records every call: the loopback-only rule must
    // refuse the request before the seam is ever invoked.
    final seamAddresses = <String>[];
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      forwarding: SSHForwardingConfig(
        allowTcpForwarding: SshTcpForwardingMode.remote,
        dialSocket: (host, port) => throw StateError('no dial'),
        bindServerSocket: (address, port) async {
          seamAddresses.add(address.address);
          return _RealServerSocketHandle(
            await ServerSocket.bind(address, port),
          );
        },
      ),
    );
    // '' (the client's "all interfaces" default), the wildcard addresses,
    // another interface and any other host are all refused.
    for (final host in ['', '0.0.0.0', '::', '192.168.1.10', 'example.com']) {
      expect(
        await client.forwardRemote(host: host, port: 0),
        isNull,
        reason: 'tcpip-forward for $host should be refused',
      );
    }
    expect(seamAddresses, isEmpty);

    await client.close();
    await server.close();
  });

  test('tcpip-forward without a forwarding config is refused', () async {
    // No forwarding config: the forwarding surface is hard-disabled, and a
    // tcpip-forward request — even for a perfectly loopback address — gets a
    // Request_Failure reply rather than a hang or a bind attempt.
    var failures = 0;
    final (connection, client) = await startRawAuthenticatedConnection(
      forwarding: null,
      onServerMessage: (payload) {
        if (SSHMessage.readMessageId(payload) ==
            SSH_Message_Request_Failure.messageId) {
          failures += 1;
        }
      },
    );
    client.sendPacket(
      SSH_Message_Global_Request.tcpipForward('127.0.0.1', 0).encode(),
    );
    await waitUntil(() => failures == 1);

    await connection.close();
    client.close();
  });

  test('cancel-tcpip-forward releases the bind', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      forwarding: _testForwardingConfig(bindServerSocket: _bindRealLoopback),
    );
    final forward = await client.forwardRemote(host: '127.0.0.1', port: 0);
    final port = forward!.port;

    final cancelled = await client.cancelForwardRemote(forward);
    expect(cancelled, isTrue);

    // The released loopback port refuses connections.
    await expectLater(
      Socket.connect('127.0.0.1', port),
      throwsA(isA<SocketException>()),
    );

    await client.close();
    await server.close();
  });

  test('connection close releases everything that connection bound', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      forwarding: _testForwardingConfig(bindServerSocket: _bindRealLoopback),
    );
    // 'localhost' is a loopback spelling too: bound on IPv4 loopback.
    final forward = await client.forwardRemote(host: 'localhost', port: 0);
    final port = forward!.port;

    // Closing the server side tears the connection — and with it every bind
    // the connection made — down to the last socket.
    await server.close();
    await client.close();

    await expectLater(
      Socket.connect('127.0.0.1', port),
      throwsA(isA<SocketException>()),
    );
  });

  test('tcpip-forward replies with the bound port; unknown cancels are refused',
      () async {
    var successes = 0;
    var failures = 0;
    int? boundPort;
    final (connection, client) = await startRawAuthenticatedConnection(
      forwarding: _testForwardingConfig(bindServerSocket: _bindRealLoopback),
      onServerMessage: (payload) {
        switch (SSHMessage.readMessageId(payload)) {
          case SSH_Message_Request_Success.messageId:
            successes += 1;
            if (boundPort == null) {
              boundPort = SSHMessageReader(
                SSH_Message_Request_Success.decode(payload).requestData,
              ).readUint32();
            }
          case SSH_Message_Request_Failure.messageId:
            failures += 1;
        }
      },
    );

    // Bind an ephemeral loopback port; the success payload carries the port
    // that was actually bound.
    client.sendPacket(
      SSH_Message_Global_Request.tcpipForward('127.0.0.1', 0).encode(),
    );
    await waitUntil(() => successes == 1);
    expect(boundPort, greaterThan(0));

    // Cancelling the live bind succeeds...
    client.sendPacket(
      SSH_Message_Global_Request.cancelTcpipForward(
        bindAddress: '127.0.0.1',
        bindPort: boundPort!,
      ).encode(),
    );
    await waitUntil(() => successes == 2);

    // ...while a cancel naming a bind the server no longer holds is refused
    // (a deliberate, testable policy: an unknown cancel is a Failure, so a
    // client can tell a released bind from a mistaken one).
    client.sendPacket(
      SSH_Message_Global_Request.cancelTcpipForward(
        bindAddress: '127.0.0.1',
        bindPort: boundPort!,
      ).encode(),
    );
    await waitUntil(() => failures == 1);

    await connection.close();
    client.close();
  });

  test('permitOpen gates the bind target before the seam is consulted',
      () async {
    final seamCalls = <(String, int)>[];
    var allow = false;
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      forwarding: SSHForwardingConfig(
        allowTcpForwarding: SshTcpForwardingMode.remote,
        permitOpen: (connection, host, port) async {
          return allow;
        },
        dialSocket: (host, port) => throw StateError('no dail'),
        bindServerSocket: (address, port) async {
          seamCalls.add((address.address, port));
          return _RealServerSocketHandle(
              await ServerSocket.bind(address, port));
        },
        dialTimeout: const Duration(seconds: 5),
      ),
    );
    expect(await client.forwardRemote(host: '127.0.0.1', port: 0), isNull);
    expect(seamCalls, isEmpty);
    allow = true;
    final forward = await client.forwardRemote(host: '127.0.0.1', port: 0);
    expect(forward, isNotNull);
    // cancelForwardRemote, not forward.close(): the fork's close() waits on
    // its connections controller's done event, which is only delivered once
    // something listens to the stream.
    await client.cancelForwardRemote(forward!);
    await client.close();
    await server.close();
  });

  test('remote forwarding is refused when the mode lacks the remote bit',
      () async {
    var failures = 0;
    final (connection, client) = await startRawAuthenticatedConnection(
      forwarding: SSHForwardingConfig(
        allowTcpForwarding: SshTcpForwardingMode.local,
        permitOpen: null,
        dialSocket: (host, port) => throw StateError('no dial'),
        bindServerSocket: _bindRealLoopback,
        dialTimeout: const Duration(seconds: 5),
      ),
      onServerMessage: (payload) {
        if (SSHMessage.readMessageId(payload) ==
            SSH_Message_Request_Failure.messageId) {
          failures += 1;
        }
      },
    );
    client.sendPacket(
      SSH_Message_Global_Request.tcpipForward('127.0.0.1', 0).encode(),
    );
    await waitUntil(() => failures == 1);
    await connection.close();
    client.close();
  });
}

/// The forwarding config the forward tests configure the bind seam with:
/// remote forwarding on, a dial seam that must never be reached.
SSHForwardingConfig _testForwardingConfig({
  required SSHBindServerSocket bindServerSocket,
}) =>
    SSHForwardingConfig(
      allowTcpForwarding: SshTcpForwardingMode.remote,
      dialSocket: (host, port) => throw StateError('no dial'),
      bindServerSocket: bindServerSocket,
    );

/// Binds a real loopback [ServerSocket] through the seam.
Future<ServerSocketHandle> _bindRealLoopback(
  InternetAddress address,
  int port,
) async =>
    _RealServerSocketHandle(await ServerSocket.bind(address, port));

/// Adapts a real [ServerSocket] to [ServerSocketHandle].
class _RealServerSocketHandle implements ServerSocketHandle {
  _RealServerSocketHandle(this._socket);

  final ServerSocket _socket;

  @override
  int get port => _socket.port;

  @override
  Stream<ForwardConnection> get connections =>
      _socket.map(_RealForwardConnection.new);

  @override
  Future<void> close() => _socket.close();
}

/// Adapts a real [Socket] to [ForwardConnection].
class _RealForwardConnection implements ForwardConnection {
  _RealForwardConnection(this._socket);

  final Socket _socket;

  @override
  Stream<Uint8List> get input => _socket;

  @override
  StreamSink<List<int>> get output => _socket;

  @override
  Future<void> get done => _socket.done;

  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;

  @override
  int get remotePort => _socket.remotePort;

  @override
  void destroy() => _socket.destroy();
}

/// A [ServerSocketHandle] whose accepted connections are pushed by the test
/// through a controller, with a fixed bound port.
class _FakeServerSocketHandle implements ServerSocketHandle {
  _FakeServerSocketHandle(this._connections);

  final Stream<ForwardConnection> _connections;

  @override
  int get port => 41234;

  @override
  Stream<ForwardConnection> get connections => _connections;

  @override
  Future<void> close() async {}
}

/// A [ForwardConnection] whose peer never says anything and never goes away:
/// an accepted forwarded connection at rest.
class _IdleForwardConnection implements ForwardConnection {
  final _inputController = StreamController<Uint8List>();

  @override
  Stream<Uint8List> get input => _inputController.stream;

  @override
  StreamSink<List<int>> get output => _DiscardSink();

  @override
  Future<void> get done => Completer<void>().future;

  @override
  InternetAddress get remoteAddress => InternetAddress.loopbackIPv4;

  @override
  int get remotePort => 54321;

  @override
  void destroy() {}
}

/// A [ForwardConnection] whose peer resets the connection mid-stream: its
/// [ForwardConnection.done] completes with the SocketException a TCP RST
/// produces on a real socket.
class _ResetForwardConnection implements ForwardConnection {
  final _inputController = StreamController<Uint8List>();
  final _doneCompleter = Completer<void>();

  @override
  Stream<Uint8List> get input => _inputController.stream;

  @override
  StreamSink<List<int>> get output => _DiscardSink();

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  InternetAddress get remoteAddress => InternetAddress.loopbackIPv4;

  @override
  int get remotePort => 54321;

  @override
  void destroy() {}

  /// The peer's RST lands while the pump is running.
  void reset() {
    _doneCompleter.completeError(
      const SocketException('Connection reset by peer'),
    );
  }

  Future<void> close() async {
    await _inputController.close();
  }
}

/// A [StreamSink] that swallows everything written to it.
class _DiscardSink implements StreamSink<List<int>> {
  @override
  void add(List<int> data) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}
}
