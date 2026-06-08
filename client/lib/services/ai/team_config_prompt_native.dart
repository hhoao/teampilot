import 'team_config_draft.dart';
import 'team_config_prompt_spec.dart';

/// Builds the native-mode (single-CLI native team) generation prompt.
String buildNativeTeamConfigPrompt({
  required String description,
  required TeamDraftAllowedOptions allowed,
}) {
  final opts = allowed.primary;
  final models = opts.models.join(', ');
  final efforts = opts.efforts.join(', ');
  final skills = allowed.skillIds.join(', ');
  final dm = opts.defaultModel;

  return '''
${TeamPromptSpec.identity}

This is a NATIVE team: every member runs on the single CLI "${opts.cli.value}" and shares one roster. The team-lead delegates by member name; members do NOT choose a CLI.

${TeamPromptSpec.ironLaw}

Description:
$description

${TeamPromptSpec.compositionRules}

${TeamPromptSpec.fieldRubric}

Allowed values:
- "model" MUST be one of: [$models].
- "effort" MUST be one of: [$efforts], or omit it.
- "skillIds" MUST be a subset of: [$skills].

${TeamPromptSpec.languageLock}

<example>
{
  "teamName": "auth-revamp",
  "description": "Ship the OAuth migration. The lead decomposes and integrates; workers own implementation and review. Scope is the auth module only.",
  "members": [
    {"name": "team-lead", "role": "coordinator", "model": "$dm",
     "responsibilities": "Break the request into a task list with scope and acceptance criteria, then assign by member name. Do NOT implement large changes yourself.",
     "workingMethod": "Read code and docs to understand the task, create the task list, assign teammates, then synthesize their results into one reply with files, decisions, and next steps. Escalate blockers to the user."},
    {"name": "implementer", "role": "backend developer", "model": "$dm",
     "responsibilities": "Implement assigned auth tasks within the agreed scope. Do NOT refactor unrelated code.",
     "workingMethod": "Work test-first: write a failing test, make it pass with the smallest diff, run the suite, and report changed files with reasons. Follow test-driven-development if available. Stop at agreed checkpoints."},
    {"name": "reviewer", "role": "code reviewer", "model": "$dm",
     "responsibilities": "Review the implementer's diffs for correctness and scope creep. Do NOT modify files yourself.",
     "workingMethod": "Inspect each diff against the task's acceptance criteria, list concrete issues by file and line, then approve or request changes. Escalate disagreements to the lead."}
  ],
  "skillIds": []
}
</example>

JSON schema:
{
  "teamName": string,
  "description": string,
  "members": [
    {"name": string, "role": string, "responsibilities": string, "workingMethod": string, "model": one of [$models], "effort": one of [$efforts]},
    ...
  ],
  "skillIds": subset of [$skills]
}
''';
}
