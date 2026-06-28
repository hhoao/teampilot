import 'dart:io';

import '../host/host_executable_locator.dart';
import '../host/host_execution_environment.dart';
import '../storage/app_storage.dart';

/// Result of a git detection or installation operation.
class GitInstallResult {
  const GitInstallResult({
    required this.success,
    required this.message,
    this.executablePath,
  });

  final bool success;
  final String message;
  final String? executablePath;

  const GitInstallResult.found(String path)
      : success = true,
        executablePath = path,
        message = 'Found git at $path';

  const GitInstallResult.notFound(String detail)
      : success = false,
        executablePath = null,
        message = 'Git not found: $detail';

  const GitInstallResult.installed(String path)
      : success = true,
        executablePath = path,
        message = 'Git installed successfully at $path';

  const GitInstallResult.failed(String detail)
      : success = false,
        executablePath = null,
        message = detail;
}

/// Phases of git detection / installation for UI progress reporting.
enum GitInstallPhase {
  checking,
  installing,
  locating,
}

/// Progress report emitted during detection or installation.
class GitInstallProgress {
  const GitInstallProgress({required this.phase, this.detail});

  final GitInstallPhase phase;
  final String? detail;
}

/// Callback for UI progress updates during git detection / installation.
typedef GitInstallProgressCallback = void Function(
  GitInstallProgress progress,
);

/// Injection point so tests can replace [Process.run] with a mock.
typedef GitProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

Future<ProcessResult> _defaultProcessRunner(
  String executable,
  List<String> arguments,
) =>
    Process.run(executable, arguments);

/// Detects and optionally installs git on the local host.
///
/// Uses [HostExecutionEnvironment] for platform detection and dispatches to
/// the appropriate package manager (`winget` on Windows, `brew` on macOS).
/// Linux always returns a guide URL — no `sudo` is ever invoked.
final class GitInstaller {
  const GitInstaller({
    GitProcessRunner? processRunner,
    bool? isWindowsOverride,
  })  : _processRunner = processRunner ?? _defaultProcessRunner,
       _isWindowsOverride = isWindowsOverride;

  final GitProcessRunner _processRunner;
  final bool? _isWindowsOverride;

  // ---- guide URLs -----------------------------------------------------------

  static const _windowsGuideUrl = 'https://git-scm.com/downloads/win';
  static const _macOSGuideUrl = 'https://git-scm.com/downloads/mac';
  static const _linuxGuideUrl = 'https://git-scm.com/downloads/linux';

  // ---- platform helpers -----------------------------------------------------

  HostExecutionEnvironment get _hostEnv {
    if (AppStorage.isInstalled) {
      return HostExecutionEnvironment.fromStorage(AppStorage.context);
    }
    return HostExecutionEnvironment.resolve(
      isWindowsHost: _isWindowsOverride,
    );
  }

  bool get _isWindows => _hostEnv.isWindowsHost;
  bool get _isMacOS => !_isWindows && Platform.isMacOS;

  // ---- detect ---------------------------------------------------------------

  /// Checks whether git is on PATH and resolves its absolute path.
  ///
  /// Returns a [GitInstallResult] whose [GitInstallResult.executablePath] is
  /// the resolved path when git is found.
  Future<GitInstallResult> detectGit({
    GitInstallProgressCallback? onProgress,
  }) async {
    onProgress?.call(
      const GitInstallProgress(phase: GitInstallPhase.checking),
    );

    // Fast check: can we run `git --version`?
    try {
      final versionResult = await _processRunner('git', ['--version']);
      if (versionResult.exitCode != 0) {
        return _notFound(
          '`git --version` exited with code ${versionResult.exitCode}',
        );
      }
    } on ProcessException catch (e) {
      return _notFound(e.message);
    }

    // Resolve the absolute path via `where` / `which`.
    onProgress?.call(
      const GitInstallProgress(phase: GitInstallPhase.locating),
    );

    final locator = HostExecutableLocator(_hostEnv);
    try {
      final whichResult = await _processRunner(locator.whichCommand, ['git']);
      if (whichResult.exitCode != 0) {
        // git runs but is not on PATH — unusual but possible (e.g. aliased).
        return GitInstallResult.found('git');
      }

      final parsed = HostExecutableLocator.parsePathLookupOutput(
        whichResult.stdout,
        isWindows: _isWindows,
      );

      if (parsed != null && parsed.isNotEmpty) {
        return GitInstallResult.found(parsed);
      }

      return GitInstallResult.found('git');
    } on ProcessException {
      // `which` / `where` itself failed — git still runs, fall back to bare name.
      return GitInstallResult.found('git');
    }
  }

  // ---- install --------------------------------------------------------------

  /// Installs git on the local host using the platform package manager.
  ///
  /// * Windows: `winget install Git.Git` (guide URL fallback).
  /// * macOS:   `brew install git` (guide URL fallback).
  /// * Linux:   guide URL only — never runs `sudo` or any system command.
  Future<GitInstallResult> install({
    GitInstallProgressCallback? onProgress,
  }) async {
    if (_isWindows) {
      return _installWindows(onProgress: onProgress);
    }
    if (_isMacOS) {
      return _installMacOS(onProgress: onProgress);
    }
    // Linux or any other platform — guide only, no sudo.
    return GitInstallResult.failed(
      'Automatic git installation is not supported on this platform.\n'
          'Please install git manually: $_linuxGuideUrl',
    );
  }

  // ---- Windows --------------------------------------------------------------

  Future<GitInstallResult> _installWindows({
    GitInstallProgressCallback? onProgress,
  }) async {
    // Prefer winget; it ships on Windows 10 1709+ and Windows 11.
    final hasWinget = await _canRun('winget');
    if (!hasWinget) {
      return GitInstallResult.failed(
        'winget is not available on this system.\n'
            'Please install git manually: $_windowsGuideUrl',
      );
    }

    onProgress?.call(
      const GitInstallProgress(phase: GitInstallPhase.installing),
    );

    try {
      final result = await _processRunner('winget', [
        'install',
        '--id',
        'Git.Git',
        '--exact',
        '--silent',
        '--accept-source-agreements',
        '--accept-package-agreements',
      ]);

      if (result.exitCode != 0) {
        final stderr = (result.stderr as String).trim();
        final detail =
            stderr.isNotEmpty ? stderr : 'exit code ${result.exitCode}';
        return GitInstallResult.failed(
          'winget install failed ($detail).\n'
              'Please install git manually: $_windowsGuideUrl',
        );
      }
    } on ProcessException catch (e) {
      return GitInstallResult.failed(
        'Failed to run winget: ${e.message}.\n'
            'Please install git manually: $_windowsGuideUrl',
      );
    }

    // After install, locate the new executable.
    onProgress?.call(
      const GitInstallProgress(phase: GitInstallPhase.locating),
    );

    final detected = await detectGit(onProgress: onProgress);
    if (detected.success) {
      return GitInstallResult.installed(detected.executablePath!);
    }

    return GitInstallResult.failed(
      'Installation completed, but git was not found on PATH.\n'
          'You may need to restart your terminal or add git to your PATH manually.',
    );
  }

  // ---- macOS ----------------------------------------------------------------

  Future<GitInstallResult> _installMacOS({
    GitInstallProgressCallback? onProgress,
  }) async {
    final hasBrew = await _canRun('brew');
    if (!hasBrew) {
      return GitInstallResult.failed(
        'Homebrew is not available on this system.\n'
            'Please install git manually: $_macOSGuideUrl\n'
            'Or install Homebrew first: https://brew.sh',
      );
    }

    onProgress?.call(
      const GitInstallProgress(phase: GitInstallPhase.installing),
    );

    try {
      final result = await _processRunner('brew', ['install', 'git']);

      if (result.exitCode != 0) {
        final stderr = (result.stderr as String).trim();
        final detail =
            stderr.isNotEmpty ? stderr : 'exit code ${result.exitCode}';
        return GitInstallResult.failed(
          'brew install failed ($detail).\n'
              'Please install git manually: $_macOSGuideUrl',
        );
      }
    } on ProcessException catch (e) {
      return GitInstallResult.failed(
        'Failed to run brew: ${e.message}.\n'
            'Please install git manually: $_macOSGuideUrl',
      );
    }

    // After install, locate the new executable.
    onProgress?.call(
      const GitInstallProgress(phase: GitInstallPhase.locating),
    );

    final detected = await detectGit(onProgress: onProgress);
    if (detected.success) {
      return GitInstallResult.installed(detected.executablePath!);
    }

    return GitInstallResult.failed(
      'Installation completed, but git was not found on PATH.\n'
          'You may need to restart your terminal or add git to your PATH manually.',
    );
  }

  // ---- helpers --------------------------------------------------------------

  /// Quick check whether [executable] is on PATH.
  Future<bool> _canRun(String executable) async {
    try {
      final cmd = _isWindows ? 'where' : 'which';
      final result = await _processRunner(cmd, [executable]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  static GitInstallResult _notFound(String detail) =>
      GitInstallResult.notFound(detail);
}
