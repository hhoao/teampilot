import 'dart:io';

import 'package:flutter_pty/flutter_pty.dart';

import '../models/connection_mode.dart';
import '../models/launch_target.dart';
import '../models/ssh_profile.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_known_host_repository.dart';
import '../repositories/ssh_profile_repository.dart';
import 'local_pty_transport.dart';
import 'remote_flashskyai_command_builder.dart';
import 'ssh_client_factory.dart';
import 'ssh_pty_transport.dart';
import 'terminal_transport.dart';

typedef PtyStarter =
    Future<TerminalTransport> Function(
      String executable, {
      required List<String> arguments,
      required String workingDirectory,
      required int columns,
      required int rows,
      Map<String, String>? environment,
    });

typedef SshTransportStarter =
    Future<TerminalTransport> Function({
      required SshProfile profile,
      required SshClientFactory clientFactory,
      required String command,
      required int columns,
      required int rows,
    });

class TerminalTransportFactory {
  TerminalTransportFactory({
    required SshProfileRepository sshProfileRepository,
    required SshCredentialStore sshCredentialStore,
    required SshKnownHostRepository sshKnownHostRepository,
    SshClientFactory? sshClientFactory,
    PtyStarter? ptyStarter,
    SshTransportStarter? sshStarter,
  }) : _sshProfileRepository = sshProfileRepository,
       sshClientFactory =
           sshClientFactory ??
           SshClientFactory(
             credentialStore: sshCredentialStore,
             knownHostRepository: sshKnownHostRepository,
           ),
       _ptyStarter = ptyStarter ?? _defaultPtyStarter,
       _sshStarter = sshStarter ?? _defaultSshStarter;

  final SshProfileRepository _sshProfileRepository;
  final SshClientFactory sshClientFactory;
  final PtyStarter _ptyStarter;
  final SshTransportStarter _sshStarter;

  static Future<TerminalTransport> _defaultPtyStarter(
    String executable, {
    required List<String> arguments,
    required String workingDirectory,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) async {
    final pty = Pty.start(
      executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      columns: columns,
      rows: rows,
      environment: environment,
    );
    return LocalPtyTransport(pty);
  }

  static Future<TerminalTransport> _defaultSshStarter({
    required SshProfile profile,
    required SshClientFactory clientFactory,
    required String command,
    required int columns,
    required int rows,
  }) {
    return SshPtyTransport.start(
      profile: profile,
      clientFactory: clientFactory,
      command: command,
      columns: columns,
      rows: rows,
    );
  }

  ConnectionMode resolveConnectionMode(ConnectionMode? preferred) {
    if (preferred != null) return preferred;
    if (Platform.isAndroid) return ConnectionMode.ssh;
    return ConnectionMode.localPty;
  }

  Future<TerminalTransport> startTransport(
    LaunchTarget target, {
    required List<String> arguments,
    required int columns,
    required int rows,
  }) async {
    switch (target.connectionMode) {
      case ConnectionMode.localPty:
        return _ptyStarter(
          target.executable,
          arguments: arguments,
          workingDirectory: target.workingDirectory,
          columns: columns,
          rows: rows,
          environment: target.environment.isNotEmpty
              ? target.environment
              : null,
        );
      case ConnectionMode.ssh:
        final profile = await _sshProfileRepository.findById(
          target.sshProfileId,
        );
        if (profile == null) {
          throw StateError('SSH profile not found: ${target.sshProfileId}');
        }
        final remoteEnvironment = target.remoteEnvironment;
        final command = const RemoteFlashskyaiCommandBuilder().buildCommand(
          remoteExecutablePath: target.remoteExecutable,
          arguments: arguments,
          workingDirectory: target.remoteWorkingDirectory.isEmpty
              ? null
              : target.remoteWorkingDirectory,
          environment: remoteEnvironment.isNotEmpty ? remoteEnvironment : null,
          useLoginShell: target.useLoginShell,
        );
        return _sshStarter(
          profile: profile,
          clientFactory: sshClientFactory,
          command: command,
          columns: columns,
          rows: rows,
        );
    }
  }
}
