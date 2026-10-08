@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';

/// A process whose stdout the test pumps by hand, standing in for a
/// long-running streaming program (`head -c N /dev/zero` and friends): the
/// test decides when data flows, so a rekey can be made to land mid-stream.
class _StreamingProcess implements SSHServerProcess {
  final _stdin = StreamController<List<int>>();
  final _stdout = StreamController<Uint8List>();
  final _stderr = StreamController<Uint8List>();
  final _exit = Completer<int>();

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void kill() {
    if (!_exit.isCompleted) _exit.complete(9);
  }

  @override
  StreamSink<List<int>> get stdin => _stdin.sink;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  void emit(Uint8List chunk) => _stdout.add(chunk);

  void finish([int code = 0]) {
    _stdout.close();
    _stderr.close();
    if (!_exit.isCompleted) _exit.complete(code);
  }
}

void main() {
  test('rekey defaults are 1 GiB and 1 hour', () {
    final config = SSHServerConfig(
      hostKeyPair: testHostKey,
      expectedUsername: 'user',
      authenticate: (_) async => true,
    );
    expect(config.rekeyBytes, 1024 * 1024 * 1024);
    expect(config.rekeyInterval, const Duration(hours: 1));
  });

  test('server initiates rekey after rekeyBytes of outbound traffic', () async {
    final process = _StreamingProcess();
    final (client, connection) = await startDualConnection(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      processFactory: (argv, cwd, env) async => process,
      rekeyBytes: 64 * 1024,
      rekeyInterval: null,
    );
    addTearDown(client.close);
    addTearDown(connection.close);

    final session = await client.execute(
      TpExecCodec.encode(const SSHExecRequest(argv: ['stream'])),
    );
    // 4 x 32 KiB = 128 KiB of outbound server traffic against a 64 KiB
    // threshold: the second chunk crosses it, so an unprompted KEXINIT goes
    // out mid-stream without the client ever asking for one.
    for (var i = 0; i < 4; i++) {
      process.emit(Uint8List(32 * 1024));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    process.finish(0);
    await session.done.timeout(const Duration(seconds: 5));

    expect(connection.rekeyCount, greaterThanOrEqualTo(1));
    expect(client.isClosed, isFalse);
  });

  test('rekey interval timer fires on an idle session', () async {
    final process = _StreamingProcess();
    final (client, connection) = await startDualConnection(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      processFactory: (argv, cwd, env) async => process,
      rekeyBytes: null,
      rekeyInterval: const Duration(milliseconds: 200),
    );
    addTearDown(client.close);
    addTearDown(connection.close);

    // No traffic at all: the idle session rotates its keys on the timer
    // alone, the case a byte counter can never reach (audit B07).
    await waitUntil(() => connection.rekeyCount >= 1);
    expect(client.isClosed, isFalse);

    // The session still serves after the rotation: a fresh exec round-trips.
    final session = await client.execute(
      TpExecCodec.encode(const SSHExecRequest(argv: ['post'])),
    );
    process.emit(Uint8List(4));
    process.finish(0);
    await session.done.timeout(const Duration(seconds: 5));
    expect(await session.waitForExit(), 0);
  });

  test('an open channel survives a mid-stream server-initiated rekey', () async {
    final process = _StreamingProcess();
    final (client, connection) = await startDualConnection(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      processFactory: (argv, cwd, env) async => process,
      rekeyBytes: 16 * 1024,
      rekeyInterval: null,
    );
    addTearDown(client.close);
    addTearDown(connection.close);

    final session = await client.execute(
      TpExecCodec.encode(const SSHExecRequest(argv: ['stream'])),
    );
    // 8 chunks of 8 KiB with pauses between them: the 16 KiB threshold is
    // crossed from the third chunk on, so at least one rotation lands with
    // data still in flight (the exchange window the audit's B02 family is
    // about). Every chunk carries its own index so integrity is checkable.
    final received = BytesBuilder();
    final drain = () async {
      await for (final chunk in session.stdout) {
        received.add(chunk);
      }
    }();
    for (var i = 0; i < 8; i++) {
      final chunk = Uint8List(8 * 1024)..[0] = i;
      process.emit(chunk);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    process.finish(0);

    await session.done.timeout(const Duration(seconds: 10));
    await drain.timeout(const Duration(seconds: 10));

    final bytes = received.takeBytes();
    expect(bytes.length, 8 * 8 * 1024);
    for (var i = 0; i < 8; i++) {
      expect(bytes[i * 8 * 1024], i, reason: 'chunk $i corrupted or lost');
    }
    expect(await session.waitForExit(), 0);
    expect(connection.rekeyCount, greaterThanOrEqualTo(1));
    expect(client.isClosed, isFalse);
  });

  test('rekey disabled when both knobs are null', () async {
    final process = _StreamingProcess();
    final (client, connection) = await startDualConnection(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      processFactory: (argv, cwd, env) async => process,
      rekeyBytes: null,
      rekeyInterval: null,
    );
    addTearDown(client.close);
    addTearDown(connection.close);

    final session = await client.execute(
      TpExecCodec.encode(const SSHExecRequest(argv: ['stream'])),
    );
    for (var i = 0; i < 4; i++) {
      process.emit(Uint8List(32 * 1024));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    process.finish(0);
    await session.done.timeout(const Duration(seconds: 5));

    // Past the byte volume that would trip a threshold, plus the quiet time
    // an interval would need: no unprompted KEXINIT either way.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(connection.rekeyCount, 0);
    expect(client.isClosed, isFalse);
  });
}
