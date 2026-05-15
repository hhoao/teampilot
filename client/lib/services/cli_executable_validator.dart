import 'dart:io';

import 'cli_invocation.dart';

/// Pre-flight checks before spawning a PTY for [flashskyai].
class CliExecutableValidator {
  const CliExecutableValidator._();

  /// Returns a user-facing error message, or `null` when spawn may proceed.
  static String? validateLaunch({
    required String executable,
    required String workingDirectory,
  }) {
    final invocation = CliInvocation.fromExecutable(executable);
    if (invocation.usesWsl) {
      return null;
    }

    final pathError = _validateExecutablePath(invocation.executable);
    if (pathError != null) return pathError;

    final cwd = workingDirectory.trim();
    if (cwd.isNotEmpty && !Directory(cwd).existsSync()) {
      return _formatMessage(
        'Working directory does not exist',
        cwd,
        hint:
            'Choose another project folder or create the directory before connecting.',
      );
    }

    return null;
  }

  static String? _validateExecutablePath(String executable) {
    final looksLikePath = executable.contains('/') ||
        (Platform.isWindows &&
            (executable.contains(r'\') || executable.contains(':')));
    if (!looksLikePath) {
      // Avoid Pty.start for a bare name that is not on PATH. flutter_pty can
      // hang when execvp fails and multiple shells are spawned (e.g. auto-launch
      // all members).
      final cmd = Platform.isWindows ? 'where' : 'which';
      try {
        final result = Process.runSync(cmd, [executable]);
        if (result.exitCode != 0) {
          return _formatMessage(
            'flashskyai executable not found on PATH',
            executable,
            hint:
                'Open Settings → Session and set the absolute path to flashskyai, '
                'or add it to PATH in ~/.bashrc.',
          );
        }
      } on ProcessException {
        return _formatMessage(
          'flashskyai executable not found on PATH',
          executable,
          hint:
              'Open Settings → Session and set the absolute path to flashskyai.',
        );
      }
      return null;
    }

    if (!File(executable).existsSync()) {
      return _formatMessage(
        'flashskyai executable not found',
        executable,
        hint:
            'Open Settings → Session and set the absolute path to flashskyai, '
            'or install it on your PATH.',
      );
    }
    return null;
  }

  static String _formatMessage(
    String title,
    String detail, {
    required String hint,
  }) {
    return '[无法启动 flashskyai: $title\n'
        '  $detail\n'
        '  $hint]';
  }
}
