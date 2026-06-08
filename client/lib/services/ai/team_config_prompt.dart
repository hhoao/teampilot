import 'team_config_draft.dart';

/// Builds the prompt that constrains AI output to legal team options.
///
/// The user [description] is interpolated unescaped. Acceptable: it is a
/// local-only desktop feature, the user authored the text, the draft is shown
/// for review before a team is created, and the parsed output is additionally
/// clamped to a whitelist of legal models/efforts/skills by [parseTeamConfigDraft].
String buildTeamConfigPrompt({
  required String description,
  required TeamDraftAllowedOptions allowed,
  required TeamGenGranularity granularity,
}) {
  final full = granularity == TeamGenGranularity.fullTeam;
  final models = allowed.models.join(', ');
  final efforts = allowed.efforts.join(', ');

  final memberShape = '{"name": string, "role": string, '
      '"model": one of [$models], "effort": one of [$efforts]}';

  final schema = full
      ? '{\n'
            '  "teamName": string,\n'
            '  "mode": "native" or "mixed",\n'
            '  "members": [$memberShape, ...],\n'
            '  "skillIds": subset of [${allowed.skillIds.join(', ')}]\n'
            '}'
      : '{\n  "members": [$memberShape, ...]\n}';

  return '''
You design an AI agent team from a description. Output STRICT JSON only.

Description:
$description

Constraints:
- "model" MUST be one of: [$models].
- "effort" MUST be one of: [$efforts], or omit it.
${full ? '- "skillIds" MUST be a subset of: [${allowed.skillIds.join(', ')}].\n- "mode" MUST be "native" or "mixed".' : '- Only output members; do not include team-level fields.'}
- Give each member a short human name and a concise role.
- Output ONLY the JSON object below, no prose, no code fences.

JSON schema:
$schema
''';
}
