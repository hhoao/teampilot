@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart'
    show SSHChannelOpenError, SSHDisconnectError;
import 'package:dartssh2/protocol.dart'
    show
        SSHMessage,
        SSH_Message_Channel_Confirmation,
        SSH_Message_Channel_Data,
        SSH_Message_Channel_Open,
        SSH_Message_Channel_Open_Failure,
        SSH_Message_Channel_Window_Adjust,
        SSH_Message_Global_Request,
        SSH_Message_Request_Failure;
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';

void main() {
  final forwardingConfig =
      ({SSHDialSocket? dial, Future<bool> Function(SSHServerConnection, String, int)? permit, Duration? dialTimeout}) =>
          SSHForwardingConfig(
            allowTcpForwarding: SshTcpForwardingMode.both,
            permitOpen: permit,
            dialSocket: dial ?? (host, port) => throw StateError('no dial'),
            bindServerSocket: _bindRealLoopback,
            dialTimeout: dialTimeout ?? const Duration(seconds: 5),
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

  test('throwing permitOpen yields reason 1 and never an unhandled error',
      () async {
    // permitOpen throws for any target
    var dialed = 0;
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      forwarding: forwardingConfig(
        permit: (conn, host, port) async => throw StateError('boom'),
        dial: (host, port) async {
          dialed += 1;
          throw StateError('should not dial');
        },
      ),
    );
    // expect forwardLocal throws SSHChannelOpenError code 1 (wire value 1)
    await expectLater(
      client.forwardLocal('10.0.0.1', 80),
      throwsA(isA<SSHChannelOpenError>()
          .having((e) => e.code, 'code',
              SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited)
          .having((e) => e.code, 'wire', 1)),
    );
    expect(dialed, 0);
    // then client.ping() completes (connection alive, no zone error).
    await expectLater(client.ping(), completes);
    await client.close();
    await server.close();
  });

  test('never-completing dial is refused at the dial timeout, connection alive',
      () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      forwarding: forwardingConfig(
        dialTimeout: const Duration(milliseconds: 100),
        dial: (host, port) => Completer<ForwardConnection>().future,
      ),
    );
    await expectLater(
      client.forwardLocal('127.0.0.1', 80),
      throwsA(isA<SSHChannelOpenError>()
          .having((e) => e.code, 'code',
              SSH_Message_Channel_Open_Failure.codeConnectFailed)
          .having((e) => e.code, 'wire', 2)),
    );
    await expectLater(client.ping(), completes);
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

  test('out-of-range originator port refuses with reason 1', () async {
    // raw 驱动（真实 client 不会发送 >0xFFFF 的 originator 端口）
    final refused = Completer<void>();
    final (connection, client) = await startRawAuthenticatedConnection(
      forwarding: forwardingConfig(),
      onServerMessage: (payload) {
        final m = SSHMessage.readMessageId(payload);
        if (m == SSH_Message_Channel_Open_Failure.messageId &&
            SSH_Message_Channel_Open_Failure.decode(payload).reasonCode ==
                SSH_Message_Channel_Open_Failure
                    .codeAdministrativelyProhibited &&
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
        port: 80,
        originatorIP: '127.0.0.1',
        originatorPort: 0x10000,
      ).encode(),
    );
    await refused.future.timeout(const Duration(seconds: 5));
    await connection.close();
    client.close();
  });

  test('post-dial cap re-check refuses a channel that crossed the cap while dialing',
      () async {
    // 时序：先发 direct-tcpip open（拨号卡在 gate 上），再开一个 session 通道
    // 把 cap=1 占满，最后放开 gate → post-dial 复检以 reason 4 拒绝、拨入的
    // socket 被销毁、通道表不变。
    final gate = Completer<void>();
    final dialed = Completer<void>();
    final listener = await _echoListener();
    addTearDown(listener.close);
    final (client, connection) = await startDualConnection(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      maxChannels: 1,
      forwarding: forwardingConfig(dial: (host, port) async {
        if (!dialed.isCompleted) dialed.complete();
        await gate.future; // 卡住，等 session 通道先占满 cap
        return _RealForwardConnection(await Socket.connect(host, port));
      }),
    );

    final open = client.forwardLocal('127.0.0.1', listener.port);
    // 拨号已在进行（卡在 gate），此刻通道表是全空的。
    await dialed.future.timeout(const Duration(seconds: 5));
    expect(connection.channels, isEmpty);
    // 用 session 通道占满 cap=1（接收时点复检放行，因为它先于拨号注册）。
    final session = await openClientSessionChannel(client);
    await waitUntil(() => connection.channels.length == 1);
    // 放开 gate：post-dial 复检拒绝，而不是确认。
    gate.complete();
    await expectLater(
      open,
      throwsA(isA<SSHChannelOpenError>()
          .having((e) => e.code, 'code',
              SSH_Message_Channel_Open_Failure.codeResourceShortage)
          .having((e) => e.code, 'wire', 4)),
    );
    expect(connection.channels.length, 1); // session 通道仍占着，没被膨胀
    session.close();
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

  test('a forwarded peer that never reads keeps the granted window a bound',
      () async {
    // F4's direct-tcpip half (A16): the flood target never reads, so the
    // forward pump's writes never complete, nothing is re-granted, and a
    // peer that keeps sending past the granted window beyond sshd's 10%
    // grace margin is disconnected instead of buffered unboundedly.
    final confirmed = Completer<void>();
    final adjusts = <int>[];
    final (connection, client) = await startRawAuthenticatedConnection(
      forwarding: forwardingConfig(
        dial: (host, port) async => _GatedForwardConnection(),
      ),
      onServerMessage: (payload) {
        switch (SSHMessage.readMessageId(payload)) {
          case SSH_Message_Channel_Confirmation.messageId:
            if (!confirmed.isCompleted) confirmed.complete();
          case SSH_Message_Channel_Window_Adjust.messageId:
            adjusts.add(
              SSH_Message_Channel_Window_Adjust.decode(payload).bytesToAdd,
            );
        }
      },
    );
    addTearDown(connection.close);
    addTearDown(client.close);

    client.sendPacket(
      SSH_Message_Channel_Open.directTcpip(
        senderChannel: 100,
        initialWindowSize: 2 * 1024 * 1024,
        maximumPacketSize: 32768,
        host: '127.0.0.1',
        port: 80,
        originatorIP: '127.0.0.1',
        originatorPort: 5,
      ).encode(),
    );
    await confirmed.future;
    final serverChannel = connection.channels.keys.single;

    // 64 chunks of 32768 spend the 2 MiB window; the seventh overflowing
    // chunk crosses the 10% grace and draws the disconnect.
    final chunk = Uint8List(32768);
    for (var i = 0; i < 71; i++) {
      client.sendPacket(
        SSH_Message_Channel_Data(
          recipientChannel: serverChannel,
          data: chunk,
        ).encode(),
      );
    }
    await expectLater(
      client.done.timeout(const Duration(seconds: 5)),
      throwsA(
        isA<SSHDisconnectError>()
            .having((error) => error.reasonCode, 'reasonCode', 2)
            .having(
              (error) => error.message,
              'message',
              'channel $serverChannel: peer ignored channel window',
            ),
      ),
    );
    expect(adjusts, isEmpty);
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

/// A forwarded connection whose peer never reads: every write waits on a
/// gate the test never opens, standing in for A16's silent flood target.
/// Its input never ends either — a closed stream would finish the channel
/// before the flood even starts.
class _GatedForwardConnection implements ForwardConnection {
  final _output = _GatedOutputSink();
  final _input = StreamController<Uint8List>();

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  StreamSink<List<int>> get output => _output;

  @override
  Future<void> get done => Completer<void>().future;

  @override
  InternetAddress get remoteAddress => InternetAddress.loopbackIPv4;

  @override
  int get remotePort => 80;

  @override
  void destroy() {}
}

class _GatedOutputSink implements StreamSink<List<int>> {
  final _gate = Completer<void>();

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => _gate.future;

  @override
  Future<void> close() => Future.value();

  @override
  Future<void> get done => Future.value();
}