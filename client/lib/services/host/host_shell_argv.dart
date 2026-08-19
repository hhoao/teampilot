import '../storage/remote_file_store.dart';

/// Shell-string helpers for SSH one-shot exec (not local argv).
abstract final class HostShellArgv {
  HostShellArgv._();

  /// `cd … && export … && 'exe' 'arg' …` safe for remote login shell.
  static String command({
    required String executable,
    required List<String> arguments,
    String? workingDirectory,
    Map<String, String>? environment,
    List<String> pathPrepend = const [],
  }) {
    final parts = <String>[];
    final cwd = workingDirectory?.trim() ?? '';
    if (cwd.isNotEmpty) {
      parts.add('cd ${RemoteFileStore.shellSingleQuote(cwd)}');
    }
    if (environment != null) {
      for (final entry in environment.entries) {
        parts.add(
          'export ${RemoteFileStore.shellSingleQuote(entry.key)}='
          '${RemoteFileStore.shellSingleQuote(entry.value)}',
        );
      }
    }
    if (pathPrepend.isNotEmpty) {
      final prefix = RemoteFileStore.shellSingleQuote(
        '${pathPrepend.join(':')}:',
      );
      parts.add('export PATH=$prefix"\$PATH"');
    }
    final argv = [
      executable,
      ...arguments,
    ].map(RemoteFileStore.shellSingleQuote).join(' ');
    parts.add(argv);
    return parts.join(' && ');
  }
}
