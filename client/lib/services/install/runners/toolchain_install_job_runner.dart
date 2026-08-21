import 'package:meta/meta.dart';

import '../../../models/install_job/install_job_context.dart';
import '../../../models/install_job/install_job_key.dart';
import '../../../models/install_job/install_job_spec.dart';
import '../../../models/session_preferences.dart';
import '../../cli/git_installer.dart';
import '../install_job_runner.dart';

typedef GitInstallInvoke =
    Future<GitInstallResult> Function({
      GitInstallProgressCallback? onProgress,
      bool Function()? isCancelled,
    });

final class ToolchainInstallJobRunner implements InstallJobRunner {
  ToolchainInstallJobRunner({
    GitInstaller Function()? installerFactory,
    @visibleForTesting GitInstallInvoke? installOverride,
  }) : _installerFactory = installerFactory ?? (() => const GitInstaller()),
       _installOverride = installOverride;

  final GitInstaller Function() _installerFactory;
  final GitInstallInvoke? _installOverride;

  @override
  InstallJobKind get kind => InstallJobKind.toolchain;

  @override
  bool supports(InstallJobKey key) {
    return key.kind == kind && key.target == SessionPreferences.toolchainGit;
  }

  @override
  Future<T> run<T>(InstallJobSpec<T> spec, InstallJobContext ctx) async {
    if (!supports(spec.key)) {
      throw StateError('Unsupported toolchain target: ${spec.key.target}');
    }

    final result = await _install(
      onProgress: (progress) => _reportGitProgress(ctx, progress),
      isCancelled: () => ctx.isCancelled,
    );

    if (!result.success) {
      throw StateError(result.message);
    }
    return result as T;
  }

  Future<GitInstallResult> _install({
    GitInstallProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) {
    final override = _installOverride;
    if (override != null) {
      return override(onProgress: onProgress, isCancelled: isCancelled);
    }
    return _installerFactory().install(
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }
}

void _reportGitProgress(InstallJobContext ctx, GitInstallProgress progress) {
  final phaseLabel = _gitInstallPhaseLabel(progress.phase);
  final detail = progress.detail?.trim();
  if (detail != null && detail.isNotEmpty) {
    ctx.reportPhase(phaseLabel, detail: detail);
    return;
  }
  ctx.reportPhase(phaseLabel);
}

String _gitInstallPhaseLabel(GitInstallPhase phase) => switch (phase) {
  GitInstallPhase.checking => 'Checking git',
  GitInstallPhase.installing => 'Installing git',
  GitInstallPhase.locating => 'Locating git',
};
