import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import '../cli/installer_types.dart';
import '../cli/registry/capabilities/installer_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/remote_cli_installer.dart';
import '../cli/remote_cli_locator.dart';
import '../ssh/ssh_client_factory.dart';
import 'remote_preflight_cli_install.dart';
import 'remember_remote_cli_path.dart';

/// Result of probing or installing a CLI on one runtime target.
sealed class RemoteCliReadiness {
  const RemoteCliReadiness({required this.targetId, required this.cli});

  final String targetId;
  final CliTool cli;
}

final class RemoteCliProbing extends RemoteCliReadiness {
  const RemoteCliProbing({required super.targetId, required super.cli});
}

final class RemoteCliReady extends RemoteCliReadiness {
  const RemoteCliReady({
    required super.targetId,
    required super.cli,
    required this.path,
  });

  final String path;
}

final class RemoteCliMissing extends RemoteCliReadiness {
  const RemoteCliMissing({required super.targetId, required super.cli});
}

final class RemoteCliInstalling extends RemoteCliReadiness {
  const RemoteCliInstalling({
    required super.targetId,
    required super.cli,
    this.progress,
  });

  final CliInstallProgress? progress;
}

final class RemoteCliFailed extends RemoteCliReadiness {
  const RemoteCliFailed({
    required super.targetId,
    required super.cli,
    required this.message,
  });

  final String message;
}

/// Locate / user-driven install of remote CLIs (Machines + landing gate).
///
/// Connect path must not call [install] — only [probe].
class RemoteCliReadinessService {
  RemoteCliReadinessService({
    required this.registry,
    required this.sshClientFactory,
    required this.profileById,
    required this.cliPathOverride,
    required this.setCliPathOverride,
    RemoteCliInstaller? installer,
    RemoteInstallAction Function(
      CliTool cli,
      SshProfile profile,
      SshCommandRunner run,
    )?
    installActionBuilder,
  }) : _installer = installer ?? RemoteCliInstaller(
         locator: RemoteCliLocator(registry: registry),
       ),
       _installActionBuilder = installActionBuilder;

  final CliToolRegistry registry;
  final SshClientFactory sshClientFactory;
  final SshProfile? Function(String profileId) profileById;
  final Future<String?> Function(String targetId, String cliValue)
  cliPathOverride;
  final Future<void> Function(String targetId, String cliValue, String path)
  setCliPathOverride;

  final RemoteCliInstaller _installer;
  final RemoteInstallAction Function(
    CliTool cli,
    SshProfile profile,
    SshCommandRunner run,
  )?
  _installActionBuilder;

  /// Locate only. Never installs.
  Future<RemoteCliReadiness> probe({
    required RuntimeTarget target,
    required CliTool cli,
  }) async {
    if (target.kind != RuntimeKind.ssh) {
      throw ArgumentError('probe requires an SSH target, got ${target.id}');
    }
    try {
      final path = await _locate(target: target, cli: cli);
      if (path == null) {
        return RemoteCliMissing(targetId: target.id, cli: cli);
      }
      return RemoteCliReady(targetId: target.id, cli: cli, path: path);
    } on Object catch (e) {
      return RemoteCliFailed(
        targetId: target.id,
        cli: cli,
        message: '$e',
      );
    }
  }

  /// User-driven install on [target]. Remembers resolved path on success.
  Future<RemoteCliReadiness> install({
    required RuntimeTarget target,
    required CliTool cli,
    void Function(CliInstallProgress progress)? onProgress,
  }) async {
    if (target.kind != RuntimeKind.ssh) {
      throw ArgumentError('install requires an SSH target, got ${target.id}');
    }
    final profile = profileById(target.sshProfileId ?? '');
    if (profile == null) {
      return RemoteCliFailed(
        targetId: target.id,
        cli: cli,
        message: 'No SSH profile for target "${target.id}".',
      );
    }
    final supportsInstaller =
        registry.capability<InstallerCapability>(cli)?.supportsInstaller ??
        false;
    if (!supportsInstaller) {
      return RemoteCliFailed(
        targetId: target.id,
        cli: cli,
        message:
            '${cli.value} has no in-app installer; set a manual CLI path '
            'for this target.',
      );
    }

    try {
      final client = await sshClientFactory.clientForStorage(profile);
      final run = RemoteCliLocator.runnerForClient(client);
      final storedPath = (await cliPathOverride(target.id, cli.value) ?? '')
          .trim();
      final path = await _installer.ensure(
        cli: cli,
        run: run,
        optIn: true,
        supportsInstaller: true,
        install:
            _installActionBuilder?.call(cli, profile, run) ??
            buildRemotePreflightCliInstall(
              registry: registry,
              profile: profile,
              cli: cli,
            ),
        manualPathOverride: storedPath,
        onProgress: onProgress,
      );
      await rememberRemoteCliPathIfNeeded(
        targetId: target.id,
        cli: cli,
        resolvedPath: path,
        readCliPathOverride: cliPathOverride,
        writeCliPathOverride: setCliPathOverride,
      );
      return RemoteCliReady(targetId: target.id, cli: cli, path: path);
    } on Object catch (e) {
      return RemoteCliFailed(
        targetId: target.id,
        cli: cli,
        message: '$e',
      );
    }
  }

  Future<String?> _locate({
    required RuntimeTarget target,
    required CliTool cli,
  }) async {
    final profile = profileById(target.sshProfileId ?? '');
    if (profile == null) {
      throw StateError('No SSH profile for target "${target.id}".');
    }
    final client = await sshClientFactory.clientForStorage(profile);
    final run = RemoteCliLocator.runnerForClient(client);
    final storedPath = (await cliPathOverride(target.id, cli.value) ?? '')
        .trim();
    return _installer.locate(
      cli: cli,
      run: run,
      manualPathOverride: storedPath,
    );
  }
}
