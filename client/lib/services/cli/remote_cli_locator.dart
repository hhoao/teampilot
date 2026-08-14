import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:logger/logger.dart';

import '../../models/team_config.dart';
import 'cli_tool_locator.dart';
import 'registry/capabilities/cli_executable_capability.dart';
import 'registry/cli_tool_registry.dart';

export 'registry/capabilities/cli_executable_capability.dart'
    show SshCommandResult, SshCommandRunner, CliExecutableCapability;

/// Resolves the absolute path of a CLI on a remote work machine (P3c). Per-target
/// manual override wins; otherwise the CLI's [CliExecutableCapability] probes
/// over the injected [SshCommandRunner]. Generalizes the former
/// flashskyai-only `RemoteFlashskyaiCliLocator` across all 5 CLIs.
class RemoteCliLocator {
  RemoteCliLocator({CliToolRegistry? registry})
    : _registry = registry ?? CliToolRegistry.builtIn();

  final CliToolRegistry _registry;

  Future<String?> resolve({
    required CliTool cli,
    required SshCommandRunner run,
    String manualPathOverride = '',
  }) async {
    final manual = manualPathOverride.trim();
    if (manual.isNotEmpty) return manual;
    final capability = _registry.capability<CliExecutableCapability>(cli);
    if (capability == null) return null;
    return capability.locateRemote(run);
  }

  /// Adapts a connected [SSHClient] into an [SshCommandRunner] (non-test path).
  ///
  /// Locate probes keep [includeStderr] false so PATH chatter does not pollute
  /// path parsing. Install / bootstrap must pass true so failure messages and
  /// logs include remote stderr.
  static SshCommandRunner runnerForClient(
    SSHClient client, {
    bool includeStderr = false,
    Duration? timeout,
  }) {
    return (command) async {
      final run = client.runWithResult(command, stderr: includeStderr);
      final result = timeout == null ? await run : await run.timeout(timeout);
      return SshCommandResult(
        exitCode: result.exitCode ?? 1,
        stdout: utf8.decode(result.stdout, allowMalformed: true),
        stderr: includeStderr
            ? utf8.decode(result.stderr, allowMalformed: true)
            : '',
      );
    };
  }
}

/// Default probe: a non-interactive `command -v <bin>` first, then bash/zsh login
/// shells so the remote PATH matches an interactive terminal. Parameterized by
/// the CLI's [executableName] (claude/flashskyai/codex/opencode/cursor-agent).
final class DefaultRemoteCliLocator {
  const DefaultRemoteCliLocator(this.executableName);

  final String executableName;

  Future<String?> locate(SshCommandRunner run) async {
    final probe = 'command -v $executableName';
    final direct = await _tryCommand(run, probe);
    if (direct != null) return direct;
    for (final shell in const ['bash', 'zsh']) {
      for (final flags in const ['-ilc', '-lc']) {
        final located = await _tryCommand(run, '$shell $flags \'$probe\'');
        if (located != null) return located;
      }
    }
    final localBin = await _tryCommand(
      run,
      _wellKnownLocalBinProbe(executableName),
    );
    if (localBin != null) return localBin;
    return _tryCommand(run, _termuxPrefixBinProbe(executableName));
  }

  /// TeamPilot remote npm installs default to prefix `~/.local` → `~/.local/bin`.
  static String _wellKnownLocalBinProbe(String executableName) =>
      'sh -c \'test -x "\$HOME/.local/bin/$executableName" && '
      'printf "%s\\n" "\$HOME/.local/bin/$executableName"\'';

  /// Termux packages live under `$PREFIX/bin` (often missing from sparse SSH PATH).
  static String _termuxPrefixBinProbe(String executableName) =>
      'sh -c \''
      'export PATH="\${PREFIX:+\$PREFIX/bin:}\$PATH"; '
      'if [ -z "\${PREFIX:-}" ] && [ -d /data/data/com.termux/files/usr/bin ]; then '
      'export PATH="/data/data/com.termux/files/usr/bin:\$PATH"; fi; '
      'command -v $executableName'
      '\'';

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
