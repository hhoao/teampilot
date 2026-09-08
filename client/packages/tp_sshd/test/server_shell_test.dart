@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
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
}
