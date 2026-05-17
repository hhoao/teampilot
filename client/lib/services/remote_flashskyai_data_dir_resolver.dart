import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../models/ssh_profile.dart';
import 'remote_home_resolver.dart';
import 'ssh_client_factory.dart';

typedef SshRunCapture = Future<SSHRunResult> Function(
  SSHClient client,
  String command,
);

/// Resolves the flashskyai CLI data directory on a remote SSH host.
///
/// Matches desktop [AppStorage.flashskyaiDataDir] semantics: prefer
/// [FLASHSKYAI_DATA_DIR] when set, otherwise `<remoteHome>/.flashskyai`.
class RemoteFlashskyaiDataDirResolver {
  RemoteFlashskyaiDataDirResolver({
    required SshClientFactory clientFactory,
    RemoteHomeResolver? remoteHomeResolver,
    SshRunCapture? runCommand,
  })  : _clientFactory = clientFactory,
        _remoteHomeResolver =
            remoteHomeResolver ?? RemoteHomeResolver(clientFactory: clientFactory),
        _runCommand = runCommand;

  final SshClientFactory _clientFactory;
  final RemoteHomeResolver _remoteHomeResolver;
  final SshRunCapture? _runCommand;

  Future<String?> resolve(SshProfile profile) async {
    final home = await _remoteHomeResolver.resolve(profile);
    if (home == null || home.isEmpty) return null;

    final fromEnv = await _readEnvOverride(profile);
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv;
    }

    final posix = p.Context(style: p.Style.posix);
    return posix.join(home, '.flashskyai');
  }

  Future<String?> _readEnvOverride(SshProfile profile) async {
    try {
      final client = await _clientFactory.clientFor(profile);
      final result = await (_runCommand ?? _defaultRun)(
        client,
        r'printf %s "${FLASHSKYAI_DATA_DIR:-}"',
      );
      if (result.exitCode != 0) return null;
      final value = utf8.decode(result.stdout, allowMalformed: true).trim();
      return value.isEmpty ? null : value;
    } on Object {
      return null;
    }
  }

  static Future<SSHRunResult> _defaultRun(SSHClient client, String command) {
    return client.runWithResult(command, stderr: false);
  }
}
