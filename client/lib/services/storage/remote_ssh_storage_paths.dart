import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../../models/ssh_profile.dart';
import 'app_storage.dart';
import '../ssh/ssh_client_factory.dart';
import '../ssh/ssh_run_result.dart';

typedef SshRunCapture =
    Future<SSHRunResult> Function(SSHClient client, String command);

/// Home + TeamPilot app-data dir on a remote SSH host.
class RemoteSshStoragePaths {
  const RemoteSshStoragePaths({
    required this.home,
    required this.teampilotAppDir,
  });

  final String home;
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

  /// Resolves `$HOME` and the TeamPilot app-data dir in one shell round-trip.
  static const resolveCommand = r'''
HOME_DIR="$HOME"
TP_DIR="${TEAMPILOT_APP_DATA_DIR:-${XDG_DATA_HOME:-$HOME_DIR/.local/share}/com.hhoa.teampilot}"
printf '%s\n' "$HOME_DIR" "$TP_DIR"
''';

  Future<RemoteSshStoragePaths> resolve(SshProfile profile) async {
    final client = await _clientFactory.clientForStorage(profile);
    final result = await (_runCommand ?? _defaultRun)(client, resolveCommand);
    final lines = utf8
        .decode(result.stdout, allowMalformed: true)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (sshRunFailed(result)) {
      throw StateError(
        'Failed to resolve remote SSH storage paths '
        '(${sshRunFailureLabel(result)}): ${sshRunOutputDetail(result)}',
      );
    }
    if (lines.length < 2) {
      throw StateError(
        'Remote SSH path resolve returned ${lines.length} line(s), expected 2: '
        '${sshRunOutputDetail(result)}',
      );
    }
    return RemoteSshStoragePaths(home: lines[0], teampilotAppDir: lines[1]);
  }

  /// Fallback when the combined command fails.
  RemoteSshStoragePaths fallbackForHome(String home) {
    final posix = p.Context(style: p.Style.posix);
    return RemoteSshStoragePaths(
      home: home,
      teampilotAppDir: posix.join(
        AppPaths.defaultTeampilotAppDataDirForHome(home),
      ),
    );
  }

  static Future<SSHRunResult> _defaultRun(SSHClient client, String command) {
    return client.runWithResult(command);
  }
}
