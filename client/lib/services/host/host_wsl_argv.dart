/// Builds `wsl.exe` argv prefixes shared by one-shot runners and filesystem IO.
abstract final class HostWslArgv {
  HostWslArgv._();

  static List<String> prefixDistro({
    String? distro,
    required List<String> command,
  }) {
    final trimmed = distro?.trim() ?? '';
    if (trimmed.isEmpty) return command;
    return ['-d', trimmed, ...command];
  }

  /// `wsl.exe [-d distro] [--cd cwd] <executable> <args…>`
  static List<String> processInvocation({
    String? distro,
    String? workingDirectory,
    required String executable,
    required List<String> arguments,
    Map<String, String>? environment,
    List<String> pathPrepend = const [],
  }) {
    final inner = <String>[];
    final cwd = workingDirectory?.trim() ?? '';
    if (cwd.isNotEmpty) {
      inner.addAll(['--cd', cwd]);
    }
    if (pathPrepend.isEmpty) {
      inner.add(executable);
      inner.addAll(arguments);
    } else {
      final script = <String>[];
      if (environment != null) {
        for (final entry in environment.entries) {
          script.add(
            'export ${_shellQuote(entry.key)}=${_shellQuote(entry.value)}',
          );
        }
      }
      script.add(
        'export PATH=${_shellQuote('${pathPrepend.join(':')}:')}"\$PATH"',
      );
      final argv = [executable, ...arguments].map(_shellQuote).join(' ');
      script.add('exec $argv');
      // `-lc` receives the script as a direct argv element. Quote only the
      // script's shell syntax, not the whole argv value, or sh will see the
      // outer quotes literally.
      inner.addAll(['sh', '-lc', script.join(' && ')]);
    }
    return prefixDistro(distro: distro, command: inner);
  }

  static String _shellQuote(String value) {
    if (value.isEmpty) return "''";
    if (!value.contains("'")) return "'$value'";
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }
}
