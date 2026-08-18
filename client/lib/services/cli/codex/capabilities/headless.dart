import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../models/app_provider_config.dart';
import '../../../../models/team_config.dart';
import '../../registry/capabilities/headless_capability.dart';
import '../../registry/headless/headless_provision_support.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_capability_error.dart';
import '../../registry/launch/cli_headless_launch_context.dart';
import '../../registry/launch/headless_launch_context_adapter.dart';
import '../../registry/launch/user_extra_args_provider.dart';
import 'permission_launch.dart';
import 'workspace_access_launch.dart';
import '../provider/codex_auth_artifacts.dart';
import '../provider/codex_home_provisioner.dart';
import '../provider/codex_official_provider.dart';
import '../provider/codex_provider_settings_resolver.dart';

/// Codex one-shot via `codex exec` (effort via `-c model_reasoning_effort=`),
/// plus provisioning of an isolated `CODEX_HOME` (config + auth).
final class CodexHeadlessCapability
    with HeadlessProvisionSupport
    implements HeadlessCapability {
  const CodexHeadlessCapability();

  @override
  bool get isSupported => true;

  @override
  bool get supportsStreaming => false;

  @override
  String get executable => 'codex';

  @override
  Map<String, String> buildEnvironment(HeadlessLaunchContext context) => {
    'CODEX_HOME': context.configDir,
  };

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  Iterable<CliLaunchArgContribution> buildHeadlessLaunchArgs(
    CliHeadlessLaunchContext ctx,
  ) sync* {
    final interactive = interactiveContextForHeadless(ctx, CliTool.codex);
    final resume = ctx.resumeSessionId?.trim() ?? '';
    final fixed = ctx.fixedSessionId?.trim() ?? '';
    if (fixed.isNotEmpty) {
      throw const CliLaunchCapabilityException(
        cli: CliTool.codex,
        contributionKey: 'codex-headless-session',
        reason: 'Codex headless exec does not support fixed session ids.',
      );
    }
    yield CliLaunchArgContribution(
      key: 'codex-headless-command',
      phase: LaunchArgPhase.command,
      args: [
        'exec',
        if (resume.isNotEmpty) ...['resume', resume],
      ],
    );
    final model = ctx.model.trim();
    if (model.isNotEmpty) {
      yield CliLaunchArgContribution(
        key: 'codex-headless-model',
        phase: LaunchArgPhase.model,
        args: ['--model', model],
      );
    }
    final effort = ctx.effort.trim();
    if (effort.isNotEmpty) {
      yield CliLaunchArgContribution(
        key: 'codex-headless-effort',
        phase: LaunchArgPhase.model,
        args: ['-c', 'model_reasoning_effort=$effort'],
      );
    }
    yield* const CodexWorkspaceAccessLaunch().buildLaunchArgs(interactive);
    yield* const CodexPermissionLaunch().buildLaunchArgs(interactive);
    yield CliLaunchArgContribution(
      key: 'codex-headless-prompt',
      phase: LaunchArgPhase.prompt,
      args: [ctx.prompt],
    );
    yield* const UserExtraArgsProvider().buildLaunchArgs(interactive);
  }

  @override
  String extractText(ProcessResult result) =>
      (result.stdout as String? ?? '').trim();

  @override
  String? streamResultText(String line) => null;

  @override
  Future<HeadlessProvisionResult> provision(
    HeadlessProvisionContext ctx,
  ) async {
    final fs = this.fs;
    await fs.ensureDir(ctx.configDir);

    final warnings = <String>[];
    final resolved =
        ctx.provider ??
        await CodexProviderSettingsResolver(
          basePath: basePath,
          repository: repository,
        ).findById(ctx.providerId);
    if (resolved == null) {
      return const HeadlessProvisionResult(
        warnings: ['codex_provider_missing'],
        credentialsReady: false,
      );
    }

    final trusted = <String>[
      if (ctx.workingDirectory != null &&
          ctx.workingDirectory!.trim().isNotEmpty)
        ctx.workingDirectory!.trim(),
    ];
    try {
      await CodexHomeProvisioner(fs: fs).provision(
        codexHome: ctx.configDir,
        provider: resolved,
        trustedProjectDirectories: trusted,
        storedAuthPath: _storedCodexAuthPath(resolved),
        reasoningEffortOverride: ctx.effort.trim().isNotEmpty
            ? ctx.effort.trim()
            : null,
        providerDir: p.join(basePath, 'providers', 'codex', resolved.id),
      );
    } on CodexHomeProvisionException catch (e) {
      warnings.add('codex_config_invalid: $e');
      return HeadlessProvisionResult(
        warnings: warnings,
        credentialsReady: false,
      );
    }

    if (isOfficialCodexOAuthProvider(resolved)) {
      final authPath = p.join(ctx.configDir, CodexAuthArtifacts.authFileName);
      if (!(await fs.stat(authPath)).isFile) {
        warnings.add('codex_credentials_missing');
        return HeadlessProvisionResult(
          warnings: warnings,
          credentialsReady: false,
        );
      }
    }

    return HeadlessProvisionResult(warnings: warnings);
  }

  String? _storedCodexAuthPath(AppProviderConfig provider) {
    if (!isOfficialCodexOAuthProvider(provider)) return null;
    return p.join(
      basePath,
      'providers',
      'codex',
      provider.id,
      CodexAuthArtifacts.authFileName,
    );
  }
}
