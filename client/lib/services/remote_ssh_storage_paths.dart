import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../models/ssh_profile.dart';
import 'app_storage.dart';
import 'ssh_client_factory.dart';

typedef SshRunCapture =
    Future<SSHRunResult> Function(SSHClient client, String command);

/// Home, CLI data dir, and TeamPilot app-data dir on a remote SSH host.
class RemoteSshStoragePaths {
  const RemoteSshStoragePaths({
    required this.home,
    required this.cliDataDir,
    required this.teampilotAppDir,
  });

  final String home;
  final String cliDataDir;
  final String teampilotAppDir;
}

/// Resolves remote storage paths in a single SSH round-trip.
class RemoteSshStoragePathResolver {
  RemoteSshStoragePathResolver({
    required SshClientFactory clientFactory,
    SshRunCapture? runCommand,
  }) : _clientFactory = clientFactory,
       _runCommand = runCommand;

  final SshClientFactory _clientFactory;
  final SshRunCapture? _runCommand;

  /// One shell invocation: `$HOME`, flashskyai data dir, teampilot app dir.
  static const resolveCommand = r'''
HOME_DIR="$HOME"
CLI_DIR="${FLASHSKYAI_DATA_DIR:-$HOME_DIR/.flashskyai}"
TP_DIR="${TEAMPILOT_APP_DATA_DIR:-${XDG_DATA_HOME:-$HOME_DIR/.local/share}/com.hhoa.teampilot}"
printf '%s\n' "$HOME_DIR" "$CLI_DIR" "$TP_DIR"
''';

  Future<RemoteSshStoragePaths?> resolve(SshProfile profile) async {
    try {
      final client = await _clientFactory.clientFor(profile);
      final result = await (_runCommand ?? _defaultRun)(client, resolveCommand);
      if (result.exitCode != 0) return null;
      final lines = utf8
          .decode(result.stdout, allowMalformed: true)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.length < 3) return null;
      return RemoteSshStoragePaths(
        home: lines[0],
        cliDataDir: lines[1],
        teampilotAppDir: lines[2],
      );
    } on Object {
      return null;
    }
  }

  /// Fallback when the combined command fails.
  RemoteSshStoragePaths fallbackForHome(String home) {
    final posix = p.Context(style: p.Style.posix);
    return RemoteSshStoragePaths(
      home: home,
      cliDataDir: posix.join(home, '.flashskyai'),
      teampilotAppDir: AppStorage.defaultTeampilotAppDataDirForHome(home),
    );
  }

  static Future<SSHRunResult> _defaultRun(SSHClient client, String command) {
    return client.runWithResult(command, stderr: false);
  }
}
