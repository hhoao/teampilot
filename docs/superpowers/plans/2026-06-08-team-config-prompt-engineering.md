# Engineering-grade, mode-split team generation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the shallow single team-generation prompt with two mode-specific, engineering-grade builders that produce a team charter plus per-member scoped Responsibilities and concrete Working method, fully validated.

**Architecture:** Functional builders (matching `buildCommitMessagePrompt`). A dispatcher picks a `native` or `mixed` builder; both draw on a shared spec module (identity, Iron Law, field rubric, language lock). The draft model, parser, generator, and new-team dialog grow to carry the new fields. Mode is chosen in the dialog and passed in — the AI never decides it.

**Tech Stack:** Dart / Flutter, `flutter_bloc`, the CLI registry capabilities (`ProviderModelCapability`, `CliEffortCapability`).

**Spec:** `docs/superpowers/specs/2026-06-08-team-config-prompt-engineering-design.md`

---

## ⚠️ Build-state note for executors

This is an atomic type migration. Changing `TeamDraftAllowedOptions` / `TeamConfigDraft` and the parser signature breaks every consumer until the UI is updated in **Task 4**.

- After **Tasks 1–3**, the whole-project `flutter analyze` is **expected to be RED** (the dialog still uses the old API). Do **NOT** run full `flutter analyze` as a checkpoint for Tasks 1–3.
- Each service task is independently verified by running **its own test file** — those compile only their import subtree (which is green) — e.g. `flutter test test/services/ai/team_config_draft_test.dart`.
- Full green (`flutter analyze` + full `flutter test`) is restored and verified in **Task 4** and **Task 5**.

All commands run from `client/`.

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `lib/services/ai/team_config_draft.dart` | Draft + allowed-options types, parser, lead invariant | Rewrite |
| `lib/services/ai/team_config_prompt_spec.dart` | Shared prompt scaffolding (identity, Iron Law, rubric, language lock) | Create |
| `lib/services/ai/team_config_prompt_native.dart` | Native-mode builder | Create |
| `lib/services/ai/team_config_prompt_mixed.dart` | Mixed-mode builder | Create |
| `lib/services/ai/team_config_prompt.dart` | Dispatcher | Rewrite |
| `lib/services/ai/team_config_generator.dart` | Mode-dispatched generation + retry | Modify |
| `lib/pages/home_workspace/home_workspace_team_generate_section.dart` | Description + generate button (toggle removed) | Modify |
| `lib/pages/home_workspace/home_workspace_new_team_dialog.dart` | Per-CLI allowed options, apply rich draft | Modify |
| `lib/cubits/team_cubit.dart` | `addTeam` accepts `description` + `skillIds` | Modify |
| `lib/l10n/app_en.arb`, `lib/l10n/app_zh.arb` | Remove granularity strings | Modify |
| `test/services/ai/team_config_draft_test.dart` | Parser tests | Rewrite |
| `test/services/ai/team_config_prompt_test.dart` | Builder tests | Rewrite |
| `test/services/ai/team_config_generator_test.dart` | Generator tests | Rewrite |
| `test/pages/home_workspace/home_workspace_team_generate_section_test.dart` | Section test | Rewrite |

---

## Task 1: Draft model + parser

**Files:**
- Rewrite: `lib/services/ai/team_config_draft.dart`
- Rewrite (test): `test/services/ai/team_config_draft_test.dart`

- [ ] **Step 1: Write the failing tests**

Replace the entire contents of `test/services/ai/team_config_draft_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/team_config_draft.dart';
import 'package:teampilot/utils/team_member_naming.dart';

void main() {
  const native = TeamDraftAllowedOptions(
    clis: [
      CliModelOptions(
        cli: CliTool.claude,
        models: ['sonnet', 'opus'],
        efforts: ['low', 'high'],
        defaultModel: 'sonnet',
      ),
    ],
    skillIds: ['code-review', 'testing'],
  );

  const mixed = TeamDraftAllowedOptions(
    clis: [
      CliModelOptions(
        cli: CliTool.claude,
        models: ['sonnet', 'opus'],
        efforts: ['low', 'high'],
        defaultModel: 'sonnet',
      ),
      CliModelOptions(
        cli: CliTool.codex,
        models: ['gpt-x'],
        efforts: ['medium'],
        defaultModel: 'gpt-x',
      ),
    ],
    skillIds: ['code-review'],
  );

  test('parses rich members and team fields, clamping invalid values', () {
    const json = '''
{
  "teamName": "Frontend",
  "description": "Ship the UI.",
  "members": [
    {"name": "team-lead", "role": "coordinator", "model": "opus", "effort": "high",
     "responsibilities": "Coordinate. Do NOT implement.",
     "workingMethod": "Decompose, assign, synthesize."},
    {"name": "Bad One", "role": "dev", "model": "ghost", "effort": "ultra",
     "responsibilities": "Build it.", "workingMethod": "Test first."}
  ],
  "skillIds": ["code-review", "unknown-skill"]
}
''';
    final draft = parseTeamConfigDraft(
      json,
      allowed: native,
      mode: TeamMode.native,
      joinedAt: 100,
    );

    expect(draft.teamName, 'Frontend');
    expect(draft.description, 'Ship the UI.');
    expect(draft.members, hasLength(2));
    final lead = draft.members.first;
    expect(lead.id, TeamMemberNaming.teamLeadName);
    expect(lead.model, 'opus');
    expect(lead.effort, 'high');
    expect(lead.prompt, 'Coordinate. Do NOT implement.');
    expect(lead.playbook, 'Decompose, assign, synthesize.');
    // invalid model clamps to default, invalid effort clears
    expect(draft.members[1].model, 'sonnet');
    expect(draft.members[1].effort, '');
    expect(draft.members[1].prompt, 'Build it.');
    // unknown skill dropped
    expect(draft.skillIds, ['code-review']);
  });

  test('native ignores any per-member cli', () {
    const json = '{"members":[{"name":"team-lead"},'
        '{"name":"Dev","cli":"codex","model":"sonnet"}]}';
    final draft = parseTeamConfigDraft(
      json,
      allowed: native,
      mode: TeamMode.native,
      joinedAt: 1,
    );
    expect(draft.members[1].cli, isNull);
  });

  test('mixed clamps cli and resolves model/effort against that cli', () {
    const json = '{"members":[{"name":"team-lead"},'
        '{"name":"Dev","cli":"codex","model":"gpt-x","effort":"medium"},'
        '{"name":"Ghost","cli":"opencode","model":"sonnet","effort":"low"}]}';
    final draft = parseTeamConfigDraft(
      json,
      allowed: mixed,
      mode: TeamMode.mixed,
      joinedAt: 1,
    );
    final dev = draft.members[1];
    expect(dev.cli, CliTool.codex);
    expect(dev.model, 'gpt-x');
    expect(dev.effort, 'medium');
    // unknown cli falls back to primary (claude); its model 'sonnet' is valid there
    final ghost = draft.members[2];
    expect(ghost.cli, CliTool.claude);
    expect(ghost.model, 'sonnet');
  });

  test('injects a default team-lead when none is emitted', () {
    const json = '{"members":[{"name":"Dev","role":"dev"}]}';
    final draft = parseTeamConfigDraft(
      json,
      allowed: native,
      mode: TeamMode.native,
      joinedAt: 1,
    );
    expect(draft.members.first.id, TeamMemberNaming.teamLeadName);
    expect(draft.members, hasLength(2));
  });

  test('keeps the first lead and demotes duplicate leads to workers', () {
    const json = '{"members":[{"name":"team-lead","role":"a"},'
        '{"name":"team-lead","role":"b"}]}';
    final draft = parseTeamConfigDraft(
      json,
      allowed: native,
      mode: TeamMode.native,
      joinedAt: 1,
    );
    final leads = draft.members
        .where((m) => m.id == TeamMemberNaming.teamLeadName)
        .toList();
    expect(leads, hasLength(1));
    expect(draft.members, hasLength(2));
    expect(draft.members[1].id, isNot(TeamMemberNaming.teamLeadName));
  });

  test('skips members without a name', () {
    const json = '{"members":[{"name":"team-lead"},{"role":"dev"},'
        '{"name":"Ok","role":"dev"}]}';
    final draft = parseTeamConfigDraft(
      json,
      allowed: native,
      mode: TeamMode.native,
      joinedAt: 1,
    );
    expect(draft.members.map((m) => m.name), contains('Ok'));
    expect(draft.members, hasLength(2)); // team-lead + Ok
  });

  test('throws TeamDraftFormatException on non-JSON', () {
    expect(
      () => parseTeamConfigDraft(
        'not json',
        allowed: native,
        mode: TeamMode.native,
        joinedAt: 1,
      ),
      throwsA(isA<TeamDraftFormatException>()),
    );
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/services/ai/team_config_draft_test.dart`
Expected: FAIL to compile (`CliModelOptions` undefined, `TeamDraftAllowedOptions` no `clis`, `parseTeamConfigDraft` no `mode`).

- [ ] **Step 3: Rewrite the draft model + parser**

Replace the entire contents of `lib/services/ai/team_config_draft.dart`:

```dart
import 'dart:convert';

import '../../models/default_team_roster.dart';
import '../../models/team_config.dart';
import '../../utils/team_member_naming.dart';

class TeamDraftFormatException implements Exception {
  TeamDraftFormatException(this.message);
  final String message;
  @override
  String toString() => 'TeamDraftFormatException: $message';
}

/// Legal model/effort values for one CLI, used to clamp parsed members.
class CliModelOptions {
  const CliModelOptions({
    required this.cli,
    required this.models,
    required this.efforts,
    required this.defaultModel,
  });

  final CliTool cli;
  final List<String> models;
  final List<String> efforts;
  final String defaultModel;
}

/// Legal values the AI must choose from; used to clamp parsed output.
///
/// native: [clis] holds one entry (the team CLI).
/// mixed: one entry per launch-supported CLI.
class TeamDraftAllowedOptions {
  const TeamDraftAllowedOptions({required this.clis, required this.skillIds});

  final List<CliModelOptions> clis;
  final List<String> skillIds;

  CliModelOptions get primary => clis.first;

  CliModelOptions optionsFor(CliTool cli) =>
      clis.firstWhere((o) => o.cli == cli, orElse: () => primary);
}

/// A validated, legal team draft produced from AI output.
class TeamConfigDraft {
  const TeamConfigDraft({
    required this.members,
    this.teamName,
    this.description,
    this.skillIds = const [],
  });

  final List<TeamMemberConfig> members;
  final String? teamName;
  final String? description;
  final List<String> skillIds;
}

/// Parses [rawJson] into a clamped [TeamConfigDraft]. Illegal models fall back
/// to the member CLI's default; illegal efforts are cleared; unknown skill ids
/// and (in mixed) unknown clis are dropped to the primary CLI; nameless members
/// are skipped. The result always contains exactly one `team-lead`.
TeamConfigDraft parseTeamConfigDraft(
  String rawJson, {
  required TeamDraftAllowedOptions allowed,
  required TeamMode mode,
  required int joinedAt,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(_stripFences(rawJson));
  } on FormatException catch (e) {
    throw TeamDraftFormatException('Output was not valid JSON: ${e.message}');
  }
  if (decoded is! Map) {
    throw TeamDraftFormatException('Output JSON was not an object.');
  }

  final mixed = mode == TeamMode.mixed;
  final rawMembers = decoded['members'];
  final parsed = <TeamMemberConfig>[];
  if (rawMembers is List) {
    for (final raw in rawMembers) {
      if (raw is! Map) continue;
      final name = (raw['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final role = (raw['role'] as String? ?? '').trim();
      final responsibilities = (raw['responsibilities'] as String? ?? '').trim();
      final workingMethod = (raw['workingMethod'] as String? ?? '').trim();

      CliTool? memberCli;
      if (mixed) {
        final parsedCli = CliTool.tryParse(raw['cli'] as String?);
        memberCli = (parsedCli != null &&
                allowed.clis.any((o) => o.cli == parsedCli))
            ? parsedCli
            : allowed.primary.cli;
      }
      final opts = allowed.optionsFor(memberCli ?? allowed.primary.cli);
      final rawModel = (raw['model'] as String? ?? '').trim();
      final model =
          opts.models.contains(rawModel) ? rawModel : opts.defaultModel;
      final rawEffort = (raw['effort'] as String? ?? '').trim();
      final effort = opts.efforts.contains(rawEffort) ? rawEffort : '';

      parsed.add(
        TeamMemberConfig(
          id: TeamMemberNaming.slugMemberName(name),
          name: name,
          agentType: role,
          prompt: responsibilities,
          playbook: workingMethod,
          model: model,
          effort: effort,
          cli: memberCli,
          joinedAt: joinedAt,
        ),
      );
    }
  }

  final members = _enforceSingleLead(parsed, joinedAt: joinedAt);

  final teamName = (decoded['teamName'] as String? ?? '').trim();
  final description = (decoded['description'] as String? ?? '').trim();
  final rawSkills = decoded['skillIds'];
  final skillIds = <String>[];
  if (rawSkills is List) {
    for (final s in rawSkills) {
      final id = s.toString().trim();
      if (allowed.skillIds.contains(id)) skillIds.add(id);
    }
  }

  return TeamConfigDraft(
    members: members,
    teamName: teamName.isEmpty ? null : teamName,
    description: description.isEmpty ? null : description,
    skillIds: skillIds,
  );
}

/// Guarantees exactly one `team-lead`: keeps the first lead the model emitted,
/// re-slugs duplicate leads to unique worker ids, and injects the default lead
/// when none was produced.
List<TeamMemberConfig> _enforceSingleLead(
  List<TeamMemberConfig> members, {
  required int joinedAt,
}) {
  final result = <TeamMemberConfig>[];
  final usedIds = <String>{};
  var leadSeen = false;
  for (final m in members) {
    if (TeamMemberNaming.isTeamLead(m)) {
      if (!leadSeen) {
        leadSeen = true;
        usedIds.add(m.id);
        result.add(m);
        continue;
      }
      final base = TeamMemberNaming.slugMemberName(m.name);
      final demoted = base == TeamMemberNaming.teamLeadName
          ? TeamMemberNaming.defaultWorkerName
          : base;
      final id = _uniqueMemberId(demoted, usedIds);
      usedIds.add(id);
      result.add(m.copyWith(id: id));
    } else {
      final id = _uniqueMemberId(m.id, usedIds);
      usedIds.add(id);
      result.add(id == m.id ? m : m.copyWith(id: id));
    }
  }
  if (!leadSeen) {
    final lead = DefaultTeamRoster.bootstrap(joinedAt: joinedAt).first;
    result.insert(0, lead);
  }
  return result;
}

String _uniqueMemberId(String base, Set<String> used) {
  final b = base.isEmpty ? TeamMemberNaming.defaultWorkerName : base;
  if (!used.contains(b)) return b;
  var n = 2;
  while (used.contains('$b-$n')) {
    n++;
  }
  return '$b-$n';
}

/// Removes a surrounding ```json ... ``` fence if present.
String _stripFences(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    final nl = text.indexOf('\n');
    if (nl != -1) text = text.substring(nl + 1);
    final end = text.lastIndexOf('```');
    if (end != -1) text = text.substring(0, end);
  }
  return text.trim();
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/services/ai/team_config_draft_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/ai/team_config_draft.dart test/services/ai/team_config_draft_test.dart
git commit -m "feat(ai): rich team draft model + mode-aware parser with lead invariant"
```

---

## Task 2: Shared spec + native/mixed builders + dispatcher

**Files:**
- Create: `lib/services/ai/team_config_prompt_spec.dart`
- Create: `lib/services/ai/team_config_prompt_native.dart`
- Create: `lib/services/ai/team_config_prompt_mixed.dart`
- Rewrite: `lib/services/ai/team_config_prompt.dart`
- Rewrite (test): `test/services/ai/team_config_prompt_test.dart`

- [ ] **Step 1: Write the failing tests**

Replace the entire contents of `test/services/ai/team_config_prompt_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/team_config_draft.dart';
import 'package:teampilot/services/ai/team_config_prompt.dart';

void main() {
  const native = TeamDraftAllowedOptions(
    clis: [
      CliModelOptions(
        cli: CliTool.claude,
        models: ['sonnet', 'opus'],
        efforts: ['low', 'high'],
        defaultModel: 'sonnet',
      ),
    ],
    skillIds: ['code-review'],
  );

  const mixed = TeamDraftAllowedOptions(
    clis: [
      CliModelOptions(
        cli: CliTool.claude,
        models: ['sonnet'],
        efforts: ['high'],
        defaultModel: 'sonnet',
      ),
      CliModelOptions(
        cli: CliTool.codex,
        models: ['gpt-x'],
        efforts: ['medium'],
        defaultModel: 'gpt-x',
      ),
    ],
    skillIds: ['code-review'],
  );

  test('native prompt: rubric, schema fields, single cli, no cli field', () {
    final p = buildTeamConfigPrompt(
      mode: TeamMode.native,
      description: 'Flutter frontend team',
      allowed: native,
    );
    expect(p, contains('Flutter frontend team'));
    expect(p, contains('NATIVE team'));
    expect(p, contains('"responsibilities"'));
    expect(p, contains('"workingMethod"'));
    expect(p, contains('"description"'));
    expect(p, contains('Do NOT'));
    expect(p, contains('exactly one member named "team-lead"'));
    expect(p, contains('sonnet'));
    expect(p, contains('code-review'));
    // native must not ask members to choose a CLI
    expect(p.contains('"cli"'), isFalse);
  });

  test('mixed prompt: bus context, per-cli model lists, cli field', () {
    final p = buildTeamConfigPrompt(
      mode: TeamMode.mixed,
      description: 'cross-cli team',
      allowed: mixed,
    );
    expect(p, contains('MIXED team'));
    expect(p, contains('teammate bus'));
    expect(p, contains('"cli"'));
    expect(p, contains('claude'));
    expect(p, contains('codex'));
    expect(p, contains('gpt-x'));
  });

  test('language lock is present in both modes', () {
    final n = buildTeamConfigPrompt(
      mode: TeamMode.native,
      description: 'x',
      allowed: native,
    );
    final m = buildTeamConfigPrompt(
      mode: TeamMode.mixed,
      description: 'x',
      allowed: mixed,
    );
    expect(n, contains('SAME language as the Description'));
    expect(m, contains('SAME language as the Description'));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/services/ai/team_config_prompt_test.dart`
Expected: FAIL to compile (`buildTeamConfigPrompt` signature mismatch — no `mode`).

- [ ] **Step 3: Create the shared spec module**

Create `lib/services/ai/team_config_prompt_spec.dart`:

```dart
/// Shared scaffolding for the native/mixed team prompt builders: identity, the
/// strict-JSON Iron Law, the per-field rubric, composition rules, and the
/// language lock. Voice borrows from the superpowers skills and Claude Code /
/// opencode system prompts (terse imperative, explicit "Do NOT" boundaries).
abstract final class TeamPromptSpec {
  static const identity =
      'You are a staff-level AI team architect. Design the SMALLEST team that '
      'fully covers the task — no filler roles, no overlapping duties.';

  static const ironLaw = '''
=== OUTPUT CONTRACT (MANDATORY) ===
Output STRICT JSON only. No prose. No code fences. No commentary.
Emit exactly one JSON object matching the schema at the end.''';

  static const compositionRules = '''
Team composition rules:
- MUST include exactly one member named "team-lead" that coordinates and does NOT implement large changes itself.
- 2-5 members total. Every role MUST be distinct; NEVER give two members overlapping responsibilities.
- Cover the disciplines the task implies (e.g. implement, review, research) — and nothing more.''';

  static const fieldRubric = '''
Per-field rubric (follow exactly):
- "role": a concise noun phrase (e.g. "backend developer").
- "responsibilities" (WHAT): terse imperative, 1-3 sentences. MUST end with an explicit "Do NOT ..." scope boundary.
- "workingMethod" (HOW): a concrete SOP — ordered steps, checkpoints, the report format, and the escalation trigger. May soft-reference skills (e.g. "follow test-driven-development if available"). 2-5 sentences.
- "description" (team-level): one paragraph — mission, scope boundary, and how members collaborate.
- "model"/"effort": choose only from the allowed values listed for that member.''';

  static const languageLock =
      'IMPORTANT: Write EVERY generated string (names, roles, responsibilities, '
      'workingMethod, description) in the SAME language as the Description above.';
}
```

- [ ] **Step 4: Create the native builder**

Create `lib/services/ai/team_config_prompt_native.dart`:

```dart
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
```

- [ ] **Step 5: Create the mixed builder**

Create `lib/services/ai/team_config_prompt_mixed.dart`:

```dart
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
    {"name": "implementer", "role": "backend developer", "cli": "$exCli", "model": "$exModel",
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
```

- [ ] **Step 6: Rewrite the dispatcher**

Replace the entire contents of `lib/services/ai/team_config_prompt.dart`:

```dart
import '../../models/team_config.dart';
import 'team_config_draft.dart';
import 'team_config_prompt_mixed.dart';
import 'team_config_prompt_native.dart';

/// Dispatches to the mode-specific engineering-grade team prompt builder.
///
/// The user [description] is interpolated unescaped. Acceptable: it is a
/// local-only desktop feature, the user authored the text, the draft is shown
/// for review before a team is created, and the parsed output is additionally
/// clamped to legal models/efforts/skills/clis by [parseTeamConfigDraft].
String buildTeamConfigPrompt({
  required TeamMode mode,
  required String description,
  required TeamDraftAllowedOptions allowed,
}) {
  return switch (mode) {
    TeamMode.native =>
      buildNativeTeamConfigPrompt(description: description, allowed: allowed),
    TeamMode.mixed =>
      buildMixedTeamConfigPrompt(description: description, allowed: allowed),
  };
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/services/ai/team_config_prompt_test.dart`
Expected: PASS (all tests).

- [ ] **Step 8: Commit**

```bash
git add lib/services/ai/team_config_prompt_spec.dart lib/services/ai/team_config_prompt_native.dart lib/services/ai/team_config_prompt_mixed.dart lib/services/ai/team_config_prompt.dart test/services/ai/team_config_prompt_test.dart
git commit -m "feat(ai): mode-split engineering-grade team prompt builders"
```

---

## Task 3: Generator mode dispatch

**Files:**
- Modify: `lib/services/ai/team_config_generator.dart`
- Rewrite (test): `test/services/ai/team_config_generator_test.dart`

- [ ] **Step 1: Write the failing tests**

Replace the entire contents of `test/services/ai/team_config_generator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/team_config_draft.dart';
import 'package:teampilot/services/ai/team_config_generator.dart';
import 'package:teampilot/utils/team_member_naming.dart';

const _setting = AiFeatureSetting(
  cli: CliTool.claude,
  providerId: 'p',
  model: 'm',
);

const _allowed = TeamDraftAllowedOptions(
  clis: [
    CliModelOptions(
      cli: CliTool.claude,
      models: ['sonnet'],
      efforts: ['high'],
      defaultModel: 'sonnet',
    ),
  ],
  skillIds: [],
);

void main() {
  test('returns a parsed draft on first success', () async {
    String? seenPrompt;
    final gen = TeamConfigGenerator(
      runHeadless: ({required setting, required prompt, required expectJson}) async {
        seenPrompt = prompt;
        return '{"members":[{"name":"team-lead"},'
            '{"name":"Dev","role":"dev","model":"sonnet"}]}';
      },
    );

    final draft = await gen.generate(
      setting: _setting,
      description: 'team',
      allowed: _allowed,
      mode: TeamMode.native,
      joinedAt: 1,
    );

    expect(seenPrompt, contains('NATIVE team'));
    expect(draft.members.first.id, TeamMemberNaming.teamLeadName);
    expect(draft.members.map((m) => m.name), contains('Dev'));
  });

  test('mixed mode builds the mixed prompt', () async {
    String? seenPrompt;
    final gen = TeamConfigGenerator(
      runHeadless: ({required setting, required prompt, required expectJson}) async {
        seenPrompt = prompt;
        return '{"members":[{"name":"team-lead"}]}';
      },
    );
    await gen.generate(
      setting: _setting,
      description: 'team',
      allowed: _allowed,
      mode: TeamMode.mixed,
      joinedAt: 1,
    );
    expect(seenPrompt, contains('MIXED team'));
  });

  test('retries once on bad JSON then succeeds', () async {
    var calls = 0;
    final gen = TeamConfigGenerator(
      runHeadless: ({required setting, required prompt, required expectJson}) async {
        calls++;
        return calls == 1
            ? 'garbage'
            : '{"members":[{"name":"team-lead"}]}';
      },
    );

    final draft = await gen.generate(
      setting: _setting,
      description: 'team',
      allowed: _allowed,
      mode: TeamMode.native,
      joinedAt: 1,
    );

    expect(calls, 2);
    expect(draft.members, isNotEmpty);
  });

  test('throws after two bad JSON attempts', () async {
    final gen = TeamConfigGenerator(
      runHeadless: ({required setting, required prompt, required expectJson}) async =>
          'still garbage',
    );

    expect(
      () => gen.generate(
        setting: _setting,
        description: 'team',
        allowed: _allowed,
        mode: TeamMode.native,
        joinedAt: 1,
      ),
      throwsA(isA<TeamDraftFormatException>()),
    );
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/services/ai/team_config_generator_test.dart`
Expected: FAIL to compile (`generate` has no `mode`; still has `granularity`).

- [ ] **Step 3: Update the generator**

In `lib/services/ai/team_config_generator.dart`, add the `team_config.dart` import near the top (after the existing imports):

```dart
import '../../models/ai_feature_setting.dart';
import '../../models/team_config.dart';
import 'headless_ai_service.dart' show HeadlessAiService;
import 'team_config_draft.dart';
import 'team_config_prompt.dart';
```

Then replace the entire `generate` method body with:

```dart
  Future<TeamConfigDraft> generate({
    required AiFeatureSetting setting,
    required String description,
    required TeamDraftAllowedOptions allowed,
    required TeamMode mode,
    required int joinedAt,
  }) async {
    final basePrompt = buildTeamConfigPrompt(
      mode: mode,
      description: description,
      allowed: allowed,
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
        return parseTeamConfigDraft(
          text,
          allowed: allowed,
          mode: mode,
          joinedAt: joinedAt,
        );
      } on TeamDraftFormatException {
        if (attempt == 1) rethrow;
      }
    }
    throw TeamDraftFormatException('Failed to generate a valid team draft.');
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/services/ai/team_config_generator_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/ai/team_config_generator.dart test/services/ai/team_config_generator_test.dart
git commit -m "feat(ai): dispatch team generation by mode"
```

---

## Task 4: UI migration (restores full green)

**Files:**
- Modify: `lib/cubits/team_cubit.dart:264` (`addTeam`)
- Modify: `lib/pages/home_workspace/home_workspace_team_generate_section.dart`
- Modify: `lib/pages/home_workspace/home_workspace_new_team_dialog.dart`
- Rewrite (test): `test/pages/home_workspace/home_workspace_team_generate_section_test.dart`

- [ ] **Step 1: Write the failing section test**

Replace the entire contents of `test/pages/home_workspace/home_workspace_team_generate_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_team_generate_section.dart';

void main() {
  testWidgets('renders description field and generate button, no toggle',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: HomeWorkspaceTeamGenerateSection(
            cli: CliTool.claude,
            providerId: 'p',
            generating: false,
            onGenerate: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('team-gen-description')), findsOneWidget);
    expect(find.byKey(const ValueKey('team-gen-button')), findsOneWidget);
    expect(find.text('Members only'), findsNothing);
  });

  testWidgets('generate button reports the description', (tester) async {
    String? gotDescription;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: HomeWorkspaceTeamGenerateSection(
            cli: CliTool.claude,
            providerId: 'p',
            generating: false,
            onGenerate: (desc) => gotDescription = desc,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('team-gen-description')),
      'My team',
    );
    await tester.tap(find.byKey(const ValueKey('team-gen-button')));
    await tester.pump();

    expect(gotDescription, 'My team');
  });
}
```

- [ ] **Step 2: Run the section test to verify it fails**

Run: `flutter test test/pages/home_workspace/home_workspace_team_generate_section_test.dart`
Expected: FAIL to compile (`onGenerate` still takes two args; `TeamGenGranularity` referenced).

- [ ] **Step 3: Simplify the generate section**

In `lib/services/ai/team_config_draft.dart` there is no longer a `TeamGenGranularity` (removed in Task 1), so the section must drop it. Replace the entire contents of `lib/pages/home_workspace/home_workspace_team_generate_section.dart`:

```dart
import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';

typedef TeamGenerateCallback = void Function(String description);

/// "Generate with AI" block inside the new-team dialog: a description field and
/// a generate button. Stateless about the result; the dialog owns generation,
/// the mode selection, and draft application.
class HomeWorkspaceTeamGenerateSection extends StatefulWidget {
  const HomeWorkspaceTeamGenerateSection({
    required this.cli,
    required this.providerId,
    required this.generating,
    required this.onGenerate,
    super.key,
  });

  final CliTool cli;
  final String providerId;
  final bool generating;
  final TeamGenerateCallback onGenerate;

  @override
  State<HomeWorkspaceTeamGenerateSection> createState() =>
      _HomeWorkspaceTeamGenerateSectionState();
}

class _HomeWorkspaceTeamGenerateSectionState
    extends State<HomeWorkspaceTeamGenerateSection> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.teamGenTitle,
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('team-gen-description'),
          controller: _controller,
          minLines: 2,
          maxLines: 4,
          enabled: !widget.generating,
          decoration: InputDecoration(
            hintText: l10n.teamGenDescriptionHint,
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const ValueKey('team-gen-button'),
          onPressed: widget.generating
              ? null
              : () => widget.onGenerate(_controller.text.trim()),
          icon: widget.generating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome_outlined, size: 16),
          label: Text(l10n.teamGenButton),
        ),
      ],
    );
  }
}
```

Note: the `export ... show TeamGenGranularity` line is intentionally removed.

- [ ] **Step 4: Add `description` + `skillIds` to `addTeam`**

In `lib/cubits/team_cubit.dart`, change the `addTeam` signature (line ~264) and the `TeamConfig` it builds. Replace the signature block:

```dart
  Future<bool> addTeam(
    String name, {
    CliTool cli = CliTool.flashskyai,
    TeamMode teamMode = TeamMode.native,
    Map<String, String> providerIdsByTool = const {},
    List<TeamMemberConfig>? members,
    String description = '',
    List<String> skillIds = const [],
  }) async {
```

And in the same method, replace the `TeamConfig(` constructor call with:

```dart
    final team = TeamConfig(
      id: teamId,
      name: trimmed,
      description: description.trim(),
      cli: cli,
      teamMode: teamMode,
      providerIdsByTool: providerIdsByTool,
      skillIds: skillIds,
      createdAt: now,
      members: members ?? TeamMemberNaming.defaultRoster(joinedAt: now),
    );
```

- [ ] **Step 5: Migrate the dialog — result record + addTeam call**

In `lib/pages/home_workspace/home_workspace_new_team_dialog.dart`, update the result record type and the `addTeam` call in `showHomeWorkspaceNewTeamDialog`. Replace the `showDialog<...>` type parameter and the `addTeam` call:

```dart
  final result =
      await showDialog<
        ({
          String name,
          TeamMode mode,
          CliTool cli,
          Map<String, String> providerIdsByTool,
          List<TeamMemberConfig>? members,
          String description,
          List<String> skillIds,
        })
      >(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (_) => const HomeWorkspaceNewTeamDialog(),
      );
  if (result == null || !context.mounted) return;
  await teamCubit.addTeam(
    result.name,
    cli: result.cli,
    teamMode: result.mode,
    providerIdsByTool: result.providerIdsByTool,
    description: result.description,
    skillIds: result.skillIds,
    members: (result.members != null && result.members!.isNotEmpty)
        ? result.members
        : DefaultTeamRoster.localized(
            l10n,
            joinedAt: DateTime.now().millisecondsSinceEpoch,
          ),
  );
```

- [ ] **Step 6: Migrate the dialog — `_submit` populates the new fields**

In the same file, replace the `_submit` method:

```dart
  void _submit() {
    final name = _teamNameForSubmit().trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop((
      name: name,
      mode: _mode,
      cli: _cli,
      providerIdsByTool: _providerIdsByToolForSubmit(),
      members: _draft?.members,
      description: _draft?.description?.trim() ?? '',
      skillIds: _draft?.skillIds ?? const <String>[],
    ));
  }
```

- [ ] **Step 7: Migrate the dialog — per-CLI allowed options**

In the same file, replace the entire `_collectAllowedOptions` method with a per-CLI helper plus a mode-aware collector:

```dart
  CliModelOptions _cliModelOptions(
    CliTool cli, {
    String? providerIdOverride,
    String? preferModel,
  }) {
    final registry = CliToolRegistryScope.of(context);
    final appProviders = context.read<AppProviderCubit>().state;
    final catalogCli = _providerCatalogCli(cli) ?? cli;
    final wantedId = (providerIdOverride ?? '').trim();
    final provider = appProviders
        .providersFor(catalogCli)
        .where((p) => wantedId.isEmpty || p.id == wantedId)
        .firstOrNull;
    final modelCap = registry.capability<ProviderModelCapability>(catalogCli);
    final effortCap = registry.capability<CliEffortCapability>(catalogCli);
    final models =
        modelCap?.modelCandidates(
          provider: provider,
          providerId: provider?.id ?? wantedId,
          currentModel: preferModel ?? '',
        ) ??
        const <String>[];
    final defaultModel =
        modelCap?.defaultModel(
          provider: provider,
          providerId: provider?.id ?? wantedId,
        ) ??
        (models.isNotEmpty ? models.first : '');
    final efforts =
        effortCap?.effortCandidates(model: defaultModel, provider: provider) ??
        const <String>[];
    return CliModelOptions(
      cli: cli,
      models: models,
      efforts: efforts,
      defaultModel: defaultModel,
    );
  }

  TeamDraftAllowedOptions _collectAllowedOptions({
    required TeamMode mode,
    AiFeatureSetting? aiSetting,
  }) {
    final registry = CliToolRegistryScope.of(context);
    if (mode == TeamMode.mixed) {
      final clis = [
        for (final def in registry.launchable) _cliModelOptions(def.id),
      ];
      return TeamDraftAllowedOptions(
        clis: clis.isEmpty
            ? [_cliModelOptions(aiSetting?.cli ?? _cli)]
            : clis,
        skillIds: const [],
      );
    }
    final cli = aiSetting?.cli ?? _cli;
    return TeamDraftAllowedOptions(
      clis: [
        _cliModelOptions(
          cli,
          providerIdOverride: aiSetting?.providerId ?? _providerId,
          preferModel: aiSetting?.model,
        ),
      ],
      skillIds: const [],
    );
  }
```

- [ ] **Step 8: Migrate the dialog — `_onGenerate` passes mode, drops granularity**

In the same file, update `_onGenerate`'s signature and body. Change the signature line to `Future<void> _onGenerate(String description) async {`, then replace the `allowed` line, the `generate(...)` call, and the post-generate `setState` block:

```dart
    final allowed = _collectAllowedOptions(mode: _mode, aiSetting: setting);
    setState(() => _generating = true);
    try {
      final draft = await TeamConfigGenerator().generate(
        setting: setting,
        description: description,
        allowed: allowed,
        mode: _mode,
        joinedAt: DateTime.now().millisecondsSinceEpoch,
      );
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _cli = setting.cli;
        _providerId = setting.providerId;
      });
      _syncCanCreate();
```

(The `if (draft.mode != null) _mode = draft.mode!;` line is removed — the draft no longer carries mode; `_mode` stays the user's dialog selection. Leave the surrounding `ScaffoldMessenger`, `catch`, and `finally` blocks untouched.)

- [ ] **Step 9: Verify the `onGenerate` wiring site**

The `HomeWorkspaceTeamGenerateSection` is constructed somewhere in this file's `build`. Find `onGenerate:` and confirm it is `onGenerate: _onGenerate,` (a direct tear-off). If it is written as `onGenerate: (desc, gran) => ...`, change it to `onGenerate: _onGenerate,`.

Run: `grep -n "onGenerate" lib/pages/home_workspace/home_workspace_new_team_dialog.dart`
Expected: a single `onGenerate: _onGenerate,` reference. Fix if it still passes two params.

- [ ] **Step 10: Run analyze + targeted tests (full green restored)**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/ai lib/pages/home_workspace lib/cubits/team_cubit.dart`
Expected: No errors.

Run: `flutter test test/pages/home_workspace/home_workspace_team_generate_section_test.dart test/services/ai`
Expected: PASS (all tests).

- [ ] **Step 11: Commit**

```bash
git add lib/cubits/team_cubit.dart lib/pages/home_workspace/home_workspace_team_generate_section.dart lib/pages/home_workspace/home_workspace_new_team_dialog.dart test/pages/home_workspace/home_workspace_team_generate_section_test.dart
git commit -m "feat(ai): wire mode-split generation + rich draft into the new-team dialog"
```

---

## Task 5: l10n cleanup + full verification

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_zh.arb`

- [ ] **Step 1: Remove the now-unused granularity strings**

In both `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb`, delete the `teamGenGranularityRoster` and `teamGenGranularityFull` keys (and their `@`-metadata entries if present). Keep `teamGenTitle`, `teamGenDescriptionHint`, `teamGenButton`, `teamGenNoProvider`, `teamGenApplied`, `teamGenFailed`.

First confirm nothing else references them:

Run: `grep -rn "teamGenGranularity" lib`
Expected: no matches after deletion (the generated `app_localizations*.dart` is regenerated by the next step).

- [ ] **Step 2: Regenerate localizations**

Run: `flutter pub get`
Expected: completes; `app_localizations*.dart` regenerated without the removed getters.

- [ ] **Step 3: Full analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No errors.

- [ ] **Step 4: Full test suite**

Run: `flutter test --exclude-tags integration`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_zh.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_zh.dart
git commit -m "chore(l10n): drop team-generation granularity strings"
```

---

## Self-Review

**Spec coverage:**
- Data model (draft `description`, drop `mode`; per-CLI `TeamDraftAllowedOptions`/`CliModelOptions`; delete `TeamGenGranularity`) → Task 1.
- Parser (mode param; parse `responsibilities`/`workingMethod`/`description`/`cli`; per-CLI clamp; one-lead invariant) → Task 1.
- Two builders + shared spec + dispatcher (identity, Iron Law, rubric, composition rules, mode coordination context, `<example>` few-shot, language lock, mode-specific schemas) → Task 2.
- Generator mode dispatch + retry → Task 3.
- UI: drop toggle, per-CLI options, apply `teamName`/`description`/rich members/`skillIds`, mode stays dialog's → Task 4.
- l10n cleanup → Task 5.

**Placeholder scan:** No TBD/TODO; every code step has complete content.

**Type consistency:** `TeamDraftAllowedOptions({clis, skillIds})`, `CliModelOptions({cli, models, efforts, defaultModel})`, `parseTeamConfigDraft(raw, {allowed, mode, joinedAt})`, `buildTeamConfigPrompt({mode, description, allowed})`, `generate({setting, description, allowed, mode, joinedAt})`, `onGenerate(String)` — used consistently across tasks and tests. Member JSON keys `responsibilities`→`prompt`, `workingMethod`→`playbook` are consistent between builders, parser, and tests.

**Known intentional red window:** whole-project `flutter analyze` is red between Task 1 and Task 4; each service task is verified by its own test file. Documented at the top.
