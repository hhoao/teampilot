import 'dart:async';

import '../../models/install_job/install_cancel_policy.dart';
import '../../models/install_job/install_job_scope.dart';
import '../../models/install_job/install_job_spec.dart';
import '../../models/team_config.dart';
import '../cli/cli_installer_service.dart';
import '../cli/git_installer.dart';
import 'install_job_keys.dart';
import 'install_job_registry.dart';

extension InstallJobEnqueue on InstallJobRegistry {
  Future<CliInstallResult> installCli({
    required CliTool cli,
    required InstallJobScope scope,
    required String title,
    String? subtitle,
    FutureOr<void> Function(CliInstallResult result)? onSucceeded,
    FutureOr<void> Function(Object error)? onFailed,
    String? historyTitle,
    String? Function(CliInstallResult result)? historyMessageFor,
  }) {
    final runnerRegistry = this.runnerRegistry;
    if (runnerRegistry == null) {
      throw StateError('InstallJobRegistry has no runner registry');
    }
    final key = InstallJobKeys.cli(cli.value, scope: scope);
    final runner = runnerRegistry.resolve(key);
    if (runner == null) {
      throw StateError('No InstallJobRunner for ${key.kind}');
    }
    late final InstallJobSpec<CliInstallResult> spec;
    spec = InstallJobSpec(
      key: key,
      title: title,
      subtitle: subtitle,
      cancelPolicy: InstallCancelPolicy.cooperative,
      onSucceeded: onSucceeded,
      onFailed: onFailed,
      historyTitle: historyTitle,
      historyMessageFor: historyMessageFor,
      run: (ctx) => runner.run(spec, ctx),
    );
    return enqueue(spec);
  }

  Future<GitInstallResult> installToolchain({
    required String toolId,
    required InstallJobScope scope,
    required String title,
    String? subtitle,
    FutureOr<void> Function(GitInstallResult result)? onSucceeded,
    FutureOr<void> Function(Object error)? onFailed,
    String? historyTitle,
    String? Function(GitInstallResult result)? historyMessageFor,
  }) {
    final runnerRegistry = this.runnerRegistry;
    if (runnerRegistry == null) {
      throw StateError('InstallJobRegistry has no runner registry');
    }
    final key = InstallJobKeys.toolchain(toolId, scope: scope);
    final runner = runnerRegistry.resolve(key);
    if (runner == null) {
      throw StateError('No InstallJobRunner for ${key.kind}');
    }
    late final InstallJobSpec<GitInstallResult> spec;
    spec = InstallJobSpec(
      key: key,
      title: title,
      subtitle: subtitle,
      cancelPolicy: InstallCancelPolicy.cooperative,
      onSucceeded: onSucceeded,
      onFailed: onFailed,
      historyTitle: historyTitle,
      historyMessageFor: historyMessageFor,
      run: (ctx) => runner.run(spec, ctx),
    );
    return enqueue(spec);
  }
}
