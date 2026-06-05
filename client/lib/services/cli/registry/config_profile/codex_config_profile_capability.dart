import 'package:flutter/foundation.dart';

import '../../../../models/team_config.dart';
import '../../../../repositories/app_provider_repository.dart';
import '../../../provider/codex/codex_home_provisioner.dart';
import '../../../provider/codex/codex_provider_settings_resolver.dart';
import '../../../provider/codex/codex_team_bus_overlay.dart';
import '../../../session/member_role_provision.dart';
import '../capabilities/config_profile_capability.dart';

/// Codex CLI launch: provisions provider `auth.json` + `config.toml` under
/// per-member [CODEX_HOME], optional team-bus overlay in mixed mode, and
/// member identity in `AGENTS.md`.
final class CodexConfigProfileCapability implements ConfigProfileCapability {
  const CodexConfigProfileCapability();

  static const toolId = 'codex';
  static const agentsFileName = 'AGENTS.md';

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {}

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    final paths = ctx.paths;
    final codexHome = paths.sessionToolDir(
      ctx.scope.teamId,
      ctx.scope.sessionId,
      toolId,
    );

    final member = ctx.member;
    final team = ctx.team;
    final mixed = team?.teamMode == TeamMode.mixed;
    final warnings = <String>[];

    await paths.fs.ensureDir(codexHome);

    if (team != null) {
      final resolver = CodexProviderSettingsResolver(
        basePath: paths.basePath,
        repository: AppProviderRepository(
          basePath: paths.basePath,
          fs: paths.fs,
        ),
      );
      final provider = await resolver.resolveForLaunch(
        team: team,
        member: member,
      );
      if (provider == null) {
        warnings.add('codex_provider_missing');
      } else {
        final port = mixed ? _parseBusPort(ctx.busIdleUrl) : null;
        final busOverlay =
            mixed && port != null && member != null && member.isValid
            ? CodexTeamBusOverlay.build(memberId: member.id, port: port)
            : null;
        final trustedDirectories = <String>[
          if ((ctx.workingDirectory ?? '').trim().isNotEmpty)
            ctx.workingDirectory!.trim(),
          for (final dir in ctx.additionalDirectories)
            if (dir.trim().isNotEmpty) dir.trim(),
        ];
        try {
          await CodexHomeProvisioner(fs: paths.fs).provision(
            codexHome: codexHome,
            provider: provider,
            busOverlayToml: busOverlay,
            trustedProjectDirectories: trustedDirectories,
          );
        } on CodexHomeProvisionException catch (e) {
          warnings.add('codex_config_invalid: $e');
        }
      }
    } else {
      warnings.add('codex_provider_missing');
    }

    if (member != null && member.isValid) {
      final prompt = MemberRoleProvision.composeRolePrompt(
        member: member,
        forceTeamLeadDelegateMode: team?.forceTeamLeadDelegateMode ?? false,
        mixed: mixed,
      ).trim();
      if (prompt.isNotEmpty) {
        await paths.fs.atomicWrite(
          paths.pathContext.join(codexHome, agentsFileName),
          '$prompt\n',
        );
      }
    }

    return ConfigProfileLaunchContribution(
      environment: {'CODEX_HOME': codexHome},
      warnings: warnings,
    );
  }

  /// Back-compat for tests that target the team-bus overlay fragment only.
  @visibleForTesting
  static String buildCodexConfigToml({
    required String memberId,
    required int port,
  }) =>
      CodexTeamBusOverlay.build(memberId: memberId, port: port);

  static int? _parseBusPort(String? idleUrl) {
    if (idleUrl == null || idleUrl.isEmpty) return null;
    final uri = Uri.tryParse(idleUrl);
    if (uri == null || !uri.hasPort) return null;
    return uri.port;
  }
}
