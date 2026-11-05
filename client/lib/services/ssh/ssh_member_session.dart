import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../models/ssh_profile.dart';
import '../chat/team_bus/remote/reverse_tunnel.dart';
import 'ssh_client_factory.dart';
import 'worker/ssh_worker_member_session.dart';
import 'worker/ssh_worker_storage_types.dart';

/// Dedicated SSH connection for one remote member's session plane.
///
/// Production calls are primitive worker proxies: no [SSHClient] or
/// [SSHSession] crosses this service boundary. The direct client adapter is
/// retained only by [testing] and injected factory connectors.
class SshMemberSession {
  SshMemberSession._(
    this.profile,
    this._session, {
    required ReverseTunnel Function({String bindHost}) newReverseTunnel,
  }) : _newReverseTunnel = newReverseTunnel;

  final SshProfile profile;
  final SshWorkerMemberSession _session;
  final ReverseTunnel Function({String bindHost}) _newReverseTunnel;

  static Future<SshMemberSession> open(
    SshClientFactory factory,
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final transport = await factory.openMemberTransport(
      profile,
      timeout: timeout,
    );
    try {
      final session = await SshWorkerMemberSession.open(
        profile: profile,
        transport: transport,
        timeout: timeout,
      );
      return SshMemberSession._(
        profile,
        session,
        newReverseTunnel: ({bindHost = '127.0.0.1'}) =>
            factory.newMemberReverseTunnel(profile, bindHost: bindHost),
      );
    } on Object {
      await transport.close();
      rethrow;
    }
  }

  /// Test harness with an already-authenticated [client]. It intentionally
  /// uses an injected direct transport and never creates an isolate.
  static SshMemberSession testing({
    required SshProfile profile,
    SSHClient? client,
    SshWorkerMemberTransport? transport,
  }) {
    if ((client == null) == (transport == null)) {
      throw ArgumentError('Supply exactly one test member transport');
    }
    final testTransport =
        transport ?? SshWorkerDirectMemberTransport(client: client!);
    return SshMemberSession._(
      profile,
      SshWorkerMemberSession.forTesting(profile, testTransport),
      newReverseTunnel: testTransport is SshWorkerDirectMemberTransport
          ? testTransport.newReverseTunnel
          : ({bindHost = '127.0.0.1'}) => throw UnsupportedError(
              'The injected test member transport has no reverse tunnel',
            ),
    );
  }

  Future<String> run(String command) => _session.run(command);

  Future<SSHRunResult> runWithResult(
    String command, {
    bool stderr = true,
  }) async {
    final result = await _session.runWithResult(command, stderr: stderr);
    return _toSshRunResult(result);
  }

  /// Returns the narrow tunnel transport supplied by the owning SSH factory.
  ReverseTunnel newReverseTunnel({String bindHost = '127.0.0.1'}) =>
      _newReverseTunnel(bindHost: bindHost);

  Future<SshWorkerPtyChannel> openPty({
    String? command,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) => _session.openPty(
    command: command,
    columns: columns,
    rows: rows,
    environment: environment,
  );

  Future<void> close() => _session.close();

  static SSHRunResult _toSshRunResult(SshWorkerRunResult result) {
    final output =
        (BytesBuilder(copy: false)
              ..add(result.stdout)
              ..add(result.stderr))
            .takeBytes();
    final signal = result.signalName;
    return SSHRunResult(
      output: output,
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
      exitSignal: signal == null
          ? null
          : SSHSessionExitSignal(
              signalName: signal,
              coreDumped: false,
              errorMessage: '',
              languageTag: '',
            ),
    );
  }

  /// Opens a non-PTY exec channel: separated stdout/stderr and a writable
  /// stdin. Used by the remote ACP transport, which must NOT use a PTY (a PTY
  /// merges stderr into stdout and echoes, both of which corrupt NDJSON).
  Future<SshWorkerExecChannel> openExec(String command) =>
      _session.startProcess(command);
}
