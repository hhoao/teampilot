import '../../cubits/expert_hub_cubit.dart';
import '../../models/config_bundle.dart';
import '../../models/discoverable_member.dart';
import '../../models/landing_launch_context.dart';
import '../../models/team_config.dart';
import '../expert_hub/expert_landing_preflight.dart';
import '../expert_hub/expert_member_resolver.dart';
import '../launch/layered_config_bundle.dart';

/// Slash enable-list for Landing / review compose.
///
/// Simple: [LayeredConfigBundle.merge] expert deps (empty key → default) +
/// workspace. Team: team config + workspace. Does not install deps.
ConfigBundle slashBundleForLanding({
  required LandingLaunchContext draft,
  TeamProfile? team,
  required ConfigBundle workspace,
  ExpertHubState? hubState,
}) {
  if (!draft.isPersonal) {
    final teamBundle = team == null
        ? const ConfigBundle()
        : ConfigBundle(
            skillIds: team.skillIds,
            pluginIds: team.pluginIds,
            mcpServerIds: team.mcpServerIds,
          );
    return LayeredConfigBundle.merge(team: teamBundle, workspace: workspace);
  }

  final key = resolveLandingSessionExpertKey(draft.expertKey);
  final member = ExpertMemberResolver.resolve(key: key, hubState: hubState);
  final expert = member == null
      ? const ConfigBundle()
      : _bundleFromExpertDeps(member);
  return LayeredConfigBundle.merge(expert: expert, workspace: workspace);
}

ConfigBundle _bundleFromExpertDeps(DiscoverableMember member) {
  return ConfigBundle(
    skillIds: [
      for (final d in member.skillDeps)
        if (d.expectedLocalId.trim().isNotEmpty) d.expectedLocalId,
    ],
    pluginIds: [
      for (final d in member.pluginDeps)
        if (d.expectedLocalId.trim().isNotEmpty) d.expectedLocalId,
    ],
    mcpServerIds: [
      for (final d in member.mcpDeps)
        if (d.id.trim().isNotEmpty) d.id,
    ],
  );
}
