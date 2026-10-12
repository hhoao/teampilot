import '../../../models/install_job/install_job_context.dart';
import '../../../models/install_job/install_job_key.dart';
import '../../../models/install_job/install_job_scope.dart';
import '../../../models/install_job/install_job_spec.dart';
import '../../../models/ssh_profile.dart';
import '../../../models/team_config.dart';
import '../../cli/claude/capabilities/acp_adapter_installer.dart';
import '../../cli/cli_installer_service.dart';
import '../../cli/codex/capabilities/acp_adapter_installer.dart';
import '../../cli/registry/installer/npm_installer_capability.dart';
import '../install_job_runner.dart';

typedef SshProfileById = SshProfile? Function(String profileId);

final class CliInstallJobRunner implements InstallJobRunner {
  CliInstallJobRunner({
    required CliInstallerService Function() installerFactory,
    SshProfileById? sshProfileById,
  }) : _installerFactory = installerFactory,
       _sshProfileById = sshProfileById;

  final CliInstallerService Function() _installerFactory;
  final SshProfileById? _sshProfileById;

  @override
  InstallJobKind get kind => InstallJobKind.cliExecutable;

  @override
  bool supports(InstallJobKey key) {
    if (key.kind != kind) return false;
    return _adapterFor(key.target) != null ||
        CliTool.tryParse(key.target) != null;
  }

  @override
  Future<T> run<T>(InstallJobSpec<T> spec, InstallJobContext ctx) async {
    final adapter = _adapterFor(spec.key.target);
    final cli = CliTool.tryParse(spec.key.target);
    if (adapter == null && cli == null) {
      throw StateError('Unknown CLI target: ${spec.key.target}');
    }

    final (mode, sshProfile) = _resolveInstallTarget(spec.key.scope);
    void onProgress(CliInstallProgress progress) =>
        _reportCliProgress(ctx, progress);
    final result = adapter != null
        ? await _installerFactory().installAdapter(
            installer: adapter,
            mode: mode,
            sshProfile: sshProfile,
            onProgress: onProgress,
            isCancelled: () => ctx.isCancelled,
            onProcessStarted: ctx.registerProcess,
          )
        : await _installerFactory().install(
            cli: cli!,
            mode: mode,
            sshProfile: sshProfile,
            onProgress: onProgress,
            isCancelled: () => ctx.isCancelled,
            onProcessStarted: ctx.registerProcess,
          );

    if (!result.success) {
      throw StateError(result.message);
    }
    return result as T;
  }

  (CliInstallMode, SshProfile?) _resolveInstallTarget(InstallJobScope scope) {
    return switch (scope) {
      InstallJobScopeLocal() => (CliInstallMode.local, null),
      InstallJobScopeSsh(:final profileId) => _resolveSsh(profileId),
    };
  }

  (CliInstallMode, SshProfile?) _resolveSsh(String profileId) {
    final profile = _sshProfileById?.call(profileId);
    if (profile == null) {
      throw StateError('SSH profile not found: $profileId');
    }
    return (CliInstallMode.ssh, profile);
  }
}

void _reportCliProgress(InstallJobContext ctx, CliInstallProgress progress) {
  final phaseLabel = _cliInstallPhaseLabel(progress.phase);
  final detail = progress.detail?.trim();
  if (isUserFacingCliInstallDetail(detail)) {
    ctx.reportPhase(phaseLabel, detail: detail);
    return;
  }
  ctx.reportPhase(phaseLabel);
}

NpmInstallerCapability? _adapterFor(String target) {
  if (target == ClaudeAcpAdapterInstaller.jobTarget) {
    return const ClaudeAcpAdapterInstaller();
  }
  if (target == CodexAcpAdapterInstaller.jobTarget) {
    return const CodexAcpAdapterInstaller();
  }
  return null;
}

String _cliInstallPhaseLabel(CliInstallPhase phase) => switch (phase) {
  CliInstallPhase.checkingNpm => 'Checking npm',
  CliInstallPhase.bootstrappingNode => 'Bootstrapping Node',
  CliInstallPhase.installingCli => 'Installing CLI',
  CliInstallPhase.locatingExecutable => 'Locating executable',
  CliInstallPhase.syncingRemoteWorkspace => 'Syncing remote workspace',
};
