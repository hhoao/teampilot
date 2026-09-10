@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/protocol.dart'
    show
        SSHMessage,
        SSHMessageReader,
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
      bindServerSocket: _bindRealLoopback,
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

  test('non-loopback bind requests are refused without consulting the seam',
      () async {
    // A permissive seam that records every call: the loopback-only rule must
    // refuse the request before the seam is ever invoked.
    final seamAddresses = <String>[];
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      bindServerSocket: (address, port) async {
        seamAddresses.add(address.address);
        return _RealServerSocketHandle(await ServerSocket.bind(address, port));
      },
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

  test('cancel-tcpip-forward releases the bind', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      bindServerSocket: _bindRealLoopback,
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
      bindServerSocket: _bindRealLoopback,
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
      bindServerSocket: _bindRealLoopback,
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
}

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
