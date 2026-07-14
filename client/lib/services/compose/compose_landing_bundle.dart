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

/// Legacy landing identity enable-list (empty in Simple). Prefer [slashBundleForLanding].
ConfigBundle identityBundleForLanding({
  required LandingLaunchContext draft,
  TeamProfile? team,
}) {
  if (draft.isPersonal) return const ConfigBundle();
  if (team == null) return const ConfigBundle();
  return ConfigBundle(
    skillIds: team.skillIds,
    pluginIds: team.pluginIds,
    mcpServerIds: team.mcpServerIds,
  );
}

/// Legacy ordered union of identity + workspace enable-lists. Prefer [slashBundleForLanding].
ConfigBundle unionConfigBundles(
  ConfigBundle identity,
  ConfigBundle workspace,
) {
  return ConfigBundle(
    skillIds: _unionOrdered(identity.skillIds, workspace.skillIds),
    pluginIds: _unionOrdered(identity.pluginIds, workspace.pluginIds),
    mcpServerIds: _unionOrdered(identity.mcpServerIds, workspace.mcpServerIds),
  );
}

List<String> _unionOrdered(List<String> left, List<String> right) {
  final seen = <String>{};
  final out = <String>[];
  for (final id in [...left, ...right]) {
    final trimmed = id.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) continue;
    out.add(trimmed);
  }
  return out;
}
