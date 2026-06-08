import 'team_config_prompt_spec.dart';

/// Builds the native-mode (single-CLI native team) generation prompt.
String buildNativeTeamConfigPrompt({required String description}) {
  return '''
${TeamPromptSpec.identity}

This is a NATIVE team: all members share one CLI and one roster. The team-lead delegates by member name; teammates report back to the lead.

${TeamPromptSpec.ironLaw}

Description:
$description

${TeamPromptSpec.compositionRules}

${TeamPromptSpec.fieldRubric}

Generate ONLY the team shape and prose below. Do NOT emit model, effort, skillIds, or cli fields — the user configures those after creation.

${TeamPromptSpec.languageLock}

<example>
{
  "teamName": "auth-revamp",
  "description": "Ship the OAuth migration. The lead decomposes and integrates; workers own implementation and review. Scope is the auth module only.",
  "members": [
    {"name": "team-lead", "role": "coordinator",
     "responsibilities": "Break the request into a task list with scope and acceptance criteria, then assign by member name. Do NOT implement large changes yourself.",
     "workingMethod": "Read code and docs to understand the task, create the task list, assign teammates, then synthesize their results into one reply with files, decisions, and next steps. Escalate blockers to the user."},
    {"name": "implementer", "role": "backend developer",
     "responsibilities": "Implement assigned auth tasks within the agreed scope. Do NOT refactor unrelated code.",
     "workingMethod": "Work test-first: write a failing test, make it pass with the smallest diff, run the suite, and report changed files with reasons. Follow test-driven-development if available. Stop at agreed checkpoints."},
    {"name": "reviewer", "role": "code reviewer",
     "responsibilities": "Review the implementer's diffs for correctness and scope creep. Do NOT modify files yourself.",
     "workingMethod": "Inspect each diff against the task's acceptance criteria, list concrete issues by file and line, then approve or request changes. Escalate disagreements to the lead."}
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
