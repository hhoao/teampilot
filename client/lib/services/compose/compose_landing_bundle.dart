import '../../models/config_bundle.dart';
import '../../models/landing_launch_context.dart';
import '../../models/team_config.dart';

/// Enable lists from the active landing identity.
///
/// Simple mode has no identity bundle — workspace + expert pack supply deps.
/// Team mode uses the team [ConfigBundle].
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

/// Landing slash menu uses skills/plugins enabled on identity or workspace.
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
