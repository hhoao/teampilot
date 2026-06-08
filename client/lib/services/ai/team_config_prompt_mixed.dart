import 'team_config_prompt_spec.dart';

/// Builds the mixed-mode (cross-CLI teammate bus) generation prompt.
String buildMixedTeamConfigPrompt({required String description}) {
  return '''
${TeamPromptSpec.identity}

This is a MIXED team: members may run on different CLIs and coordinate ONLY through the teammate bus (send_message / wait_for_message). The team-lead never stands down.

${TeamPromptSpec.ironLaw}

Description:
$description

${TeamPromptSpec.compositionRules}

${TeamPromptSpec.fieldRubric}

Generate ONLY the team shape and prose below. Do NOT emit model, effort, skillIds, or cli fields — the user configures those after creation. Write bus-aware working methods.

${TeamPromptSpec.languageLock}

<example>
{
  "teamName": "auth-revamp",
  "description": "Ship the OAuth migration across CLIs. The lead decomposes and integrates via the bus; workers own implementation and research. Scope is the auth module only.",
  "members": [
    {"name": "team-lead", "role": "coordinator",
     "responsibilities": "Decompose the request into bus tasks with scope and acceptance criteria, then assign by member id. Do NOT implement large changes yourself.",
     "workingMethod": "Loop: list_teammates, add_tasks, wait_for_message. Assign by member id, collect results, then synthesize one reply with files, decisions, and next steps. Never stand down; escalate blockers to the user."},
    {"name": "implementer", "role": "backend developer",
     "responsibilities": "Implement assigned auth tasks within scope. Do NOT refactor unrelated code.",
     "workingMethod": "Pull a task from wait_for_message, work test-first with the smallest diff, run the suite, then update_task(done) with changed files and reasons. Follow test-driven-development if available."}
  ]
}
</example>

JSON schema:
{
  "teamName": string,
  "description": string,
  "members": [
    {"name": string, "role": string, "responsibilities": string, "workingMethod": string},
    ...
  ]
}
''';
}
