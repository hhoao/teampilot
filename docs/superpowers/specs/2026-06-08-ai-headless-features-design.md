# AI Headless Features: Commit Message + Team Config Generation

**Date:** 2026-06-08
**Status:** Design approved, pending spec review

## Summary

Add two AI-assisted features to TeamPilot:

1. **AI commit message generation** — in the existing source-control panel, generate a
   commit message draft from the staged diff.
2. **AI team-config generation** — in the new-team flow, generate a team roster (or full
   team draft) from a natural-language description.

Both features share one new subsystem: a **headless one-shot AI invocation** (prompt in →
text out), implemented by reusing the already-installed CLIs in their non-interactive modes.
Each feature has its own configurable `(CLI provider, model, effort)`, stored globally.

## Goals

- Reuse installed CLIs' headless modes (no separate API keys, no new auth path).
- Per-feature configuration of CLI provider / model / effort, via the existing
  registry-driven picker widgets.
- Constrain AI output to valid options so generated configs are always legal.
- AI output is always a reviewable **draft** — it never auto-commits or auto-creates.

## Non-goals (v1)

- Direct provider HTTP API calls (chosen against; CLI headless only).
- Commit messages in languages other than English (fixed English for v1).
- PTY-scrape based invocation.

## Decisions (from brainstorming)

| Question | Decision |
|----------|----------|
| Invocation mechanism | Reuse installed CLIs' **headless mode** |
| Team-gen granularity | Support **both** roster-only and full-team draft; **configurable** via a toggle |
| Config location | New **"AI Features"** section in the global settings page, persisted in `AppSettings` (SharedPreferences) |
| CLI coverage (v1) | claude (`claude -p`), flashskyai (non-interactive), codex (`codex exec`), cursor (`cursor-agent -p`), opencode (`opencode run`) |
| Architecture | **Approach A** — a registry capability `HeadlessRunCapability`, one impl per CLI, behind a thin `HeadlessAiService` |

## Existing code reused

- Provider/model picker: `widgets/app_provider/provider_model_picker_field.dart`
- Effort picker: `widgets/app_provider/cli_effort_picker_field.dart`
- Effort resolution: `services/cli/registry/capabilities/cli_effort_capability.dart`
  (`resolveLaunchEffort`: member → team → provider → default)
- Model catalog / candidates: `services/cli/registry/capabilities/provider_model_capability.dart`
- CLI registry + capability pattern: `services/cli/registry/cli_tool_registry.dart`,
  `services/cli/registry/tools/*_cli_tool.dart`
- Process injection pattern: `services/git/git_service.dart`,
  `services/skill/skill_repo_git_service.dart` (`ProcessRunner`, `CliToolLocator`)
- Git source-control panel: `widgets/git/git_source_control_panel.dart`, `cubits/git_cubit.dart`
  (already has commit `TextField`, `setCommitMessage`, `commit()`)
- Git ops: `services/git/git_service.dart` (`diff`, `stage`, `commit`, …)
- Team creation: `pages/home_workspace/home_workspace_new_team_dialog.dart`,
  `cubits/team_cubit.dart` (`addTeam`), `models/team_config.dart`, `DefaultTeamRoster`
- Settings: `repositories/app_settings_repository.dart` (SharedPreferences JSON blob)
- l10n: `lib/l10n/app_en.arb`, `lib/l10n/app_zh.arb`

---

## Section 1 — Shared subsystem: `HeadlessRunCapability` + `HeadlessAiService`

### 1a. Registry capability

`services/cli/registry/capabilities/headless_run_capability.dart`

```dart
abstract class HeadlessRunCapability {
  /// Whether this CLI supports a one-shot headless call.
  bool get isSupported;

  /// Build the executable + args + env for a one-shot call.
  /// ctx carries model / effort / configDir / workingDirectory / expectJson.
  HeadlessInvocation buildInvocation(HeadlessRunContext ctx);

  /// Extract the model's final text from process stdout
  /// (stripping each CLI's wrapper / JSON envelope).
  String extractText(ProcessRunResult result);
}
```

- `HeadlessInvocation` = `{ executable, args, environment }`. `environment` carries the
  isolated `CONFIG_DIR` / `*_CONFIG_DIR` (same isolation approach as PTY launch).
- One implementation per CLI, registered on the corresponding `*CliTool` definition,
  alongside `LaunchArgsCapability`:
  - **claude**: `claude -p <prompt> --model <m> --output-format json`; `extractText` reads
    the JSON `result` field. Effort written to a temp `CONFIG_DIR` settings.json (reuse
    `ClaudeConfigProfileCapability` approach).
  - **codex**: `codex exec --model <m> <prompt>`; `extractText` takes the final stdout segment.
  - **flashskyai / cursor / opencode**: respective non-interactive entrypoints — verify exact
    flags against each CLI's `--help` during implementation.
- A CLI whose headless entry is unknown/unsupported returns `isSupported == false`; callers
  surface a clear "not supported for this CLI" message.

### 1b. Thin service layer

`services/ai/headless_ai_service.dart`

```dart
class HeadlessAiService {
  HeadlessAiService({
    required CliToolRegistry registry,
    ProcessRunner runner = cliToolDefaultProcessRun,
  });

  Future<HeadlessAiResult> run({
    required AiFeatureSetting setting,   // cli + providerId + model + effort
    required String prompt,
    bool expectJson = false,
    Duration timeout = const Duration(seconds: 90),
  });
}
```

Responsibilities: resolve effective effort (`resolveLaunchEffort`) → build an isolated temp
`CONFIG_DIR` (reuse existing provider-credential / profile write logic) → fetch the CLI's
`HeadlessRunCapability` → `buildInvocation` → run via injected `ProcessRunner` with timeout →
`extractText` → return `{ text, rawStdout, exitCode }`. No UI, no feature semantics.

`HeadlessAiResult` = `{ String text, String rawStdout, int exitCode }`.

### Principles

- Reuse (not reinvent) provider/effort resolution and CONFIG_DIR isolation — same source as
  PTY launch.
- Service and capability are unit-tested via injected `ProcessRunner`; never spawn real
  subprocesses in tests.
- Both features depend only on `HeadlessAiService` and are agnostic to which CLI runs.

---

## Section 2 — Per-feature config storage + settings UI

### 2a. Model

`models/ai_feature_setting.dart`

```dart
class AiFeatureSetting {
  final CliTool cli;
  final String providerId;
  final String model;
  final String effort; // empty = use capability default
  // fromJson / toJson / copyWith
}

enum AiFeatureId { commitMessage, teamGenerate }
```

### 2b. Persistence

Stored under `AppSettingsRepository` (SharedPreferences, single JSON blob), new field:

```jsonc
"aiFeatures": {
  "commitMessage": { "cli": "claude", "providerId": "claude-official", "model": "sonnet", "effort": "" },
  "teamGenerate":  { "cli": "claude", "providerId": "claude-official", "model": "opus",   "effort": "high" }
}
```

- Held as `Map<AiFeatureId, AiFeatureSetting>`. Adding a new feature = add an enum value.
- Unconfigured feature → fallback to a sensible default (first available provider +
  its `defaultModel`); never block usage on prior configuration.

### 2c. Settings UI

New **AI Features** section under `pages/config/` (follow the existing config-section style,
e.g. `layout_region_visibility_section.dart`):

- One card per feature: title + one-line description + three selectors:
  - **CLI selector** (drives provider/model candidates),
  - `ProviderModelPickerField` (reused, registry-driven),
  - `CliEffortPickerField` (reused; auto-hides when model has no effort).
- A light `AiFeatureSettingsCubit` reads/writes through `AppSettingsRepository`
  (state via `flutter_bloc` only).

Config is global, cross-project, cross-team.

---

## Section 3 — Feature A: AI commit message generation

### 3a. UI integration

In `git_source_control_panel.dart`, add a **✨ Generate** `IconButton` next to the existing
commit `TextField` (no new panel).

- Disabled when there are no staged changes.
- On click: loading state (button spinner, field read-only) → write result into
  `_commitController.text` and call `GitCubit.setCommitMessage`.
- Generation fills a **draft**; user may edit or regenerate; it never auto-commits.

### 3b. Data flow

```
Click Generate
 → GitCubit.generateCommitMessage()
 → GitService.stagedDiff(dir)            // NEW: git diff --cached (size-capped, truncate + mark)
 → read AppSettings.aiFeatures[commitMessage]
 → build prompt (diff + instructions)
 → HeadlessAiService.run(setting, prompt, expectJson: false)
 → clean output (strip code fences, leading/trailing whitespace, explanatory prefixes)
 → write back into the commit field
```

### 3c. Prompt (per common open-source ai-commit practice)

- Instruction: Conventional Commits (`type(scope): subject`), imperative subject, ≤ ~72 chars,
  optional blank line + bullet body; output the commit message only — no explanation, no fences.
- Input: `git diff --cached` text (truncation-protected).
- Language: **English, fixed for v1** (YAGNI; app-language follow-up deferred).

### 3d. Edge cases / errors

- No staged changes → button disabled + hint to stage first.
- Oversized diff → truncate to a cap (~12k chars) and note "(truncated)" in the prompt.
- CLI missing / no provider configured / timeout / non-zero exit → existing `GitCubit`
  `errorMessage` → SnackBar (`context.l10n`); field returns to editable.

`GitService` only gains `stagedDiff()`; `commit` etc. already exist.

---

## Section 4 — Feature B: AI team-config generation

Core difficulty: constrain AI output to legal options (real providers, valid models,
installed skills) and keep generation reviewable before apply.

### 4a. Trigger

Extend the new-team dialog (`home_workspace_new_team_dialog.dart`) with a **Generate with AI**
entry:

- Multi-line text field: describe the team (e.g. "Flutter frontend, with code review and tests").
- A **granularity toggle**:
  - `Roster only`: members[] only (name + role/agentType + suggested model + effort).
  - `Full team draft`: plus team name, native/mixed, checked installed skills/plugins.
- Generate button → `HeadlessAiService.run(..., expectJson: true)`.

### 4b. Constraining output (key)

Inject an "allowed options" list into the prompt and require the AI to choose only from it:

- Legal models for the current CLI (`ProviderModelCapability.modelCandidates`).
- Legal effort levels (`CliEffortCapability.effortCandidates`).
- Configured provider ids (`providerIdsByTool` / `AppProviderRepository`).
- Installed skill/plugin ids (full-draft mode).
- Require strict JSON matching a given schema (members array / team fields).

After parsing, a **validation clamp**: illegal model → fall back to `defaultModel`; illegal
effort → clear (use default); unknown skill id → drop. The output is always a legal
`TeamConfig` draft.

### 4c. Data flow

```
description + granularity + current CLI
 → collect allowed-options lists
 → build schema-constrained prompt
 → HeadlessAiService.run(expectJson: true)
 → parse JSON → validate/clamp to legal values
 → build TeamConfig / members draft
 → populate the new-team dialog (visible, editable)
 → user confirms → existing TeamCubit.addTeam()
```

### 4d. Layering / files

- New `services/ai/team_config_generator.dart`: assemble lists + prompt, parse, validate,
  produce draft. No UI.
- Dialog gets a new section file under `pages/<domain>/` (per AGENTS.md, route-only UI in
  `pages/<domain>/`) to avoid bloating the dialog file.
- Reuse `DefaultTeamRoster` as a fallback when AI fails.

### 4e. Edge cases / errors

- JSON parse failure → retry once (prompt appends "JSON only"); on second failure → message +
  fall back to default roster; user proceeds manually.
- Timeout / CLI missing / no provider configured → l10n error; dialog stays manually usable.

AI output is a draft entering the existing creation flow; `TeamCubit.addTeam()` remains the
single landing point — no bypass of existing validation.

---

## Section 5 — Cross-cutting concerns

### Testing

- **`HeadlessRunCapability` per CLI**: fake `ProcessRunner`; assert `buildInvocation`
  executable/args/env; assert `extractText` unwraps each CLI's stdout envelope.
- **`HeadlessAiService`**: fake runner; verify effort resolution, timeout, non-zero exit → error.
- **`TeamConfigGenerator`**: feed crafted JSON; verify illegal model/effort/skill-id are
  clamped/dropped; corrupt JSON → retry logic.
- **`GitService.stagedDiff`**: fake runner verifies `git diff --cached` args + truncation.
- **cubit/widget tests**: use `GitService.debugOverrideFactory` and `setUpTestAppStorage()`;
  never spawn real git/subprocesses.

### l10n

All user-visible text → `app_en.arb` + `app_zh.arb` (generate button, settings titles/help,
error messages, team-gen dialog copy). Diagnostics via `AppLogger`; no `print`.

### Layering / file size (per AGENTS.md)

- Logic in `services/` + `cubits/`; no `Process.run` / raw paths in UI.
- New settings section and team-gen section split into their own section files to avoid
  bloating host files; services kept under ~600 lines.

### Acceptance

`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` passes.

---

## File-change summary

**New**
- `client/lib/services/cli/registry/capabilities/headless_run_capability.dart` (+ `HeadlessInvocation`, `HeadlessRunContext`)
- `client/lib/services/cli/registry/.../headless_run_capability` impls per CLI (claude, codex, flashskyai, cursor, opencode)
- `client/lib/services/ai/headless_ai_service.dart` (+ `HeadlessAiResult`)
- `client/lib/services/ai/team_config_generator.dart`
- `client/lib/models/ai_feature_setting.dart` (+ `AiFeatureId`)
- `client/lib/cubits/ai_feature_settings_cubit.dart`
- `client/lib/pages/config/ai_features_section.dart`
- team-gen dialog section file under `client/lib/pages/<domain>/`
- Tests mirroring each of the above

**Modified**
- `client/lib/repositories/app_settings_repository.dart` (add `aiFeatures`)
- `client/lib/services/git/git_service.dart` (add `stagedDiff`)
- `client/lib/cubits/git_cubit.dart` (add `generateCommitMessage`)
- `client/lib/widgets/git/git_source_control_panel.dart` (Generate button)
- `client/lib/pages/home_workspace/home_workspace_new_team_dialog.dart` (Generate with AI entry)
- each `*_cli_tool.dart` definition (register `HeadlessRunCapability`)
- settings page host (mount AI Features section)
- `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
