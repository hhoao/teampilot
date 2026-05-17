class RemoteFlashskyaiCommandBuilder {
  const RemoteFlashskyaiCommandBuilder();

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

    final execArgs = [
      remoteExecutablePath,
      ...arguments,
    ].map((a) => _quote(a)).join(' ');
    parts.add('exec $execArgs');

    final command = parts.join(' && ');
    return useLoginShell ? wrapWithLoginShell(command) : command;
  }

  String buildResumeCommand({
    required String remoteExecutablePath,
    required String sessionId,
    String? workingDirectory,
    Map<String, String>? environment,
    bool useLoginShell = false,
  }) {
    return buildCommand(
      remoteExecutablePath: remoteExecutablePath,
      arguments: ['--resume', sessionId],
      workingDirectory: workingDirectory,
      environment: environment,
      useLoginShell: useLoginShell,
    );
  }

  String wrapWithLoginShell(String command) {
    final shellCommand = [
      r'export TERM="${TERM:-xterm-256color}"',
      'if [ -f ~/.bashrc ]; then . ~/.bashrc || true; fi',
      command,
    ].join(' && ');
    return r'TERM="${TERM:-xterm-256color}" bash -lc ' +
        _quote(shellCommand);
  }

  static String _quote(String arg) {
    if (arg.isEmpty) return "''";
    if (!arg.contains("'")) return "'$arg'";
    return "'${arg.replaceAll("'", "'\"'\"'")}'";
  }
}
