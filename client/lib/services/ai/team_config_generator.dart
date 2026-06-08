import 'dart:math' as math;

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

/// Function seam over HeadlessAiService.runStreaming: streams NDJSON events to
/// [onEvent] and returns the final text.
typedef TeamHeadlessStreamRunner =
    Future<String> Function({
      required AiFeatureSetting setting,
      required String prompt,
      required void Function(String line) onEvent,
    });

/// Generates a clamped [TeamConfigDraft] from a description via a headless call.
class TeamConfigGenerator {
  TeamConfigGenerator({
    TeamHeadlessRunner? runHeadless,
    TeamHeadlessStreamRunner? runHeadlessStream,
    HeadlessAiService? service,
  }) : _run =
           runHeadless ??
           (({required setting, required prompt, required expectJson}) async {
             final svc = service ?? HeadlessAiService();
             final r = await svc.run(
               setting: setting,
               prompt: prompt,
               expectJson: expectJson,
             );
             return r.text;
           }),
       _runStreaming =
           runHeadlessStream ??
           (({required setting, required prompt, required onEvent}) async {
             final svc = service ?? HeadlessAiService();
             final r = await svc.runStreaming(
               setting: setting,
               prompt: prompt,
               onEvent: onEvent,
             );
             return r.text;
           });

  final TeamHeadlessRunner _run;
  final TeamHeadlessStreamRunner _runStreaming;

  /// Maps a streamed-event count to an asymptotic progress value that eases
  /// toward — but never reaches — [_progressCeiling] until generation completes.
  static const double _progressCeiling = 0.92;

  static double progressForEvents(int events) {
    final p = 1 - math.exp(-events / 12.0);
    return (p * _progressCeiling).clamp(0.0, _progressCeiling);
  }

  /// Streams generation, reporting asymptotic [onProgress] per NDJSON event,
  /// and returns the parsed draft. Single streamed attempt (no JSON-repair
  /// retry); throws [TeamDraftFormatException] if the final text is not valid.
  Future<TeamConfigDraft> generateStreaming({
    required AiFeatureSetting setting,
    required String description,
    required TeamMode mode,
    required int joinedAt,
    required void Function(double progress) onProgress,
  }) async {
    final prompt = buildTeamConfigPrompt(mode: mode, description: description);
    var events = 0;
    final text = await _runStreaming(
      setting: setting,
      prompt: prompt,
      onEvent: (_) {
        events++;
        onProgress(progressForEvents(events));
      },
    );
    return parseTeamConfigDraft(text, joinedAt: joinedAt);
  }

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
