import 'package:logger/logger.dart';

import '../../cli_tool_locator.dart';
import '../cli_capability.dart';

/// Result of a single remote command (over the target transport).
class SshCommandResult {
  const SshCommandResult({required this.exitCode, required this.stdout});

  final int exitCode;
  final String stdout;
}

/// Runs one command on the work machine over its transport (SSH exec). Injected
/// so remote locate/install is unit-testable without real SSH.
typedef SshCommandRunner = Future<SshCommandResult> Function(String command);

/// Locates a CLI's absolute path on a remote work machine over [SshCommandRunner]
/// (P3c, generalized across all 5 CLIs — replaces the flashskyai-only locator).
abstract interface class RemoteCliLocatorCapability implements CliCapability {
  Future<String?> locate(SshCommandRunner run);
}

/// Default probe: a non-interactive `command -v <bin>` first, then bash/zsh login
/// shells so the remote PATH matches an interactive terminal. Parameterized by
/// the CLI's [executableName] (claude/flashskyai/codex/opencode/cursor-agent).
class DefaultRemoteCliLocator implements RemoteCliLocatorCapability {
  const DefaultRemoteCliLocator(this.executableName);

  final String executableName;

  @override
  Future<String?> locate(SshCommandRunner run) async {
    final probe = 'command -v $executableName';
    final direct = await _tryCommand(run, probe);
    if (direct != null) return direct;
    for (final shell in const ['bash', 'zsh']) {
      final located = await _tryCommand(run, "$shell -ilc '$probe'");
      if (located != null) return located;
    }
    return null;
  }

  static Future<String?> _tryCommand(
    SshCommandRunner run,
    String command,
  ) async {
    try {
      final result = await run(command);
      if (result.exitCode != 0) return null;
      return CliToolLocator.parseFirstStdoutLine(result.stdout);
    } on Object catch (error, stackTrace) {
      Logger().w(
        'Remote CLI lookup failed for "$command": $error',
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
