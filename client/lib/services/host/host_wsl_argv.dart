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
  }) {
    final inner = <String>[];
    final cwd = workingDirectory?.trim() ?? '';
    if (cwd.isNotEmpty) {
      inner.addAll(['--cd', cwd]);
    }
    inner.add(executable);
    inner.addAll(arguments);
    return prefixDistro(distro: distro, command: inner);
  }
}
