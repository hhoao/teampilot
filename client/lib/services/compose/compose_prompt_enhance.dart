import '../../cubits/app_provider_cubit.dart';
import '../../models/ai_feature_setting.dart';
import '../../models/cli_preset.dart';
import '../../models/landing_launch_context.dart';
import '../../models/simple_launch_identity.dart';
import '../../models/team_config.dart';
import '../ai/ai_feature_setting_resolver.dart';
import '../ai/commit_message_prompt.dart';
import '../cli/registry/cli_tool_registry.dart';

/// Builds the headless prompt that rewrites a compose draft into a clearer ask.
String buildComposeEnhancePrompt(String draft) {
  return '''
You improve user prompts for an AI coding assistant.

Rules:
- Keep the user's intent and language (if they wrote in Chinese, respond in Chinese).
- Make the request clearer, more specific, and actionable.
- Add relevant context hints only when obvious from the draft.
- Do not answer the request — only rewrite it as a better prompt.
- Output ONLY the improved prompt. No explanations, no quotes, no markdown fences.

Draft prompt:
$draft
''';
}

/// Cleans model output into a bare enhanced prompt.
String cleanComposeEnhanceOutput(String raw) => cleanCommitMessageOutput(raw);

/// Resolves the headless AI setting for landing compose enhance from the draft.
AiFeatureSetting? resolveLandingEnhanceSetting({
  required LandingLaunchContext draft,
  required List<CliPreset> presets,
  required List<TeamProfile> teams,
  required AppProviderState appProviders,
  required CliToolRegistry registry,
}) {
  if (draft.isPersonal) {
    final presetId = draft.presetId?.trim() ?? '';
    if (presetId.isNotEmpty) {
      final preset = presets.where((p) => p.id == presetId).firstOrNull;
      final selected = preset ?? presets.firstOrNull;
      if (selected == null || selected.provider.trim().isEmpty) return null;
      return resolveAiFeatureSetting(
        stored: AiFeatureSetting(
          cli: selected.cli,
          providerId: selected.provider,
          model: selected.model,
          effort: selected.effort,
        ),
        appProviders: appProviders,
        registry: registry,
        globalPresets: presets,
      );
    }
    if (draft.cli != null) {
      final providerId = draft.provider?.trim().isNotEmpty == true
          ? draft.provider!.trim()
          : (SimpleLaunchIdentity.officialProviderIdFor(draft.cli!) ?? '');
      if (providerId.isEmpty) return null;
      return resolveAiFeatureSetting(
        stored: AiFeatureSetting(
          cli: draft.cli!,
          providerId: providerId,
          model: draft.model ?? '',
          effort: draft.effort ?? '',
        ),
        appProviders: appProviders,
        registry: registry,
        globalPresets: presets,
      );
    }
    final selected = presets.firstOrNull;
    if (selected == null || selected.provider.trim().isEmpty) return null;
    return resolveAiFeatureSetting(
      stored: AiFeatureSetting(
        cli: selected.cli,
        providerId: selected.provider,
        model: selected.model,
        effort: selected.effort,
      ),
      appProviders: appProviders,
      registry: registry,
      globalPresets: presets,
    );
  }

  final teamId = draft.teamId?.trim() ?? '';
  final team = teamId.isEmpty
      ? null
      : teams.where((t) => t.id == teamId).firstOrNull;
  final selectedTeam = team ?? teams.firstOrNull;
  if (selectedTeam == null) return null;

  final cli = selectedTeam.cli;
  final providerId = selectedTeam.providerForCli(cli);
  if (providerId.isEmpty) return null;

  return resolveAiFeatureSetting(
    stored: AiFeatureSetting(
      cli: cli,
      providerId: providerId,
      model: selectedTeam.modelForCli(cli),
      effort: selectedTeam.effortForCli(cli),
    ),
    appProviders: appProviders,
    registry: registry,
    globalPresets: presets,
  );
}
