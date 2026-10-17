import '../../models/cli_binary_kind.dart';
import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import '../../utils/logging/logger.dart';
import '../cli/acp_adapter_discovery.dart';
import '../cli/installer_types.dart';
import '../cli/registry/capabilities/acp_settings_capability.dart';
import '../cli/registry/capabilities/cli_executable_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/registry/installer/npm_installer_capability.dart';
import '../cli/remote_cli_installer.dart';
import '../cli/remote_cli_locator.dart';
import '../ssh/ssh_client_factory.dart';
import 'remote_preflight_cli_install.dart';
import 'remember_remote_cli_path.dart';

/// Result of probing or installing a binary on one runtime target.
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

/// Test seam: build the remote command runner for a profile without dartssh2.
typedef RemoteRunnerForProfile =
    SshCommandRunner Function(SshProfile profile, {required bool includeStderr});

/// Builds the adapter install action for a profile over an existing runner.
typedef AdapterInstallActionBuilder =
    RemoteInstallAction Function(
      NpmInstallerCapability installer,
      SshProfile profile,
      SshCommandRunner run,
    );

/// Locate / user-driven install of remote binaries (CLIs and separate ACP
/// adapters) for the Machines panel and the landing gate.
///
/// Connect path must not call [install] — only [probe].
class RemoteCliReadinessService {
  RemoteCliReadinessService({
    required this.registry,
    required this.sshClientFactory,
    required this.profileById,
    required this.cliPathOverride,
    required this.setCliPathOverride,
    Future<String?> Function(String targetId, String cliValue)?
    acpAdapterPathOverride,
    Future<void> Function(String targetId, String cliValue, String path)?
    setAcpAdapterPathOverride,
    RemoteCliInstaller? installer,
    RemoteInstallAction Function(
      CliTool cli,
      SshProfile profile,
      SshCommandRunner run,
    )?
    installActionBuilder,
    AdapterInstallActionBuilder? adapterInstallActionBuilder,
    RemoteRunnerForProfile? remoteRunnerFor,
  }) : _installer =
           installer ??
           RemoteCliInstaller(locator: RemoteCliLocator(registry: registry)),
       _installActionBuilder = installActionBuilder,
       _adapterInstallActionBuilder = adapterInstallActionBuilder,
       _remoteRunnerFor = remoteRunnerFor,
       acpAdapterPathOverride =
           acpAdapterPathOverride ?? ((_, __) async => null),
       setAcpAdapterPathOverride =
           setAcpAdapterPathOverride ?? ((_, __, ___) async {});

  final CliToolRegistry registry;
  final SshClientFactory sshClientFactory;
  final SshProfile? Function(String profileId) profileById;
  final Future<String?> Function(String targetId, String cliValue)
  cliPathOverride;
  final Future<void> Function(String targetId, String cliValue, String path)
  setCliPathOverride;
  final Future<String?> Function(String targetId, String cliValue)
  acpAdapterPathOverride;
  final Future<void> Function(String targetId, String cliValue, String path)
  setAcpAdapterPathOverride;

  final RemoteCliInstaller _installer;
  final RemoteInstallAction Function(
    CliTool cli,
    SshProfile profile,
    SshCommandRunner run,
  )?
  _installActionBuilder;
  final AdapterInstallActionBuilder? _adapterInstallActionBuilder;
  final RemoteRunnerForProfile? _remoteRunnerFor;

  Future<SshCommandRunner> _runnerFor(
    SshProfile profile, {
    required bool includeStderr,
  }) async {
    final override = _remoteRunnerFor;
    if (override != null) return override(profile, includeStderr: includeStderr);
    final client = await sshClientFactory.clientForStorage(profile);
    return RemoteCliLocator.getRunnerForClient(
      client,
      includeStderr: includeStderr,
    );
  }

  /// Locate only. Never installs.
  Future<RemoteCliReadiness> probe({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
  }) async {
    if (!usesSshTransport(target.kind)) {
      throw ArgumentError(
        'probe requires an SSH transport target, got ${target.id}',
      );
    }
    try {
      final path = kind == CliBinaryKind.adapter
          ? await _locateAdapter(target: target, cli: cli)
          : await _locateCli(target: target, cli: cli);
      if (path == null) {
        return RemoteCliMissing(targetId: target.id, cli: cli);
      }
      return RemoteCliReady(targetId: target.id, cli: cli, path: path);
    } on Object catch (e, st) {
      final message = remoteCliFailureMessage(e);
      appLogger.w(
        '[remote-cli] probe failed target=${target.id} cli=${cli.value} '
        'kind=${kind.name}: $message',
        error: e,
        stackTrace: st,
      );
      return RemoteCliFailed(targetId: target.id, cli: cli, message: message);
    }
  }

  /// Locate and remember the resolved path. Never installs.
  Future<RemoteCliReadiness> locate({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
  }) async {
    if (!usesSshTransport(target.kind)) {
      throw ArgumentError(
        'locate requires an SSH transport target, got ${target.id}',
      );
    }
    try {
      final profile = profileById(target.sshProfileId ?? '');
      if (profile == null) {
        throw StateError('No SSH profile for target "${target.id}".');
      }
      final run = await _runnerFor(profile, includeStderr: false);
      final path = kind == CliBinaryKind.adapter
          ? await _locateAdapterWithRun(target: target, cli: cli, run: run)
          : await _locateCliWithRun(target: target, cli: cli, run: run);
      if (path == null) {
        return RemoteCliMissing(targetId: target.id, cli: cli);
      }
      if (kind == CliBinaryKind.adapter) {
        await rememberRemoteAcpAdapterPathIfNeeded(
          targetId: target.id,
          cli: cli,
          resolvedPath: path,
          readAcpAdapterPathOverride: acpAdapterPathOverride,
          writeAcpAdapterPathOverride: setAcpAdapterPathOverride,
        );
      } else {
        await rememberRemoteCliPathIfNeeded(
          targetId: target.id,
          cli: cli,
          resolvedPath: path,
          readCliPathOverride: cliPathOverride,
          writeCliPathOverride: setCliPathOverride,
        );
      }
      return RemoteCliReady(targetId: target.id, cli: cli, path: path);
    } on Object catch (e, st) {
      final message = remoteCliFailureMessage(e);
      appLogger.w(
        '[remote-cli] locate failed target=${target.id} cli=${cli.value} '
        'kind=${kind.name}: $message',
        error: e,
        stackTrace: st,
      );
      return RemoteCliFailed(targetId: target.id, cli: cli, message: message);
    }
  }

  /// User-driven install on [target]. Remembers the resolved path on success.
  Future<RemoteCliReadiness> install({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
    void Function(CliInstallProgress progress)? onProgress,
  }) {
    if (kind == CliBinaryKind.adapter) {
      return _installAdapter(
        target: target,
        cli: cli,
        onProgress: onProgress,
      );
    }
    return _installCli(target: target, cli: cli, onProgress: onProgress);
  }

  Future<RemoteCliReadiness> _installCli({
    required RuntimeTarget target,
    required CliTool cli,
    void Function(CliInstallProgress progress)? onProgress,
  }) async {
    if (!usesSshTransport(target.kind)) {
      throw ArgumentError(
        'install requires an SSH transport target, got ${target.id}',
      );
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
        registry.capability<CliExecutableCapability>(cli)?.supportsInstaller ??
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
      final run = await _runnerFor(profile, includeStderr: true);
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
    } on Object catch (e, st) {
      final message = remoteCliFailureMessage(e);
      appLogger.w(
        '[remote-cli] install failed target=${target.id} cli=${cli.value}: '
        '$message',
        error: e,
        stackTrace: st,
      );
      return RemoteCliFailed(targetId: target.id, cli: cli, message: message);
    }
  }

  Future<RemoteCliReadiness> _installAdapter({
    required RuntimeTarget target,
    required CliTool cli,
    void Function(CliInstallProgress progress)? onProgress,
  }) async {
    if (!usesSshTransport(target.kind)) {
      throw ArgumentError(
        'install requires an SSH transport target, got ${target.id}',
      );
    }
    final profile = profileById(target.sshProfileId ?? '');
    if (profile == null) {
      return RemoteCliFailed(
        targetId: target.id,
        cli: cli,
        message: 'No SSH profile for target "${target.id}".',
      );
    }
    final installer =
        registry.capability<AcpSettingsCapability>(cli)?.adapterInstaller;
    if (installer == null) {
      return RemoteCliFailed(
        targetId: target.id,
        cli: cli,
        message:
            '${cli.value} has no ACP adapter installer; set a manual adapter '
            'path for this target.',
      );
    }

    try {
      final run = await _runnerFor(profile, includeStderr: true);
      final existing = await _locateAdapterWithRun(
        target: target,
        cli: cli,
        run: run,
      );
      final path = existing ??
          await (_adapterInstallActionBuilder?.call(installer, profile, run) ??
                  buildRemotePreflightAdapterInstall(
                    installer: installer,
                    profile: profile,
                  ))(
            run: run,
            onProgress: onProgress ?? (_) {},
          );
      await rememberRemoteAcpAdapterPathIfNeeded(
        targetId: target.id,
        cli: cli,
        resolvedPath: path,
        readAcpAdapterPathOverride: acpAdapterPathOverride,
        writeAcpAdapterPathOverride: setAcpAdapterPathOverride,
      );
      return RemoteCliReady(targetId: target.id, cli: cli, path: path);
    } on Object catch (e, st) {
      final message = remoteCliFailureMessage(e);
      appLogger.w(
        '[remote-cli] adapter install failed target=${target.id} '
        'cli=${cli.value}: $message',
        error: e,
        stackTrace: st,
      );
      return RemoteCliFailed(targetId: target.id, cli: cli, message: message);
    }
  }

  Future<String?> _locateCli({
    required RuntimeTarget target,
    required CliTool cli,
  }) async {
    final profile = profileById(target.sshProfileId ?? '');
    if (profile == null) {
      throw StateError('No SSH profile for target "${target.id}".');
    }
    final run = await _runnerFor(profile, includeStderr: false);
    return _locateCliWithRun(target: target, cli: cli, run: run);
  }

  Future<String?> _locateCliWithRun({
    required RuntimeTarget target,
    required CliTool cli,
    required SshCommandRunner run,
  }) async {
    final storedPath = (await cliPathOverride(target.id, cli.value) ?? '')
        .trim();
    return _installer.locate(
      cli: cli,
      run: run,
      manualPathOverride: storedPath,
    );
  }

  Future<String?> _locateAdapter({
    required RuntimeTarget target,
    required CliTool cli,
  }) async {
    final profile = profileById(target.sshProfileId ?? '');
    if (profile == null) {
      throw StateError('No SSH profile for target "${target.id}".');
    }
    final run = await _runnerFor(profile, includeStderr: false);
    return _locateAdapterWithRun(target: target, cli: cli, run: run);
  }

  Future<String?> _locateAdapterWithRun({
    required RuntimeTarget target,
    required CliTool cli,
    required SshCommandRunner run,
  }) async {
    final stored =
        (await acpAdapterPathOverride(target.id, cli.value) ?? '').trim();
    if (stored.isNotEmpty) return stored;
    final located = await AcpAdapterDiscovery(
      registry: registry,
    ).locateRemote(run: run);
    return located[cli];
  }
}

/// User-facing install/probe error text without Dart's `Bad state:` prefix.
String remoteCliFailureMessage(Object error) {
  if (error is StateError) {
    final message = error.message.trim();
    if (message.isNotEmpty) return message;
  }
  return '$error';
}
