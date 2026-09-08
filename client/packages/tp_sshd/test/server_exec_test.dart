@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';

/// Fake process echoing argv back on stdout with a configurable exit code.
class _EchoProcess implements SSHServerProcess {
  _EchoProcess(this.argv);

  final List<String> argv;
  final _stdin = StreamController<List<int>>();
  final _stdout = StreamController<Uint8List>();
  final _stderr = StreamController<Uint8List>();

  @override
  Future<int> get exitCode async => 17;

  @override
  void kill() {}

  @override
  StreamSink<List<int>> get stdin => _stdin.sink;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  void start() {
    _stdout.add(Uint8List.fromList(utf8.encode(argv.join(' '))));
    _stdout.close();
    _stderr.close();
  }
}

void main() {
  test('structured exec spawns argv and reports exit code', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      processFactory: (argv, cwd, env) async {
        expect(cwd, 'C:\\work\\demo');
        expect(env['TEAMPilot_TEST'], '1');
        final process = _EchoProcess(argv)..start();
        return process;
      },
    );
    final session = await client.execute(
      TpExecCodec.encode(
        const SSHExecRequest(
          argv: ['claude', '--version'],
          cwd: r'C:\work\demo',
          env: {'TEAMPilot_TEST': '1'},
        ),
      ),
    );
    final output = await utf8.decoder.bind(session.stdout).join();
    expect(output, 'claude --version');
    // waitForExit is the fork's public API for the exit status; the raw
    // getter only reflects what has already been reported.
    expect(await session.waitForExit(), 17);
    client.close();
    await server.close();
  });

  test('plain shell-string exec is rejected', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      processFactory: (argv, cwd, env) async => _EchoProcess(argv)..start(),
    );
    await expectLater(
      client.execute('rm -rf /'), // no tp1: prefix
      throwsA(anything),
    );
    client.close();
    await server.close();
  });

  test('host-info query is answered without spawning', () async {
    var factoryCalled = false;
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      hostInfo: () => const SSHHostInfo(
        platform: 'windows',
        osUser: 'dev',
        elevated: false,
        inDocker: false,
        shell: 'powershell',
      ),
      processFactory: (argv, cwd, env) async {
        factoryCalled = true;
        return _EchoProcess(argv)..start();
      },
    );
    final session = await client.execute(TpExecCodec.encodeHostInfoQuery());
    final raw = await utf8.decoder.bind(session.stdout).join();
    final info = SSHHostInfo.fromJson(raw);
    expect(info.platform, 'windows');
    expect(factoryCalled, isFalse);
    client.close();
    await server.close();
  });
}
