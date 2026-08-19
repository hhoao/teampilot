import '../../host/remote_login_shell.dart';

class RemoteFlashskyaiCommandBuilder {
  const RemoteFlashskyaiCommandBuilder();

  static const _teampilotNodePathExport =
      r'export PATH="$HOME/.local/share/com.hhoa.teampilot/toolchain/node/current/bin:$HOME/.local/bin:$PATH"';

  String buildCommand({
    required String remoteExecutablePath,
    required List<String> arguments,
    String? workingDirectory,
    Map<String, String>? environment,
    bool useLoginShell = false,
  }) {
    final parts = <String>[];

    if (workingDirectory != null && workingDirectory.isNotEmpty) {
      parts.add('cd ${_quote(workingDirectory)}');
    }

    if (environment != null && environment.isNotEmpty) {
      for (final entry in environment.entries) {
        parts.add('export ${_quote(entry.key)}=${_quote(entry.value)}');
      }
    }

    // npm-installed CLI shims use `#!/usr/bin/env node`. SSH PTY commands do
    // not inherit the app's interactive PATH, so expose TeamPilot's managed
    // Node runtime and npm bin directory on the remote host.
    parts.add(_teampilotNodePathExport);

    final execArgs = [
      remoteExecutablePath,
      ...arguments,
    ].map((a) => _quote(a)).join(' ');
    parts.add('exec $execArgs');

    final command = parts.join(' && ');
    return useLoginShell ? wrapWithLoginShell(command) : command;
  }

  String wrapWithLoginShell(String command) => RemoteLoginShell.wrap(command);

  static String _quote(String arg) {
    if (arg.isEmpty) return "''";
    if (!arg.contains("'")) return "'$arg'";
    return "'${arg.replaceAll("'", "'\"'\"'")}'";
  }
}
