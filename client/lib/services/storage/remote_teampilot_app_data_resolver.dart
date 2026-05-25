import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../../models/ssh_profile.dart';
import '../ssh/ssh_client_factory.dart';

typedef SshRunCapture =
    Future<SSHRunResult> Function(SSHClient client, String command);

/// Resolves the TeamPilot UI app-data directory on a remote SSH host.
///
/// Matches Linux desktop [AppStorage.basePath] from `path_provider`:
/// `$XDG_DATA_HOME/com.hhoa.teampilot` (default `~/.local/share/com.hhoa.teampilot`).
///
/// Override with `TEAMPILOT_APP_DATA_DIR` on the remote shell when needed.
class RemoteTeampilotAppDataResolver {
  RemoteTeampilotAppDataResolver({
    required SshClientFactory clientFactory,
    SshRunCapture? runCommand,
  }) : _clientFactory = clientFactory,
       _runCommand = runCommand;

  final SshClientFactory _clientFactory;
  final SshRunCapture? _runCommand;

  static const _resolveCommand = r'''
printf '%s' "${TEAMPILOT_APP_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/com.hhoa.teampilot}"
''';

  Future<String?> resolve(SshProfile profile) async {
    try {
      final client = await _clientFactory.clientFor(profile);
      final result = await (_runCommand ?? _defaultRun)(
        client,
        _resolveCommand,
      );
      if (result.exitCode != 0) return null;
      final value = utf8.decode(result.stdout, allowMalformed: true).trim();
      return value.isEmpty ? null : value;
    } on Object {
      return null;
    }
  }

  static Future<String> pickTeampilotRoot({
    required String primary,
    required String legacy,
    required Future<bool> Function(String root) hasExistingData,
  }) async {
    if (primary == legacy) return primary;
    if (await hasExistingData(primary)) return primary;
    if (await hasExistingData(legacy)) return legacy;
    return primary;
  }

  static Future<bool> teampilotTreeHasData(
    Future<bool> Function(String path) fileExists,
    String root,
  ) async {
    final posix = p.Context(style: p.Style.posix);
    final markers = [
      posix.join(root, 'skills', 'repos.json'),
      posix.join(root, 'projects', 'projects.json'),
      posix.join(root, 'skills', 'installed', 'manifest.json'),
      posix.join(root, 'teams'),
    ];
    final found = await Future.wait(markers.map(fileExists));
    return found.any((exists) => exists);
  }

  static Future<SSHRunResult> _defaultRun(SSHClient client, String command) {
    return client.runWithResult(command, stderr: false);
  }
}
