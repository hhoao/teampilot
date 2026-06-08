# Engineering-grade, mode-split team generation — Design

**Date:** 2026-06-08
**Status:** Approved (pending written-spec review)
**Area:** `client/lib/services/ai/` team-config generation

## Problem

`buildTeamConfigPrompt` ([team_config_prompt.dart](../../../client/lib/services/ai/team_config_prompt.dart)) produces a shallow team. It asks the model for only `name / role / model / effort` per member (plus `teamName / mode / skillIds` in "full" mode). The result is a roster of stubs.

The data model is far richer than what we generate. [`TeamMemberConfig`](../../../client/lib/models/team_config.dart) carries two substantive fields the prompt never touches:

- **`prompt`** → rendered as `# Responsibilities` in `role.md` (WHAT the role is).
- **`playbook`** → rendered as `# Working method` in `role.md` (HOW it operates — the SOP).

Both feed `role.md` via `MemberRoleProvision.composeMemberRoleBody` ([member_role_provision.dart:118](../../../client/lib/services/session/member_role_provision.dart#L118)). `TeamConfig.description` (team charter) is likewise never generated. And critically, [`parseTeamConfigDraft`](../../../client/lib/services/ai/team_config_draft.dart#L48) does not parse any of these — so enriching the prompt alone would be inert; the whole pipeline must grow.

The two coordination modes also genuinely differ and deserve different prompts:

- **`native`** — a single CLI's native team feature; one shared roster; no per-member CLI.
- **`mixed`** — cross-CLI teammate bus (`send_message` / `wait_for_message`); each member may run a different CLI via a per-member `cli` override.

## Goal

Replace the stub generator with two mode-specific, engineering-grade prompt builders that produce, for every team: a team **charter** (`description`), and per member a scoped **Responsibilities** block and a concrete **Working method**, with models/efforts/CLIs validly assigned. The prompts borrow the proven voice of the superpowers skills and Claude Code / opencode system prompts (Iron Law, terse imperative, `<example>` few-shot, explicit "Do NOT" boundaries).

No backward/forward compatibility constraints — clean cuts are preferred.

## Decisions (resolved during brainstorming)

1. **Mode is chosen in the dialog before generating.** The AI never decides mode; the generator dispatches to the matching builder.
2. **Always rich.** Drop the roster/full granularity toggle. Every generation is engineering-grade.
3. **Use all four quality levers:** few-shot exemplars, per-field rubric, composition rules, mode coordination context.
4. **The AI emits the team-lead too** (one member with id `team-lead`), and the parser clamps to exactly one valid lead.

## Architecture (Approach A — two builders + shared spec)

Functional style, matching the existing `buildCommitMessagePrompt` / `buildTeamConfigPrompt` idiom.

```
client/lib/services/ai/
  team_config_prompt.dart          # dispatcher buildTeamConfigPrompt({mode, description, allowed})
                                    #   + shared spec: identity framing, Iron Law, field rubric,
                                    #     voice rules, JSON-strictness contract, language lock
  team_config_prompt_native.dart   # buildNativeTeamConfigPrompt(...)  — single-CLI native team
  team_config_prompt_mixed.dart    # buildMixedTeamConfigPrompt(...)   — cross-CLI bus + per-member cli
```

The dispatcher and shared constants live in `team_config_prompt.dart`; each mode's exemplar, member shape, coordination context, and JSON schema live in its own file. Shared helpers stay deliberately small so they never become a conditional soup (the failure mode of a single data-driven template).

## Data model changes

### `TeamConfigDraft` ([team_config_draft.dart](../../../client/lib/services/ai/team_config_draft.dart))

- **Add** `final String? description;`
- **Remove** `final TeamMode? mode;` — mode is now an *input* from the dialog, not an AI output.
- Keep `members`, `teamName`, `skillIds`. `members` already carry `prompt` / `playbook` / `cli` via `TeamMemberConfig`.

### `TeamDraftAllowedOptions` — per-CLI, so mixed validates each member against its own CLI

```dart
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

class TeamDraftAllowedOptions {
  const TeamDraftAllowedOptions({required this.clis, required this.skillIds});
  final List<CliModelOptions> clis;   // native: 1 entry (team CLI). mixed: 1 per launch-supported CLI.
  final List<String> skillIds;
}
```

### Delete `TeamGenGranularity` entirely

Remove the enum and every call site (`team_config_draft.dart`, generator, prompt builders, the generate section, the UI section test, the `export` in [home_workspace_team_generate_section.dart:7](../../../client/lib/pages/home_workspace/home_workspace_team_generate_section.dart#L7)).

## Parser changes (`parseTeamConfigDraft`)

New signature: `parseTeamConfigDraft(rawJson, {required allowed, required mode, required joinedAt})`.

Per member, parse and clamp:

| Field | Source key | Clamp rule |
|-------|-----------|------------|
| name | `name` | required non-empty, else skip member |
| role | `role` | → `agentType`, free text |
| Responsibilities | `responsibilities` | → `prompt`, free text |
| Working method | `workingMethod` | → `playbook`, free text |
| cli (mixed only) | `cli` | one of `allowed.clis[].cli`; else `defaultCli`. Null in native. |
| model | `model` | one of the member's resolved CLI's `models`; else that CLI's `defaultModel` |
| effort | `effort` | one of the member's resolved CLI's `efforts`; else `''` |

Team-level: parse `teamName`, `description`, `skillIds` (subset of `allowed.skillIds`).

**Lead invariant — exactly one `team-lead`:**
1. `TeamMemberConfig.fromJson` already normalizes any `team-lead`-named id to the canonical lead id.
2. Keep the **first** member resolving to the lead id; re-slug any subsequent duplicate-lead members to ordinary worker ids (suffix-dedup) so no two members share the lead id.
3. If the model emits **no** lead, inject the `DefaultTeamRoster` lead ([default_team_roster.dart:40](../../../client/lib/models/default_team_roster.dart#L40)) at the front.

The resulting draft is always valid regardless of model output.

## The builders — content

Each builder emits a single string. Voice and structure borrow from the superpowers skills and Claude Code / opencode system prompts.

### Shared scaffold (in `team_config_prompt.dart`)

- **Identity framing:** `You are a staff-level AI team architect. Design the SMALLEST team that fully covers the task — no filler roles, no overlapping duties.`
- **Iron Law (code block):** `Output STRICT JSON only. No prose. No code fences. No commentary.`
- **Composition rules (MUST/NEVER):**
  - MUST include exactly one `team-lead` member (name `team-lead`) that coordinates and does **NOT** self-implement.
  - 2–5 members total. Every role distinct; NEVER two members with overlapping responsibilities.
  - Cover the disciplines the task implies (e.g. implement, review, research) — and nothing more.
- **Per-field rubric (the quality core), each with a verbosity bound:**
  - `responsibilities` → WHAT. Terse imperative, 1–3 sentences. **MUST end with an explicit `Do NOT …` scope boundary.**
  - `workingMethod` → HOW. Concrete SOP: ordered steps, checkpoints, the report format, and the escalation trigger. May soft-reference skills (`follow test-driven-development if available`). 2–5 sentences.
  - `description` → one-paragraph team charter: mission, scope boundary, how members collaborate.
  - `model` / `effort` → choose from the allowed values for that member's CLI.
- **Few-shot exemplar** in `<example>` tags: one complete team for the mode, as valid JSON, with Responsibilities/Working-method text written in the target voice (derived from the existing presets in [team_member_prompt_presets.dart](../../../client/lib/models/team_member_prompt_presets.dart) but richer).
- **Language lock (IMPORTANT):** `Write EVERY generated string (names, roles, responsibilities, working methods, description) in the same language as the Description above.` — overrides the English exemplar so a Chinese description yields Chinese content.
- **JSON schema block** appended last.

### Native builder adds

Single-CLI native-team context: one shared roster on `<cli>`; the lead delegates via SendMessage by member name; members do not pick a CLI. Schema has **no** `cli` field. `model` / `effort` drawn from the single allowed CLI entry.

### Mixed builder adds

Cross-CLI teammate-bus context: members coordinate ONLY via `send_message` / `wait_for_message`; the lead **never stands down**. **Each member picks a `cli` from the allowed set by role fit**, and writes a bus-aware Working method. Schema includes `cli` per member, constrained to the allowed CLI list; `model` / `effort` must come from that CLI's option set.

### Worked illustration of the quality lift

Before (today): `{"name":"Dev","role":"developer","model":"..."}`

After (mixed, abbreviated):
```json
{
  "teamName": "auth-revamp",
  "description": "Ship the OAuth migration. Lead decomposes and integrates; workers own implementation, review, and research. Scope is the auth module only.",
  "members": [
    {"name":"team-lead","role":"coordinator","cli":"claude","model":"...",
     "responsibilities":"Break the request into a task list with scope + acceptance criteria, then assign. Do NOT implement large changes yourself.",
     "workingMethod":"list_teammates → add_tasks → wait_for_message loop. Assign by member id. After workers report, synthesize files + decisions + next steps for the user. Escalate blockers to the user."},
    {"name":"implementer","role":"developer","cli":"flashskyai","model":"...",
     "responsibilities":"Implement assigned auth tasks within scope. Do NOT refactor unrelated code.",
     "workingMethod":"Test-first: write a failing test, make it pass with the smallest diff, run the suite, update_task(done) with changed files + why. Stop at agreed checkpoints."}
  ],
  "skillIds": ["..."]
}
```

## Generator & UI changes

- `TeamConfigGenerator.generate({setting, description, allowed, mode, joinedAt})` — drop `granularity`, add `mode`. Build via `buildTeamConfigPrompt(mode: ...)`. Keep the existing 2-attempt JSON-repair retry ([team_config_generator.dart:44](../../../client/lib/services/ai/team_config_generator.dart#L44)).
- **Generate section** ([home_workspace_team_generate_section.dart](../../../client/lib/pages/home_workspace/home_workspace_team_generate_section.dart)): remove the `SegmentedButton` and `_granularity`; callback becomes `onGenerate(String description)`.
- **New-team dialog** ([home_workspace_new_team_dialog.dart](../../../client/lib/pages/home_workspace/home_workspace_new_team_dialog.dart)):
  - `_onGenerate` passes the dialog's current `_mode`.
  - `_collectAllowedOptions`: native → one `CliModelOptions` for the team CLI; mixed → one per launch-supported CLI, each built from that CLI's selected app provider (fall back to its catalog default), reusing the existing `ProviderModelCapability` / `CliEffortCapability` lookups.
  - Apply draft: set `teamName` (when the field is empty), `description`, the rich `members` (with `prompt` / `playbook` / `cli`), and `skillIds`. `_mode` stays the dialog's selection — the draft no longer carries mode.
- **l10n:** remove `teamGenGranularityRoster` / `teamGenGranularityFull` from `app_en.arb` and `app_zh.arb`.

## Testing

- **Builder tests** (`team_config_prompt_test.dart`): native vs mixed each include their coordination context, composition rules, field rubric, `<example>` exemplar, language lock, and the correct schema (mixed has `cli`, native does not); neither references granularity.
- **Parser tests** (`team_config_draft_test.dart`): parses `responsibilities` / `workingMethod` / `description`; lead-invariant (zero → injected, duplicate → deduped, one → kept); mixed clamps `cli` and per-CLI `model` / `effort`; native ignores any `cli` key.
- **Generator test** (`team_config_generator_test.dart`): dispatches by mode; retry path intact.
- **UI section test** (`home_workspace_team_generate_section_test.dart`): toggle removed; `onGenerate(description)` signature.

Run before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`.

## Out of scope

- Editing the team-lead's injected coordination addendum (`MemberRoleProvision` system text) — unchanged.
- Regenerating an existing team's members — this is creation-flow only.
- Per-CLI provider selection UX in mixed mode beyond reusing the already-selected app providers.
