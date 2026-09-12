@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHChannelOpenError;
import 'package:dartssh2/protocol.dart'
    show
        SSHMessage,
        SSH_Message_Channel_Open,
        SSH_Message_Channel_Open_Failure,
        SSH_Message_Global_Request,
        SSH_Message_Request_Failure;
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';

void main() {
  final forwardingConfig =
      ({SSHDialSocket? dial, Future<bool> Function(SSHServerConnection, String, int)? permit}) =>
          SSHForwardingConfig(
            allowTcpForwarding: SshTcpForwardingMode.both,
            permitOpen: permit,
            dialSocket: dial ?? (host, port) => throw StateError('no dial'),
            bindServerSocket: _bindRealLoopback,
            dialTimeout: const Duration(seconds: 5),
          );

  Future<ServerSocket> _echoListener() async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    listener.listen((socket) {
      socket.listen((data) => socket.add(data), onDone: socket.close);
    });
    return listener;
  }

  test('direct-tcpip round-trips bytes over a real loopback target', () async {
    final listener = await _echoListener();
    addTearDown(listener.close);
    final echoed = Completer<void>();
    final seenHosts = <String>[];
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      forwarding: forwardingConfig(dial: (host, port) async {
        seenHosts.add(host);
        return _RealForwardConnection(await Socket.connect(host, port));
      }),
    );
    final channel = await client.forwardLocal('127.0.0.1', listener.port);
    final got = StringBuffer();
    channel.stream.listen((data) {
      got.write(utf8.decode(data));
      if (!echoed.isCompleted && got.toString().contains('ping')) {
        echoed.complete();
      }
    });
    channel.sink.add(utf8.encode('ping'));
    await echoed.future.timeout(const Duration(seconds: 5));
    expect(got.toString(), 'ping');
    expect(seenHosts, ['127.0.0.1']);
    await channel.close();
    await client.close();
    await server.close();
  });

  test('host string is handed to the seam verbatim', () async {
    final seen = <String>[];
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      forwarding: forwardingConfig(dial: (host, port) async {
        seen.add(host);
        return _RealForwardConnection(await Socket.connect('127.0.0.1', port));
      }),
    );
    final listener = await _echoListener();
    addTearDown(listener.close);
    await client.forwardLocal('localhost', listener.port);
    expect(seen, ['localhost']);
    await client.close();
    await server.close();
  });

  test('forwarding disabled refuses direct-tcpip with reason 1', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
    );
    await expectLater(
      client.forwardLocal('127.0.0.1', 80),
      throwsA(isA<SSHChannelOpenError>()
          .having((e) => e.code, 'code',
              SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited)
          .having((e) => e.code, 'wire', 1)),
    );
    await client.close();
    await server.close();
  });

  test('permitOpen denial refuses with reason 1 and never dials', () async {
    var dialed = 0;
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      forwarding: forwardingConfig(
        permit: (conn, host, port) async => host == '127.0.0.1',
        dial: (host, port) async {
          dialed += 1;
          throw StateError('should not dial');
        },
      ),
    );
    await expectLater(
      client.forwardLocal('10.0.0.1', 80),
      throwsA(isA<SSHChannelOpenError>()
          .having((e) => e.code, 'code',
              SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited)),
    );
    expect(dialed, 0);
    await client.close();
    await server.close();
  });

  test('dial failure refuses with reason 2 and keeps the connection alive',
      () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      forwarding: forwardingConfig(
        dial: (host, port) async =>
            _RealForwardConnection(await Socket.connect(host, port)),
      ),
    );
    await expectLater(
      client.forwardLocal('127.0.0.1', 1),
      throwsA(isA<SSHChannelOpenError>()
          .having((e) => e.code, 'code',
              SSH_Message_Channel_Open_Failure.codeConnectFailed)
          .having((e) => e.code, 'wire', 2)),
    );
    await expectLater(client.ping(), completes); // 连接存活
    await client.close();
    await server.close();
  });

  test('out-of-range target port refuses with reason 1', () async {
    // raw 驱动（真实 client 会拒绝 0x10000 端口）
    final refused = Completer<void>();
    final (connection, client) = await startRawAuthenticatedConnection(
      forwarding: forwardingConfig(),
      onServerMessage: (payload) {
        final m = SSHMessage.readMessageId(payload);
        if (m == SSH_Message_Channel_Open_Failure.messageId &&
            SSH_Message_Channel_Open_Failure.decode(payload).reasonCode ==
                SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited &&
            !refused.isCompleted) {
          refused.complete();
        }
      },
    );
    client.sendPacket(
      SSH_Message_Channel_Open.directTcpip(
        senderChannel: 3,
        initialWindowSize: 2 * 1024 * 1024,
        maximumPacketSize: 32768,
        host: '127.0.0.1',
        port: 0x10000,
        originatorIP: '127.0.0.1',
        originatorPort: 5,
      ).encode(),
    );
    await refused.future.timeout(const Duration(seconds: 5));
    await connection.close();
    client.close();
  });

  test('direct-tcpip channels count against the per-connection cap', () async {
    final listener = await _echoListener();
    addTearDown(listener.close);
    final (client, connection) = await startDualConnection(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      forwarding: forwardingConfig(dial: (host, port) async =>
          _RealForwardConnection(await Socket.connect(host, port))),
    );
    // 10 个 session 通道（cap）后，direct-tcpip 打开被 reason 4 拒绝、表不膨胀：
    // 拒绝恰在分派前发生，拨号不会执行。
    for (var i = 0; i < 10; i++) {
      await openClientSessionChannel(client);
    }
    expect(connection.channels.length, 10);
    await expectLater(
      client.forwardLocal('127.0.0.1', listener.port),
      throwsA(isA<SSHChannelOpenError>()
          .having((e) => e.code, 'code',
              SSH_Message_Channel_Open_Failure.codeResourceShortage)
          .having((e) => e.code, 'wire', 4)),
    );
    expect(connection.channels.length, 10);
    await connection.close();
    await client.close();
  });

  test('connection close destroys the dialed socket', () async {
    final listener = await _echoListener();
    addTearDown(listener.close);
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      forwarding: forwardingConfig(dial: (host, port) async =>
          _RealForwardConnection(await Socket.connect(host, port))),
    );
    final channel = await client.forwardLocal('127.0.0.1', listener.port);
    await server.close();
    await channel.done.timeout(const Duration(seconds: 5)); // 拨入 socket 被销毁
    await client.close();
  });

  test('tcpip-forward for a port above INT_MAX is refused before binding',
      () async {
    // OpenSSH serverloop.c refuses a tcpip-forward whose port exceeds INT_MAX
    // before it ever consults the bind listener; the bind seam must stay
    // untouched.
    var bindAttempts = 0;
    var failures = 0;
    final (connection, client) = await startRawAuthenticatedConnection(
      forwarding: SSHForwardingConfig(
        allowTcpForwarding: SshTcpForwardingMode.remote,
        dialSocket: (host, port) => throw StateError('no dial'),
        bindServerSocket: (address, port) async {
          bindAttempts += 1;
          return _bindRealLoopback(address, port);
        },
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
      SSH_Message_Global_Request.tcpipForward('127.0.0.1', 0x80000000)
          .encode(),
    );
    await waitUntil(() => failures == 1);
    expect(bindAttempts, 0);

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