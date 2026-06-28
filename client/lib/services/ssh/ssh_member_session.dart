import 'package:dartssh2/dartssh2.dart';

import '../../models/ssh_profile.dart';
import '../team_bus/remote/reverse_tunnel.dart';
import 'ssh_client_factory.dart';

/// Dedicated SSH connection for one remote member's **session plane**: reverse
/// bus tunnels, exec probes, and PTY. Not pooled with the storage-plane SFTP
/// client ([SshClientFactory.clientForStorage]).
class SshMemberSession {
  SshMemberSession._(this.profile, this.client);

  final SshProfile profile;
  final SSHClient client;

  static Future<SshMemberSession> open(
    SshClientFactory factory,
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final client = await factory.createMemberClient(profile, timeout: timeout);
    await client.authenticated;
    return SshMemberSession._(profile, client);
  }

  /// Test harness with an already-authenticated [client].
  static SshMemberSession testing({
    required SshProfile profile,
    required SSHClient client,
  }) =>
      SshMemberSession._(profile, client);

  Future<String> run(String command) async {
    final out = await client.run(command);
    return String.fromCharCodes(out).trim();
  }

  Future<SSHRunResult> runWithResult(
    String command, {
    bool stderr = true,
  }) =>
      client.runWithResult(command, stderr: stderr);

  SshReverseTunnel newReverseTunnel({String bindHost = '127.0.0.1'}) =>
      SshReverseTunnel(client, bindHost: bindHost);

  Future<SSHSession> openPty({
    required String command,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) =>
      client.execute(
        command,
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: columns,
          height: rows,
        ),
        environment: environment,
      );

  void close() {
    if (!client.isClosed) {
      client.close();
    }
  }
}
