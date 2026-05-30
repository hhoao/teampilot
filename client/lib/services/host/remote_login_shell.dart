/// Wraps a remote Unix command in `bash -lc` with login environment setup.
abstract final class RemoteLoginShell {
  RemoteLoginShell._();

  static String wrap(String command) {
    final shellCommand = [
      r'export TERM="${TERM:-xterm-256color}"',
      'if [ -f ~/.bashrc ]; then . ~/.bashrc || true; fi',
      command,
    ].join(' && ');
    return r'TERM="${TERM:-xterm-256color}" bash -lc ' + _quote(shellCommand);
  }

  static String _quote(String arg) {
    if (arg.isEmpty) return "''";
    if (!arg.contains("'")) return "'$arg'";
    return "'${arg.replaceAll("'", "'\"'\"'")}'";
  }
}
