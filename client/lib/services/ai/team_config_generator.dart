import '../../models/ai_feature_setting.dart';
import '../../models/team_config.dart';
import 'headless_ai_service.dart' show HeadlessAiService;
import 'team_config_draft.dart';
import 'team_config_prompt.dart';

/// Function seam over HeadlessAiService.run that returns just the text.
typedef TeamHeadlessRunner =
    Future<String> Function({
      required AiFeatureSetting setting,
      required String prompt,
      required bool expectJson,
    });

/// Generates a clamped [TeamConfigDraft] from a description via a headless call.
class TeamConfigGenerator {
  TeamConfigGenerator({TeamHeadlessRunner? runHeadless, HeadlessAiService? service})
    : _run =
          runHeadless ??
          (({required setting, required prompt, required expectJson}) async {
            final svc = service ?? HeadlessAiService();
            final r = await svc.run(
              setting: setting,
              prompt: prompt,
              expectJson: expectJson,
            );
            return r.text;
          });

  final TeamHeadlessRunner _run;

  Future<TeamConfigDraft> generate({
    required AiFeatureSetting setting,
    required String description,
    required TeamMode mode,
    required int joinedAt,
  }) async {
    final basePrompt = buildTeamConfigPrompt(
      mode: mode,
      description: description,
    );

    for (var attempt = 0; attempt < 2; attempt++) {
      final prompt = attempt == 0
          ? basePrompt
          : '$basePrompt\n\nIMPORTANT: Your previous output was not valid JSON. '
                'Reply with ONLY the JSON object, nothing else.';
      final text = await _run(
        setting: setting,
        prompt: prompt,
        expectJson: true,
      );
      try {
        return parseTeamConfigDraft(text, joinedAt: joinedAt);
      } on TeamDraftFormatException {
        if (attempt == 1) rethrow;
      }
    }
    throw TeamDraftFormatException('Failed to generate a valid team draft.');
  }
}
