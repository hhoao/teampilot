import 'dart:async';
import 'dart:convert';

import '../../models/ssh_profile.dart';
import '../ssh/ssh_client_factory.dart';
import '../ssh/worker/ssh_worker_member_session.dart';
import '../ssh/worker/ssh_worker_storage_types.dart';
import 'installer_types.dart';
import 'registry/capabilities/cli_executable_capability.dart';

/// One short-lived member-plane exec channel for long install/provision work.
///
/// The member plane has no worker-side command timeout and does not invalidate
/// the storage plane; closing this lease never moves home connectivity state.
final class RemoteInstallTask {
  RemoteInstallTask._(this._transport, {required this.commandTimeout});

  /// Long enough for npm/Node bootstrap/downloads, short enough to end a wedge.
  static const defaultCommandTimeout = Duration(minutes: 10);

  /// Closing must never outlive the install outcome on a wedged worker.
  static const _closeTimeout = Duration(seconds: 10);

  /// Reply grace over the worker's own open timeout.
  ///
  /// `transport.open` is a worker request whose only bound is the worker's
  /// `timeoutMs`; a wedged isolate that never answers would otherwise leave the
  /// install job non-terminal, so the client bounds the wait itself.
  static const _openGrace = Duration(seconds: 5);

  static Future<RemoteInstallTask> open(
    SshClientFactory factory,
    SshProfile profile, {
    Duration connectTimeout = const Duration(seconds: 15),
    Duration commandTimeout = defaultCommandTimeout,
  }) async {
    final transport = await factory.openMemberTransport(
      profile,
      timeout: connectTimeout,
    );
    try {
      await transport
          .open(profile, timeout: connectTimeout)
          .timeout(connectTimeout + _openGrace);
    } on Object {
      try {
        await transport.close().timeout(_closeTimeout);
      } on Object {
        // The channel may already be gone; never mask the connect failure.
      }
      rethrow;
    }
    return RemoteInstallTask._(transport, commandTimeout: commandTimeout);
  }

  final SshWorkerMemberTransport _transport;
  final Duration commandTimeout;
  Future<void>? _closeFuture;

  SshCommandRunner get runner => (command) async {
    final SshWorkerRunResult result;
    try {
      result = await _transport.run(command, stderr: true).timeout(
        commandTimeout,
      );
    } on TimeoutException {
      await close();
      rethrow;
    }
    return SshCommandResult(
      exitCode: result.exitCode ?? 1,
      stdout: utf8.decode(result.stdout, allowMalformed: true),
      stderr: utf8.decode(result.stderr, allowMalformed: true),
    );
  };

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    try {
      await _transport.close().timeout(_closeTimeout);
    } on Object {
      // The channel may already be gone; a close failure must never mask the
      // install outcome or the timeout that triggered it.
    }
  }
}

/// Adapts a [RemoteInstallTask] to `CliInstallerService`'s SSH runner.
SshCliInstallRunner installRunnerForRemoteTask(RemoteInstallTask task) =>
    (SshProfile profile, CliInstallerCommand command) async {
      final result = await task.runner(command.commandLine);
      return CliInstallerCommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
      );
    };
