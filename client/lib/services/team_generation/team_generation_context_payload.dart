import '../../models/team_generation_settings.dart';
import '../../utils/team/team_member_naming.dart';
import 'models/generated_team_plan.dart';
import 'models/team_generation_job.dart';

/// Frozen payload returned by `get_generation_context`.
///
/// Kept outside the MCP wiring graph so the wire contract stays unit-testable
/// and the builder skill can rely on a single schema source.
Map<String, Object?> teamGenerationContextPayload(TeamGenerationJob job) {
  return {
    'workflowId': job.workflowId,
    'originalPrompt': job.originalPrompt,
    'settingsRevision': job.settings.revision,
    'requestedMode': job.settings.teamMode.value,
    'teamMode': job.settings.teamMode.value,
    'nativeCli': job.settings.nativeCli.value,
    'planSchema': GeneratedTeamPlan.wireSchema,
    'constraints': {
      'leadMemberName': TeamMemberNaming.teamLeadName,
      'memberCountMin': 2,
      'memberCountMax': 5,
      'replicasMin': 1,
      'replicasMax': 8,
      'leadReplicas': 1,
    },
    'modelPool': [
      for (final entry in job.settings.modelPool)
        {
          'rank': entry.rank,
          'id': effectiveTeamGenerationPoolEntryId(entry),
          'presetId': effectiveTeamGenerationPoolEntryId(entry),
          'cli': entry.preset.cli.value,
          'provider': entry.preset.provider,
          'model': entry.preset.model,
          'effort': entry.preset.effort,
          'description': entry.source.description,
          'tags': entry.source.tags,
        },
    ],
    'launch': job.launch.toJson(),
  };
}

String effectiveTeamGenerationPoolEntryId(
  EffectiveGenerateModelPoolEntry entry,
) => entry.preset.id.isNotEmpty ? entry.preset.id : entry.source.id;
