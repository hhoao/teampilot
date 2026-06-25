import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import '../../models/ssh_profile.dart';
import '../ssh/ssh_client_factory.dart';
import '../ssh/ssh_run_result.dart';

typedef SshRunCapture =
    Future<SSHRunResult> Function(SSHClient client, String command);

/// Resolves the remote login home directory for [profile] over SSH.
class RemoteHomeResolver {
  const RemoteHomeResolver({
    required SshClientFactory clientFactory,
    SshRunCapture? runCommand,
  }) : _clientFactory = clientFactory,
       _runCommand = runCommand;

  final SshClientFactory _clientFactory;
  final SshRunCapture? _runCommand;

  Future<String?> resolve(SshProfile profile) async {
    final client = await _clientFactory.clientFor(profile);
    try {
      final result = await (_runCommand ?? _defaultRun)(
        client,
        r'printf %s "$HOME"',
      );
      if (sshRunFailed(result)) return null;
      final home = utf8.decode(result.stdout, allowMalformed: true).trim();
      if (home.isEmpty) return null;
      return home;
    } on Object {
      return null;
    }
  }

  static Future<SSHRunResult> _defaultRun(SSHClient client, String command) {
    return client.runWithResult(command, stderr: false);
  }
}
