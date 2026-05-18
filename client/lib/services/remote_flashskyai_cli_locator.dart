import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:logger/logger.dart';

import '../models/ssh_profile.dart';
import 'flashskyai_cli_locator.dart';
import 'ssh_client_factory.dart';

class SshCommandResult {
  const SshCommandResult({required this.exitCode, required this.stdout});

  final int exitCode;
  final String stdout;
}

typedef SshCommandRunner = Future<SshCommandResult> Function(String command);

/// Resolves the absolute path of `flashskyai` on a remote host over SSH.
///
/// Tries a non-interactive lookup first, then login shells (bash/zsh) so remote
/// PATH matches what the user sees in an interactive terminal.
class RemoteFlashskyaiCliLocator {
  const RemoteFlashskyaiCliLocator({
    required SshClientFactory clientFactory,
    SshCommandRunner? commandRunner,
  }) : _clientFactory = clientFactory,
       _commandRunner = commandRunner;

  final SshClientFactory _clientFactory;
  final SshCommandRunner? _commandRunner;

  Future<String?> locate(SshProfile profile) async {
    try {
      final client = await _clientFactory.clientFor(profile);
      return locateWithRunner(_commandRunner ?? _runnerFor(client));
    } on Object catch (error, stackTrace) {
      Logger().w(
        'Failed to locate flashskyai on ${profile.hostIdentifier}: $error',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Lookup strategy without opening SSH (used by unit tests).
  Future<String?> locateWithRunner(SshCommandRunner runCommand) async {
    final direct = await _tryCommand(
      runCommand,
      FlashskyaiCliLocator.lookupCommand,
    );
    if (direct != null) return direct;

    for (final shell in const ['bash', 'zsh']) {
      final located = await _tryCommand(
        runCommand,
        "$shell -ilc '${FlashskyaiCliLocator.lookupCommand}'",
      );
      if (located != null) return located;
    }
    return null;
  }

  static SshCommandRunner _runnerFor(SSHClient client) {
    return (command) async {
      final result = await client.runWithResult(command, stderr: false);
      return SshCommandResult(
        exitCode: result.exitCode ?? 1,
        stdout: utf8.decode(result.stdout, allowMalformed: true),
      );
    };
  }

  static Future<String?> _tryCommand(
    SshCommandRunner runCommand,
    String command,
  ) async {
    try {
      final result = await runCommand(command);
      if (result.exitCode != 0) return null;
      return FlashskyaiCliLocator.parseFirstStdoutLine(result.stdout);
    } on Object catch (error, stackTrace) {
      Logger().w(
        'Remote flashskyai lookup failed for "$command": $error',
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
