import '../tools/finalize_team_generation_tool.dart';
import '../tools/get_generation_context_tool.dart';
import '../tools/probe_workspace_targets_tool.dart';
import '../tools/validate_team_plan_tool.dart';
import 'team_composer_tool.dart';

/// All Team Composer tools advertised on `tools/list`.
const allTeamComposerTools = <TeamComposerTool>[
  GetGenerationContextTool(),
  ProbeWorkspaceTargetsTool(),
  ValidateTeamPlanTool(),
  FinalizeTeamGenerationTool(),
];

Map<String, TeamComposerTool> teamComposerToolByName() => {
  for (final tool in allTeamComposerTools) tool.name: tool,
};

/// Build the `tools/list` payload.
List<Map<String, Object?>> listAdvertisedTeamComposerTools() => [
  for (final tool in allTeamComposerTools) tool.toJson(),
];
