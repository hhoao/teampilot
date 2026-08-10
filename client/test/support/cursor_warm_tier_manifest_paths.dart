import 'package:teampilot/services/cli/session_lifecycle/cli_session_manifest.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_workspace_warm_tier.dart';

const cursorTestTeamId = 'team-a';

/// Shared warm-tier manifest paths for cursor lifecycle tests.
CliSessionManifestShared cursorTestSharedManifest({
  required String slug,
  String teamId = cursorTestTeamId,
}) {
  final sharedRootRelative = CursorWorkspaceWarmTier.sharedRootRelative(teamId);
  final warm = CursorWorkspaceWarmTier.manifestPaths(sharedRootRelative);
  return CliSessionManifestShared(
    root: warm.root,
    projectsDir: '$sharedRootRelative/projects/$slug',
    cliConfigBase: '$sharedRootRelative/cli-config.base.json',
    pluginsLocalDir: warm.pluginsLocalDir,
    skillsCursorDir: warm.skillsCursorDir,
    mcpBase: warm.mcpBase,
    settingsJson: warm.settingsJson,
  );
}

String cursorTestMemberHomeRelative(String memberId, {String teamId = cursorTestTeamId}) =>
    'runtime/teams/$teamId/$memberId/cursor/home';
