import 'team_config_draft.dart';
import 'team_config_prompt_spec.dart';

/// Builds the mixed-mode (cross-CLI teammate bus) generation prompt.
String buildMixedTeamConfigPrompt({
  required String description,
  required TeamDraftAllowedOptions allowed,
}) {
  final cliList = allowed.clis.map((o) => o.cli.value).join(', ');
  final perCli = allowed.clis
      .map((o) =>
          '  - ${o.cli.value}: models [${o.models.join(', ')}], efforts [${o.efforts.join(', ')}]')
      .join('\n');
  final skills = allowed.skillIds.join(', ');
  final exCli = allowed.primary.cli.value;
  final exModel = allowed.primary.defaultModel;
  final exSecond = allowed.clis.length > 1 ? allowed.clis[1] : allowed.primary;
  final exCli2 = exSecond.cli.value;
  final exModel2 = exSecond.defaultModel;

  return '''
${TeamPromptSpec.identity}

This is a MIXED team: members run on DIFFERENT CLIs and coordinate ONLY through the teammate bus (send_message / wait_for_message). The team-lead never stands down. Assign each member the CLI whose strengths best fit its role.

${TeamPromptSpec.ironLaw}

Description:
$description

${TeamPromptSpec.compositionRules}

${TeamPromptSpec.fieldRubric}
- "cli": choose one of [$cliList] per member, by role fit.

Allowed values:
- "cli" MUST be one of: [$cliList].
- For each member, "model"/"effort" MUST come from that member's chosen CLI:
$perCli
- "skillIds" MUST be a subset of: [$skills].

${TeamPromptSpec.languageLock}

<example>
{
  "teamName": "auth-revamp",
  "description": "Ship the OAuth migration across CLIs. The lead decomposes and integrates via the bus; workers own implementation and research. Scope is the auth module only.",
  "members": [
    {"name": "team-lead", "role": "coordinator", "cli": "$exCli", "model": "$exModel",
     "responsibilities": "Decompose the request into bus tasks with scope and acceptance criteria, then assign by member id. Do NOT implement large changes yourself.",
     "workingMethod": "Loop: list_teammates, add_tasks, wait_for_message. Assign by member id, collect results, then synthesize one reply with files, decisions, and next steps. Never stand down; escalate blockers to the user."},
    {"name": "implementer", "role": "backend developer", "cli": "$exCli2", "model": "$exModel2",
     "responsibilities": "Implement assigned auth tasks within scope. Do NOT refactor unrelated code.",
     "workingMethod": "Pull a task from wait_for_message, work test-first with the smallest diff, run the suite, then update_task(done) with changed files and reasons. Follow test-driven-development if available."}
  ],
  "skillIds": []
}
</example>

JSON schema:
{
  "teamName": string,
  "description": string,
  "members": [
    {"name": string, "role": string, "responsibilities": string, "workingMethod": string, "cli": one of [$cliList], "model": string, "effort": string},
    ...
  ],
  "skillIds": subset of [$skills]
}
''';
}
