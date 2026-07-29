# Simple Custom Launch Compose Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Simple Landing and Simple Continue choose either a global CLI preset or an explicit `cli/provider/model/effort` four-tuple without saving a global preset.

**Architecture:** Extend `LandingLaunchContext` / `LandingPrefs` with optional custom fields (`cli != null` ⇒ Custom mode). Model chip menu keeps presets first and adds **自定义…** opening a thin dialog around `CliLaunchCustomFields`. Submit uses `SimpleLaunchIdentity.resolve`; Continue adds `ChatCubit.setSessionContinueCustom` (snapshot + persist with `presetId: ''`). Enhance reads the same draft four-tuple.

**Tech Stack:** Flutter / `flutter_bloc`; existing `CliLaunchCustomFields`, `SimpleLaunchIdentity`, `LandingPrefsStore`, `TpActionMenuSpec`.

**Spec:** `docs/superpowers/specs/2026-07-29-simple-custom-launch-compose-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/landing_launch_context.dart` | Optional `cli/provider/model/effort`; clearable `copyWith` |
| `client/lib/services/home_workspace/landing_prefs_store.dart` | Persist/omit custom fields |
| `client/lib/utils/workspace/landing_draft_resolver.dart` | Map prefs ↔ draft including custom |
| `client/lib/widgets/compose/compose_model_preset_chip.dart` | Menu sentinel + chip widget props; chip summary helper |
| `client/lib/widgets/compose/compose_chrome.dart` | BoundComposeChrome passthrough for custom menu props |
| `client/lib/widgets/compose/workspace_compose_card.dart` | Passthrough custom menu props to chip |
| `client/lib/widgets/compose/simple_custom_launch_dialog.dart` | NEW — dialog host for `CliLaunchCustomFields` |
| `client/lib/services/compose/compose_prompt_enhance.dart` | Enhance from custom four-tuple |
| `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart` | Landing state, menu, dialog, draft |
| `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` | Pass custom fields into `SimpleLaunchIdentity.resolve` |
| `client/lib/cubits/chat/session_continue_overrides_controller.dart` | `patchCustom` / `persistCustom` |
| `client/lib/cubits/chat_cubit.dart` | `setSessionContinueCustom` |
| `client/lib/pages/chat/session_chat_view.dart` | Simple Continue menu + dialog + labels |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | 自定义… (+ regenerate l10n) |
| Tests colocated under `client/test/…` | Per-task |

---

### Task 1: Draft / prefs four-tuple + clearable `copyWith`

**Files:**
- Modify: `client/lib/models/landing_launch_context.dart`
- Modify: `client/lib/services/home_workspace/landing_prefs_store.dart`
- Modify: `client/lib/utils/workspace/landing_draft_resolver.dart`
- Test: `client/test/utils/workspace/landing_draft_resolver_test.dart`
- Test: `client/test/models/landing_launch_context_test.dart` (create if none)

- [ ] **Step 1: Write failing tests**

```dart
test('copyWith can clear presetId and set custom cli', () {
  const base = LandingLaunchContext(isPersonal: true, presetId: 'p1');
  final next = base.copyWith(
    presetId: null, // must clear — use Object? _unset pattern
    clearPresetId: true, // OR extend copyWith with Object? presetId = _unset
    cli: CliTool.cursor,
    provider: 'cursor-account',
  );
  expect(next.presetId, isNull);
  expect(next.cli, CliTool.cursor);
  expect(next.provider, 'cursor-account');
});

test('persistLandingDraft round-trips custom four-tuple', () async {
  // save draft with cli/provider/model/effort, no presetId
  // resolveLandingDraft → same fields
});

test('persistLandingDraft omits empty custom fields from JSON', () async {
  // empty LandingLaunchContext → JSON has no cli/provider keys
});
```

Prefer matching existing `_unset` style already used for `expertKey` in `LandingLaunchContext.copyWith` — extend `presetId` the same way (`Object? presetId = _unset`) so `copyWith(presetId: null)` clears.

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client && flutter test test/models/landing_launch_context_test.dart test/utils/workspace/landing_draft_resolver_test.dart --reporter compact
```

- [ ] **Step 3: Implement models + prefs + resolver**

- `LandingLaunchContext`: add `CliTool? cli`, `String? provider/model/effort`; update `==` / `hashCode` / `copyWith` (clearable `presetId` + four fields).
- `LandingPrefs`: same fields; `toJson` omit empties; parse `cli` via `CliTool.parse` when present.
- `resolveLandingDraft` / `persistLandingDraft`: map fields both ways.

Helper (optional, same file or small util):

```dart
bool landingDraftIsCustom(LandingLaunchContext d) =>
    d.isPersonal && d.cli != null;
```

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit** (only if user asked for commits)

```bash
git add client/lib/models/landing_launch_context.dart \
  client/lib/services/home_workspace/landing_prefs_store.dart \
  client/lib/utils/workspace/landing_draft_resolver.dart \
  client/test/models/landing_launch_context_test.dart \
  client/test/utils/workspace/landing_draft_resolver_test.dart
git commit -m "$(cat <<'EOF'
feat(landing): persist Simple custom cli/provider/model/effort draft fields

EOF
)"
```

---

### Task 2: Chip summary helper + menu custom sentinel

**Files:**
- Modify: `client/lib/widgets/compose/compose_model_preset_chip.dart`
- Test: `client/test/widgets/compose/compose_model_preset_chip_test.dart` (extend or create)
- Also update callers of `buildComposeModelPresetMenuSpecs` signature carefully

- [ ] **Step 1: Write failing tests**

```dart
test('buildComposeModelPresetMenuSpecs inserts custom action before manage', () {
  final specs = buildComposeModelPresetMenuSpecs(
    sameCliPresets: [/* one preset */],
    selectedPresetId: null,
    emptyHintLabel: 'No presets',
    customLabel: 'Custom…',
    customSelected: true,
    managePresetsLabel: 'Add preset',
  );
  expect(
    specs.any((s) => s.value == ComposeModelPresetChipAction.custom),
    isTrue,
  );
  expect(
    specs.where((s) => s.value == ComposeModelPresetChipAction.custom).single.selected,
    isTrue,
  );
});

test('simpleLaunchChipLabel prefers preset name then custom summary', () {
  expect(
    simpleLaunchChipLabel(
      presetName: 'Work',
      cli: null,
      provider: null,
      model: null,
      emptyLabel: 'Use preset',
      cliLabel: (c) => c.name,
    ),
    'Use preset',
  );
  expect(
    simpleLaunchChipLabel(
      presetName: null,
      cli: CliTool.claude,
      provider: 'claude-official',
      model: 'opus',
      emptyLabel: 'Use preset',
      cliLabel: (_) => 'Claude',
    ),
    'Claude · opus',
  );
});
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/widgets/compose/compose_model_preset_chip_test.dart --reporter compact
```

- [ ] **Step 3: Implement**

- Add `ComposeModelPresetChipAction.custom` sentinel (alongside `manage`).
- Extend `buildComposeModelPresetMenuSpecs` with optional `customLabel`, `customSelected`.
- Menu order: presets (or empty hint) → divider → custom (if label non-null) → manage (if label non-null).
- When `customLabel == null` (Team Continue), omit custom row — preserves Team UI.
- Add pure `simpleLaunchChipLabel(...)` covering: empty; `cli · model`; `cli · provider` when model empty; CLI-only when both empty.
- Extend **`ComposeModelPresetChip`** widget with `customLabel`, `customSelected`, `onCustom` (handle sentinel like `manage`).
- Thread the same optional params through **`BoundComposeChrome`** (`compose_chrome.dart`) and **`WorkspaceComposeCard`** (`workspace_compose_card.dart`) so Continue can pass them from `session_chat_view` without dead ends.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit** (if requested)

---

### Task 3: l10n strings

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Run codegen as repo normally does for ARB (Flutter gen-l10n / existing workflow)

- [ ] **Step 1: Add keys**

```json
"workspaceChatLandingCustomLaunch": "Custom…",
"workspaceChatLandingCustomLaunchTitle": "Custom launch"
```

zh:

```json
"workspaceChatLandingCustomLaunch": "自定义…",
"workspaceChatLandingCustomLaunchTitle": "自定义启动"
```

- [ ] **Step 2: Regenerate l10n** (follow `docs/DEVELOPMENT.md` / existing `flutter gen-l10n` practice in this repo)

- [ ] **Step 3: Commit** (if requested)

---

### Task 4: Simple custom launch dialog

**Files:**
- Create: `client/lib/widgets/compose/simple_custom_launch_dialog.dart`
- Test: `client/test/widgets/compose/simple_custom_launch_dialog_test.dart` (smoke: pumps with mocked providers/registry; confirm returns result)

- [ ] **Step 1: Write failing smoke test** that looks for title / confirm button keys

- [ ] **Step 2: Implement dialog**

```dart
class SimpleCustomLaunchResult {
  const SimpleCustomLaunchResult({
    required this.cli,
    required this.provider,
    required this.model,
    required this.effort,
  });
  final CliTool cli;
  final String provider;
  final String model;
  final String effort;
}

Future<SimpleCustomLaunchResult?> showSimpleCustomLaunchDialog(
  BuildContext context, {
  required CliTool? initialCli,
  required String initialProvider,
  required String initialModel,
  required String initialEffort,
  required bool lockCli,
}) async { /* TpDialog + CliLaunchCustomFields */ }
```

- Landing: `lockCli: false`, `CliLaunchCliFieldKind.toolList`
- Continue: `lockCli: true`, CLI field hidden; seed from session
- Confirm disabled until `cli != null` (Landing) / always have locked cli (Continue)
- Load providers from `AppProviderCubit` filtered by catalog CLI (same pattern as `CliPresetEditDialog` / member launch dialog)

- [ ] **Step 3: Run test — PASS**

- [ ] **Step 4: Commit** (if requested)

---

### Task 5: Enhance resolves custom four-tuple

**Files:**
- Modify: `client/lib/services/compose/compose_prompt_enhance.dart`
- Test: `client/test/services/compose/compose_prompt_enhance_test.dart`

- [ ] **Step 1: Failing tests**

```dart
test('resolveLandingEnhanceSetting uses custom cli/provider when presetId empty', () {
  final setting = resolveLandingEnhanceSetting(
    draft: LandingLaunchContext(
      isPersonal: true,
      cli: CliTool.cursor,
      provider: 'cursor-account',
      model: 'gpt',
    ),
    presets: const [], // no presets — must not null solely for that
    teams: const [],
    appProviders: /* fixture with cursor-account */,
    registry: CliToolRegistry.builtIn(),
  );
  expect(setting, isNotNull);
  expect(setting!.cli, CliTool.cursor);
});

test('resolveLandingEnhanceSetting empty personal still falls back to first preset', () {
  // existing behavior when cli == null && presetId empty
});
```

- [ ] **Step 2: Implement**

In `draft.isPersonal` branch:

```dart
final presetId = draft.presetId?.trim() ?? '';
if (presetId.isNotEmpty) { /* existing preset path */ }
if (draft.cli != null) {
  final providerId = draft.provider?.trim().isNotEmpty == true
      ? draft.provider!.trim()
      : (SimpleLaunchIdentity.officialProviderIdFor(draft.cli!) ?? '');
  if (providerId.isEmpty) return null;
  return resolveAiFeatureSetting(
    stored: AiFeatureSetting(
      cli: draft.cli!,
      providerId: providerId,
      model: draft.model ?? '',
      effort: draft.effort ?? '',
    ),
    ...
  );
}
// else existing presets.firstOrNull fallback
```

- [ ] **Step 3: Run — PASS**

- [ ] **Step 4: Commit** (if requested)

---

### Task 6: Landing submit + unbound compose wiring

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` (`_resolveSimpleLaunchIdentity`)
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`
- Test: extend existing landing / identity tests; add focused unit test for resolve helper if extracted

- [ ] **Step 1: Extend `_resolveSimpleLaunchIdentity`**

```dart
SimpleLaunchIdentity _resolveSimpleLaunchIdentity(
  BuildContext context, {
  String? presetId,
  CliTool? cli,
  String? provider,
  String? model,
  String? effort,
  String? expertKey,
}) {
  final presets = context.read<CliPresetsCubit>().state.presets;
  final preset = _presetById(presetId, presets);
  if (preset != null) {
    return SimpleLaunchIdentity.resolve(
      preset: preset,
      presetId: presetId,
      expertKey: expertKey,
    );
  }
  return SimpleLaunchIdentity.resolve(
    cli: cli,
    provider: provider,
    model: model,
    effort: effort,
    presetId: '',
    expertKey: expertKey,
  );
}
```

Call site in `submitWorkspaceLandingMessage`: pass `launch.cli/provider/model/effort` when personal.

- [ ] **Step 2: Wire `unbound_compose_body`**

- Mirror custom fields in state the same way as `_selectedPresetId`: e.g. `_selectedCli`, `_selectedProvider`, `_selectedModel`, `_selectedEffort` (or a small record), loaded in `_applyDraft`, written in `_currentDraft`, cleared when selecting a preset.
- `_selectPreset`: set preset id + **clear** `_selectedCli` / provider / model / effort.
- Simple ↔ Team mode switch: **do not** wipe custom four-tuple state (prefs retain it while Team ignores it on submit).
- Menu: pass `customLabel: l10n.workspaceChatLandingCustomLaunch`, `customSelected: _selectedCli != null && preset empty`.
- On custom action: `showSimpleCustomLaunchDialog` → set four-tuple locals, clear preset id, `_persistDraft`.
- Chip label / leading: `simpleLaunchChipLabel` + selected/draft cli.

- [ ] **Step 3: Tests**

- Widget or unit: selecting preset clears cli on draft builder helper if extracted.
- `flutter test` for touched unit tests + any existing unbound compose tests that construct `LandingLaunchContext`.

- [ ] **Step 4: Commit** (if requested)

---

### Task 7: Continue Cubit `setSessionContinueCustom`

**Files:**
- Modify: `client/lib/cubits/chat/session_continue_overrides_controller.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/cubits/chat/session_continue_custom_test.dart` (create)

- [ ] **Step 1: Failing Cubit/controller test**

```dart
test('setSessionContinueCustom clears presetId and updates provider/model/effort', () async {
  // session with presetId 'p1', cli cursor
  // call setSessionContinueCustom(provider:, model:, effort:)
  // expect snapshot presetId '', provider/model/effort updated, cli unchanged
  // verify repo.updateSimpleLaunchIdentity called with presetId: ''
});
```

- [ ] **Step 2: Implement**

Controller:

```dart
AppSession? patchCustom({
  required AppSession session,
  required String provider,
  required String model,
  required String effort,
}) {
  if (!session.isSimple) return null;
  return session.copyWith(
    presetId: '',
    provider: provider,
    model: model,
    effort: effort,
  );
}

Future<void> persistCustom({...}) => repo.updateSimpleLaunchIdentity(
  patched.sessionId,
  presetId: '', // required to clear
  provider: patched.provider,
  model: patched.model,
  effort: patched.effort,
);
```

`ChatCubit.setSessionContinueCustom` mirrors `setSessionContinuePreset` (patch → persist → `replaceSessionSnapshot`).

- [ ] **Step 3: Run — PASS**

- [ ] **Step 4: Commit** (if requested)

---

### Task 8: Session Continue UI (Simple only)

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Modify (passthrough already done in Task 2; verify): `compose_chrome.dart`, `workspace_compose_card.dart`
- Ensure Continue enhance draft includes custom fields from session (`_enhanceDraft` / equivalent)

- [ ] **Step 1: Wire menu from `session_chat_view` through BoundComposeChrome**

- When `session.isSimple`: pass `customLabel`, `customSelected: session.presetId.trim().isEmpty`, `onCustom: () => open dialog`.
- **自定义…** → dialog `lockCli: true`, seed from session → `setSessionContinueCustom`.
- Team sessions: `customLabel: null` / `onCustom: null` (no row).
- Confirm BoundComposeChrome → WorkspaceComposeCard → ComposeModelPresetChip receive and forward these props (Task 2).

- [ ] **Step 2: Chip label**

```dart
final presetId = session.presetId.trim();
final label = presetId.isNotEmpty
    ? (presetName ?? presetId)
    : simpleLaunchChipLabel(
        presetName: null,
        cli: session.cli ?? CliTool.claude,
        provider: session.provider,
        model: session.model,
        emptyLabel: l10n.workspaceChatLandingUsePreset, // unused when cli non-null
        cliLabel: ...,
      );
```

- [ ] **Step 3: Enhance draft**

`_enhanceDraft` (or Continue equivalent) must set `cli/provider/model/effort` from session when `presetId` empty so `resolveLandingEnhanceSetting` hits custom branch.

- [ ] **Step 4: Targeted widget/cubit tests if feasible; else manual checklist in Task 9**

- [ ] **Step 5: Commit** (if requested)

---

### Task 9: Verification

- [ ] **Step 1: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 2: Tests**

```bash
cd client && flutter test \
  test/models/landing_launch_context_test.dart \
  test/utils/workspace/landing_draft_resolver_test.dart \
  test/widgets/compose/compose_model_preset_chip_test.dart \
  test/services/compose/compose_prompt_enhance_test.dart \
  test/cubits/chat/session_continue_custom_test.dart \
  --reporter compact
```

Add any other tests created in prior tasks. Fix failures.

- [ ] **Step 3: Manual smoke (optional but recommended)**

1. Landing Simple → 自定义… → pick CLI/provider/model → chip shows summary → send creates session with those fields, `presetId` empty  
2. Landing → pick preset → custom fields cleared  
3. Simple Continue → 自定义… → change model → chip updates; CLI unchanged  
4. Team Continue → no 自定义…  
5. Enhance on Landing custom draft uses that provider  

- [ ] **Step 4: Final commit** (if requested)

---

## Execution notes

- **TDD:** red → green per task; do not skip failing-test step.
- **Commits:** plan lists commit steps for agents; only run them if the user asked to commit.
- **Expert deep link:** when touching `copyWith` call sites, do not clear custom fields unless intentionally resetting launch dials (spec edge case).
- **Do not** write custom choices into `cli-presets.json`.
