import '../../../models/install_job/install_job_context.dart';
import '../../../models/install_job/install_job_key.dart';
import '../../../models/install_job/install_job_scope.dart';
import '../../../models/install_job/install_job_spec.dart';
import '../../../models/ssh_profile.dart';
import '../../../models/team_config.dart';
import '../../cli/cli_installer_service.dart';
import '../../cli/installer_types.dart';
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
    return CliTool.tryParse(key.target) != null;
  }

  @override
  Future<T> run<T>(InstallJobSpec<T> spec, InstallJobContext ctx) async {
    final cli = CliTool.tryParse(spec.key.target);
    if (cli == null) {
      throw StateError('Unknown CLI target: ${spec.key.target}');
    }

    final (mode, sshProfile) = _resolveInstallTarget(spec.key.scope);
    final result = await _installerFactory().install(
      cli: cli,
      mode: mode,
      sshProfile: sshProfile,
      onProgress: (progress) => _reportCliProgress(ctx, progress),
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

String _cliInstallPhaseLabel(CliInstallPhase phase) => switch (phase) {
  CliInstallPhase.checkingNpm => 'Checking npm',
  CliInstallPhase.bootstrappingNode => 'Bootstrapping Node',
  CliInstallPhase.installingCli => 'Installing CLI',
  CliInstallPhase.locatingExecutable => 'Locating executable',
  CliInstallPhase.syncingRemoteWorkspace => 'Syncing remote workspace',
};
