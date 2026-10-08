import 'package:teampilot/services/cli/session_lifecycle/cli_session_manifest.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_workspace_warm_tier.dart';

const cursorTestTeamId = 'team-a';
const cursorTestSessionId = 'sess';

/// Lifecycle manifest paths for cursor mixed-mode tests.
CliSessionManifestShared cursorTestSharedManifest({
  required String slug,
  String teamId = cursorTestTeamId,
}) {
  final sharedRootRelative = CursorWorkspaceWarmTier.sharedRootRelative(teamId);
  return CliSessionManifestShared(
    root: sharedRootRelative,
    projectsDir: '$sharedRootRelative/projects/$slug',
    cliConfigBase: '',
    pluginsLocalDir: '',
    skillsCursorDir: '',
    mcpBase: '',
    settingsJson: '',
  );
}

String cursorTestMemberHomeRelative(
  String memberId, {
  String teamId = cursorTestTeamId,
  String sessionId = cursorTestSessionId,
}) =>
    'sessions/$sessionId/runtime/$memberId/cursor/home';
