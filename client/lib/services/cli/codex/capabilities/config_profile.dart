import '../../../../models/team_config.dart';
import 'provider.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../../../provider/workspace_trust_provisioner.dart';
import '../../registry/capabilities/config_profile_capability.dart';
import '../../registry/capabilities/prompt_capability.dart';
import '../../registry/prompt/prompt_hub_service.dart';

/// Codex CLI launch: provisions provider `auth.json` + `config.toml` under
/// per-member [CODEX_HOME], optional team-bus overlay in mixed mode, and
/// member identity in `AGENTS.md`.
final class CodexConfigProfileCapability implements ConfigProfileCapability {
  const CodexConfigProfileCapability();

  static const toolId = 'codex';

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {}

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    final warnings = <String>[];

    await _provisionWorkspaceTrust(
      paths: ctx.paths,
      workspaceId: ctx.scope.workspaceId,
      workingDirectory: ctx.workingDirectory ?? '',
      additionalDirectories: ctx.additionalDirectories,
    );

    final contribution = await const CodexProviderCapability()
        .materializeSessionHome(sessionHomeContextFromLaunch(ctx, CliTool.codex));
    warnings.addAll(contribution.warnings);

    final member = ctx.member;
    final team = ctx.team;
    final mixed = team?.teamMode == TeamMode.mixed;
    await const PromptHubService().provisionForCli(
      cli: CliTool.codex,
      ctx: PromptMaterializeContext(
        paths: ctx.paths,
        scope: ctx.scope,
        member: member,
        forceTeamLeadDelegateMode: team?.forceTeamLeadDelegateMode ?? false,
        mixed: mixed,
      ),
    );

    return ConfigProfileLaunchContribution(
      environment: contribution.environment,
      warnings: warnings,
    );
  }

  Future<void> _provisionWorkspaceTrust({
    required ConfigProfileDelegate paths,
    required String workspaceId,
    required String workingDirectory,
    List<String> additionalDirectories = const [],
  }) {
    return WorkspaceTrustProvisioner(
      layout: paths.layout,
      fs: paths.fs,
    ).provisionWorkspace(
      workspaceId: workspaceId,
      directories: [
        if (workingDirectory.trim().isNotEmpty) workingDirectory.trim(),
        for (final directory in additionalDirectories)
          if (directory.trim().isNotEmpty) directory.trim(),
      ],
      tools: const [CodexConfigProfileCapability.toolId],
    );
  }
}
