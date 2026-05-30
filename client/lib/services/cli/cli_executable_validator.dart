import 'dart:io';

import '../host/host_executable_locator.dart';
import '../host/host_execution_environment.dart';
import '../storage/runtime_storage_context.dart';
import 'cli_invocation.dart';

/// Pre-flight checks before spawning a PTY for a configured CLI.
class CliExecutableValidator {
  const CliExecutableValidator._();

  /// Fast sync checks safe on the UI thread: working directory and absolute
  /// executable paths. Bare names on PATH are deferred to
  /// [validateLaunchPathLookupAsync].
  static String? validateLaunchSyncFast({
    required String executable,
    required String workingDirectory,
  }) {
    final invocation = CliInvocation.fromExecutable(executable);
    if (invocation.usesWsl) {
      return null;
    }

    final cwdError = _validateWorkingDirectory(workingDirectory);
    if (cwdError != null) return cwdError;

    return _validateAbsoluteExecutableSync(invocation.executable);
  }

  /// Async PATH lookup for bare executable names. Absolute paths are checked
  /// synchronously via [validateLaunchSyncFast].
  static Future<String?> validateLaunchPathLookupAsync(
    String executable,
  ) async {
    final invocation = CliInvocation.fromExecutable(executable);
    if (invocation.usesWsl || _looksLikePath(invocation.executable)) {
      return null;
    }

    return _validatePathLookupAsync(invocation.executable);
  }

  /// Returns a user-facing error message, or `null` when spawn may proceed.
  /// Async variant — does not block the UI thread.
  static Future<String?> validateLaunchAsync({
    required String executable,
    required String workingDirectory,
  }) async {
    final fastError = validateLaunchSyncFast(
      executable: executable,
      workingDirectory: workingDirectory,
    );
    if (fastError != null) return fastError;

    final invocation = CliInvocation.fromExecutable(executable);
    return validateLaunchPathLookupAsync(invocation.executable);
  }

  /// Synchronous variant kept for call sites that cannot be made async.
  static String? validateLaunch({
    required String executable,
    required String workingDirectory,
  }) {
    final fastError = validateLaunchSyncFast(
      executable: executable,
      workingDirectory: workingDirectory,
    );
    if (fastError != null) return fastError;

    final invocation = CliInvocation.fromExecutable(executable);
    return _validatePathLookupSync(invocation.executable);
  }

  static bool _looksLikePath(String executable) {
    return executable.contains('/') ||
        (Platform.isWindows &&
            (executable.contains(r'\') || executable.contains(':')));
  }

  static String? _validateWorkingDirectory(String workingDirectory) {
    final cwd = workingDirectory.trim();
    if (cwd.isEmpty || Directory(cwd).existsSync()) {
      return null;
    }
    return _formatMessage(
      'Working directory does not exist',
      cwd,
      hint:
          'Choose another project folder or create the directory before connecting.',
    );
  }

  static String? _validateAbsoluteExecutableSync(String executable) {
    if (!_looksLikePath(executable)) return null;

    final cliName = cliDisplayName(executable);
    if (!File(executable).existsSync()) {
      return _formatMessage(
        '$cliName executable not found',
        executable,
        cliName: cliName,
        hint: _settingsHint(cliName, includePathHint: true),
      );
    }
    return null;
  }

  static Future<String?> _validatePathLookupAsync(String executable) async {
    final cliName = cliDisplayName(executable);
    final cmd = _pathLocator().whichCommand;
    try {
      final result = await Process.run(cmd, [executable]);
      if (result.exitCode != 0) {
        return _formatMessage(
          '$cliName executable not found on PATH',
          executable,
          cliName: cliName,
          hint: _settingsHint(cliName, includePathHint: true),
        );
      }
    } on ProcessException {
      return _formatMessage(
        '$cliName executable not found on PATH',
        executable,
        cliName: cliName,
        hint: _settingsHint(cliName, includePathHint: false),
      );
    }
    return null;
  }

  static String? _validatePathLookupSync(String executable) {
    if (_looksLikePath(executable)) return null;

    final cliName = cliDisplayName(executable);
    // Avoid Pty.start for a bare name that is not on PATH. flutter_pty can
    // hang when execvp fails and multiple shells are spawned (e.g. auto-launch
    // all members).
    final cmd = _pathLocator().whichCommand;
    try {
      final result = Process.runSync(cmd, [executable]);
      if (result.exitCode != 0) {
        return _formatMessage(
          '$cliName executable not found on PATH',
          executable,
          cliName: cliName,
          hint: _settingsHint(cliName, includePathHint: true),
        );
      }
    } on ProcessException {
      return _formatMessage(
        '$cliName executable not found on PATH',
        executable,
        cliName: cliName,
        hint: _settingsHint(cliName, includePathHint: false),
      );
    }
    return null;
  }

  static HostExecutableLocator _pathLocator() {
    final env = RuntimeStorageContext.isInstalled
        ? HostExecutionEnvironment.fromStorage(RuntimeStorageContext.current)
        : HostExecutionEnvironment.resolve();
    return HostExecutableLocator(env);
  }

  static String cliDisplayName(String executable) {
    final normalized = executable.replaceAll(r'\', '/').toLowerCase();
    final basename = normalized.split('/').last;
    if (basename.contains('claude')) return 'claude';
    if (basename.contains('flashskyai')) return 'flashskyai';
    if (basename.contains('codex')) return 'codex';
    return 'CLI';
  }

  static String _settingsHint(String cliName, {required bool includePathHint}) {
    final base =
        'Open Settings → Session and set the absolute path to $cliName';
    if (!includePathHint) return '$base.';
    return '$base, or install it on your PATH.';
  }

  static String _formatMessage(
    String title,
    String detail, {
    String? cliName,
    required String hint,
  }) {
    return '[无法启动 ${cliName ?? 'CLI'}: $title\n'
        '  $detail\n'
        '  $hint]';
  }
}
