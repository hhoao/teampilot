import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../../models/team_config.dart';
import 'registry/capabilities/remote_cli_locator_capability.dart';
import 'registry/cli_tool_registry.dart';

export 'registry/capabilities/remote_cli_locator_capability.dart'
    show SshCommandResult, SshCommandRunner, RemoteCliLocatorCapability;

/// Resolves the absolute path of a CLI on a remote work machine (P3c). Per-target
/// manual override wins; otherwise the CLI's [RemoteCliLocatorCapability] probes
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
    final capability = _registry.capability<RemoteCliLocatorCapability>(cli);
    if (capability == null) return null;
    return capability.locate(run);
  }

  /// Adapts a connected [SSHClient] into an [SshCommandRunner] (non-test path).
  static SshCommandRunner runnerForClient(SSHClient client) {
    return (command) async {
      final result = await client.runWithResult(command, stderr: false);
      return SshCommandResult(
        exitCode: result.exitCode ?? 1,
        stdout: utf8.decode(result.stdout, allowMalformed: true),
      );
    };
  }
}
