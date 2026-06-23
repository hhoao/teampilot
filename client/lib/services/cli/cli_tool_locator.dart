import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;

import '../host/host_executable_locator.dart';
import '../host/host_execution_environment.dart';
import '../host/host_login_shell_lookup.dart';
import '../storage/runtime_context.dart';
import '../storage/app_storage.dart';


typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Encoding? stdoutEncoding,
      Encoding? stderrEncoding,
    });

Future<ProcessResult> cliToolDefaultProcessRun(
  String executable,
  List<String> arguments, {
  Encoding? stdoutEncoding,
  Encoding? stderrEncoding,
}) {
  return Process.run(
    executable,
    arguments,
    stdoutEncoding: stdoutEncoding ?? systemEncoding,
    stderrEncoding: stderrEncoding ?? systemEncoding,
  );
}

/// Resolves a CLI executable on PATH, with login-shell fallback for GUI
/// launches that start with a sparse environment.
class CliToolLocator {
  const CliToolLocator(this.executableName);

  final String executableName;

  String get lookupCommand =>
      HostLoginShellLookup.commandForExecutable(executableName);

  /// macOS `/usr/bin/git` is an Xcode shim that invokes `xcrun` and fails in
  /// App Sandbox; prefer a real git binary when present.
  static const _macOsGitCandidates = [
    '/opt/homebrew/bin/git',
    '/usr/local/bin/git',
    '/Library/Developer/CommandLineTools/usr/bin/git',
  ];

  Future<String?> locate({
    ProcessRunner runner = cliToolDefaultProcessRun,
    bool? isWindowsOverride,
  }) async {
    final isWindows = isWindowsOverride ?? Platform.isWindows;
    if (!isWindows && Platform.isMacOS && executableName == 'git') {
      final direct = await _locateMacOsGit(runner);
      if (direct != null) return direct;
    }
    final hostLocator = _hostLocator(isWindows);
    final cmd = hostLocator.whichCommand;
    try {
      final result = await runner(cmd, [executableName]);
      if (result.exitCode == 0) {
        final located = HostExecutableLocator.parsePathLookupOutput(
          result.stdout,
          isWindows: isWindows,
        );
        if (located != null) return located;
      }
      return _locateWithShellFallback(runner, isWindows: isWindows);
    } on ProcessException catch (error, stackTrace) {
      Logger().w(
        'Failed to locate $executableName: $error',
        stackTrace: stackTrace,
      );
      return _locateWithShellFallback(runner, isWindows: isWindows);
    } on Object catch (error, stackTrace) {
      Logger().w(
        'Failed to locate $executableName: $error',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<String?> _locateMacOsGit(ProcessRunner runner) async {
    for (final path in _macOsGitCandidates) {
      if (!File(path).existsSync()) continue;
      try {
        final result = await runner(path, ['--version']);
        if (result.exitCode == 0) return path;
      } on Object {
        continue;
      }
    }
    return null;
  }

  Future<String?> _locateWithShellFallback(
    ProcessRunner runner, {
    required bool isWindows,
  }) async {
    if (isWindows) {
      return _locateInWsl(runner);
    }
    return _locateInLoginShell(runner);
  }

  Future<String?> _locateInLoginShell(ProcessRunner runner) =>
      HostLoginShellLookup.locateViaLoginShells(
        runner: runner,
        innerCommand: lookupCommand,
      );

  Future<String?> _locateInWsl(ProcessRunner runner) async {
    final located = await HostLoginShellLookup.locateViaWsl(
      runner: runner,
      innerCommand: lookupCommand,
      pickLine: (line) {
        if (line.startsWith('/') && line.contains(executableName)) {
          return line;
        }
        return null;
      },
    );
    if (located == null) return null;
    return 'wsl.exe $located';
  }

  static List<String> parseStdoutLines(Object? stdoutValue) =>
      HostExecutableLocator.parseStdoutLines(stdoutValue);

  static String? parseFirstStdoutLine(Object? stdoutValue) =>
      HostExecutableLocator.parseFirstStdoutLine(stdoutValue);

  static String? parsePathLookupOutput(
    Object? stdoutValue, {
    required bool isWindows,
  }) =>
      HostExecutableLocator.parsePathLookupOutput(
        stdoutValue,
        isWindows: isWindows,
      );

  static String? preferWindowsNativeExecutable(List<String> candidates) =>
      HostExecutableLocator.preferWindowsNativeExecutable(candidates);

  static HostExecutableLocator _hostLocator(bool isWindows) {
    final storageMode = AppStorage.isInstalled
        ? AppStorage.context.mode
        : StorageBackendMode.native;
    return HostExecutableLocator(
      HostExecutionEnvironment.resolve(
        isWindowsHost: isWindows,
        storageMode: storageMode,
      ),
    );
  }

  /// Normalizes npm/global shims and other extensionless paths for PTY spawn.
  static String resolveSpawnExecutable(String executable) {
    if (!Platform.isWindows) return executable;
    if (!_looksLikePath(executable)) return executable;

    final ext = p.extension(executable).toLowerCase();
    if (const {'.exe', '.cmd', '.bat', '.com'}.contains(ext)) {
      return executable;
    }

    final cmdPath = '$executable.cmd';
    if (File(cmdPath).existsSync()) return cmdPath;

    final exePath = '$executable.exe';
    if (File(exePath).existsSync()) return exePath;

    return executable;
  }

  static bool _looksLikePath(String executable) {
    return executable.contains('/') ||
        executable.contains(r'\') ||
        executable.contains(':');
  }

}
