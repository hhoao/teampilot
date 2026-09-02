# Generate Settings Four-Tuple Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store generate-and-launch model-pool entries as inline launch four-tuples, expose a shared `LaunchFourTuplePicker` (Simple-mode cascade), and use it for both the generator model and pool rows — with native mode limited to `nativeCli`.

**Architecture:** Evolve `GenerateModelPoolEntry` to persist `id + cli/provider/model/effort`; hydrate legacy `presetId`-only JSON via presets at resolve/load time; keep `EffectiveGenerateModelPoolEntry.preset` as a **synthetic** `CliPreset` whose `id` equals the pool entry id (minimizes validator/materialize churn). Extract `LaunchFourTuplePicker` wrapping existing cascade helpers; wire generate-settings dialog; update context/skill copy.

**Tech Stack:** Flutter, `flutter_bloc`, `uuid`, existing `compose_model_preset_chip.dart` cascade builders, `CliToolRegistry` / `TeamBehaviorCapability`.

**Spec:** `docs/superpowers/specs/2026-09-03-generate-settings-four-tuple-picker-design.md`

## Global Constraints

- Analyze: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
- Tests: `cd client && dart run tool/run_tests.dart` (or targeted `flutter test <path>`)
- l10n: edit **both** `app_en.arb` and `app_zh.arb` only when new user-facing strings are required
- Native mode pickers: `cliItems == [nativeCli]`; native CLI dropdown stays `registry.nativeTeamLaunchable`
- Selecting a preset in the picker **snapshots** four-tuple; never bind `activePresetId` from generate settings
- Plan wire field name stays `presetId` (meaning = frozen pool entry `id`)
- No `print`; prefer existing patterns; do not migrate Simple compose chip in this plan
- Commit after each task

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/team_generation_settings.dart` | Inline pool entry + hydrate + snapshot resolve |
| `client/lib/services/team_generation/team_generation_context_payload.dart` | Expose `id` + four-tuple |
| `client/lib/services/team_generation/generated_team_plan_validator.dart` | Index by entry id; digest four-tuple |
| `client/lib/services/team_generation/managed_skills/team-builder/SKILL.md` (+ `providers/team_builder_skill_md.dart`) | Pool id semantics |
| `client/lib/widgets/compose/compose_model_preset_chip.dart` | Optional `showSavePreset` on cascade builder |
| `client/lib/widgets/cli_launch_config/launch_four_tuple_picker.dart` | Shared picker widget |
| `client/lib/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog.dart` | Generator + pool UI |
| Tests under `client/test/models/` and `client/test/services/team_generation/` | Model/snapshot/validator |
| `client/test/widgets/cli_launch_config/launch_four_tuple_picker_test.dart` | Picker behavior |

---

### Task 1: Inline `GenerateModelPoolEntry` + hydrate + snapshot

**Files:**
- Modify: `client/lib/models/team_generation_settings.dart`
- Modify: `client/test/models/team_generation_settings_test.dart`
- Modify callers that construct `GenerateModelPoolEntry(presetId: …)` once the constructor changes (compile fixes in this task if trivial; otherwise Task 5)

**Interfaces:**
- Produces:
```dart
final class GenerateModelPoolEntry {
  factory GenerateModelPoolEntry({
    required String id,
    required CliTool cli,
    required String provider,
    required String model,
    String effort = '',
    String description = '',
    List<String> tags = const [],
  });
  String get id;
  CliTool get cli;
  String get provider;
  String get model;
  String get effort;
  String get description;
  List<String> get tags;
  /// Non-null only for unhydrated legacy JSON rows.
  String? get legacyPresetId;
  bool get isInline; // legacyPresetId == null && provider/model usable
}

TeamGenerationSettings hydrateTeamGenerationSettings({
  required TeamGenerationSettings settings,
  required List<CliPreset> presets,
});

/// Builds synthetic CliPreset(id: entry.id, name: summary, cli/provider/model/effort from entry).
CliPreset syntheticPoolPreset(GenerateModelPoolEntry entry);
```
- `resolveTeamGenerationSettingsSnapshot` must hydrate first, skip rows that remain unresolved / non-launchable / native-mismatched, and set `EffectiveGenerateModelPoolEntry.preset = syntheticPoolPreset(entry)`.

- [ ] **Step 1: Write failing tests**

Replace/extend `client/test/models/team_generation_settings_test.dart`:

```dart
test('fromJson migrates legacy presetId into unresolved row', () {
  final entry = GenerateModelPoolEntry.fromJson({
    'presetId': 'claude-strong',
    'description': 'lead',
    'tags': ['strong'],
  });
  expect(entry.legacyPresetId, 'claude-strong');
  expect(entry.id, 'claude-strong');
  expect(entry.isInline, isFalse);
});

test('hydrate snapshots preset into inline four-tuple', () {
  final hydrated = hydrateTeamGenerationSettings(
    settings: TeamGenerationSettings(
      modelPool: [
        GenerateModelPoolEntry.fromJson({'presetId': 'claude-strong'}),
      ],
    ),
    presets: [
      CliPreset(
        id: 'claude-strong',
        name: 'Strong',
        cli: CliTool.claude,
        provider: 'anthropic',
        model: 'opus',
        effort: 'high',
        createdAt: 1,
        updatedAt: 1,
      ),
    ],
  );
  final entry = hydrated.modelPool.single;
  expect(entry.isInline, isTrue);
  expect(entry.id, 'claude-strong');
  expect(entry.cli, CliTool.claude);
  expect(entry.provider, 'anthropic');
  expect(entry.model, 'opus');
  expect(entry.effort, 'high');
  expect(entry.toJson().containsKey('presetId'), isFalse);
  expect(entry.toJson()['id'], 'claude-strong');
});

test('native snapshot filters by native cli using inline entries', () {
  final snapshot = resolveTeamGenerationSettingsSnapshot(
    settings: TeamGenerationSettings(
      teamMode: TeamMode.native,
      nativeCli: CliTool.claude,
      modelPool: [
        GenerateModelPoolEntry(
          id: 'codex-row',
          cli: CliTool.codex,
          provider: 'o',
          model: 'm',
        ),
        GenerateModelPoolEntry(
          id: 'claude-row',
          cli: CliTool.claude,
          provider: 'p',
          model: 'm',
          description: 'lead',
          tags: ['strong'],
        ),
      ],
    ),
    presets: const [],
    registry: CliToolRegistry.builtIn(),
    capturedAt: 42,
  );
  expect(snapshot.modelPool.single.rank, 1);
  expect(snapshot.modelPool.single.preset.id, 'claude-row');
  expect(snapshot.modelPool.single.preset.cli, CliTool.claude);
});

test('hydrate drops unknown legacy preset from effective pool', () {
  final snapshot = resolveTeamGenerationSettingsSnapshot(
    settings: TeamGenerationSettings(
      modelPool: [
        GenerateModelPoolEntry.fromJson({'presetId': 'missing'}),
      ],
    ),
    presets: const [],
    registry: CliToolRegistry.builtIn(),
    capturedAt: 1,
  );
  expect(snapshot.modelPool, isEmpty);
});
```

Update existing tests that pass `GenerateModelPoolEntry(presetId: …)` to the new factory or `fromJson` + hydrate.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/models/team_generation_settings_test.dart`

Expected: FAIL (constructor / APIs missing).

- [ ] **Step 3: Implement model + hydrate + snapshot**

In `team_generation_settings.dart`:

1. Rewrite `GenerateModelPoolEntry` with inline fields + optional `legacyPresetId`.
2. `fromJson`: if `cli` present (string parseable) and (`provider` or `model` non-empty), treat as inline (`id` defaulting to uuid if blank). Else if `presetId` present → `id = presetId`, `legacyPresetId = presetId`, dummy `cli = CliTool.claude`, empty provider/model.
3. `toJson`: write `id, cli, provider, model, effort?, description?, tags?` — **never** write `presetId`.
4. Implement `hydrateTeamGenerationSettings` and `syntheticPoolPreset`.
5. Update `resolveTeamGenerationSettingsSnapshot` to hydrate, then filter launchable + native rules using `entry.cli` (not lookup by preset table). Ignore `presets` for inline rows; still accept `presets` param for hydrate.
6. Update `TeamGenerationSettingsSnapshot` nested serialization: `preset` remains synthetic CliPreset JSON; `source` is inline entry JSON. Keep recovery if nested preset id empty → use `source.id`.

Use `package:uuid/uuid.dart` (`const Uuid().v4()`) only when creating **new** inline rows without id (factory default or dialog later).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/models/team_generation_settings_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/team_generation_settings.dart \
  client/test/models/team_generation_settings_test.dart
git commit -m "$(cat <<'EOF'
feat(team-generation): store model pool as inline four-tuples

Hydrate legacy presetId rows and snapshot synthetic CliPresets keyed by
pool entry id for downstream validators.
EOF
)"
```

---

### Task 2: Context payload, validator, skill, and compile-fix call sites

**Files:**
- Modify: `client/lib/services/team_generation/team_generation_context_payload.dart`
- Modify: `client/lib/services/team_generation/generated_team_plan_validator.dart`
- Modify: `client/lib/services/team_generation/managed_skills/team-builder/SKILL.md`
- Modify: `client/lib/services/team_generation/providers/team_builder_skill_md.dart` (keep in sync with SKILL.md)
- Modify: any production/test files still using `GenerateModelPoolEntry(presetId:)` / `.presetId` / `effectiveTeamGenerationPresetId`
- Modify: `client/test/services/team_generation/team_generation_settings_store_test.dart`
- Modify: `client/test/services/team_generation/team_generation_compatibility_test.dart`
- Modify: coordinator / workflow tests that build pool entries

**Interfaces:**
- Consumes: Task 1 entry/snapshot APIs
- Produces: context `modelPool[].id` (same string member plans put in `presetId`)
```dart
String effectiveTeamGenerationPoolEntryId(EffectiveGenerateModelPoolEntry entry) =>
  entry.preset.id.isNotEmpty ? entry.preset.id : entry.source.id;
```

- [ ] **Step 1: Write / update failing tests**

In settings store test, after load of legacy JSON, assert either unresolved legacy fields **or** (if store hydrates — it should **not**) raw load keeps legacy; snapshot/hydrate is separate. Prefer:

```dart
expect(loaded.modelPool.first.legacyPresetId, 'strong');
// after hydrate in test:
final hydrated = hydrateTeamGenerationSettings(settings: loaded, presets: [...]);
expect(hydrated.modelPool.first.model, isNotEmpty);
```

Add validator unit coverage if a focused test file exists; otherwise extend an existing generated-plan / compatibility test:

```dart
// member.presetId == pool entry id 'pool-1' must validate when digest matches
// synthetic preset four-tuple
```

- [ ] **Step 2: Run a focused test to see red/compile errors**

Run: `cd client && flutter test test/services/team_generation/team_generation_settings_store_test.dart test/services/team_generation/team_generation_compatibility_test.dart`

Expected: FAIL or compile errors until call sites updated.

- [ ] **Step 3: Implement payload + validator + skill + fix call sites**

1. Context payload:
```dart
'modelPool': [
  for (final entry in job.settings.modelPool)
    {
      'rank': entry.rank,
      'id': effectiveTeamGenerationPoolEntryId(entry),
      // keep 'presetId' alias equal to id for one release if skill still mentions it:
      'presetId': effectiveTeamGenerationPoolEntryId(entry),
      'cli': entry.preset.cli.value,
      'provider': entry.preset.provider,
      'model': entry.preset.model,
      'effort': entry.preset.effort,
      'description': entry.source.description,
      'tags': entry.source.tags,
    },
],
```

2. Validator `poolById`: key = `effectiveTeamGenerationPoolEntryId(entry)`. Digests: hash `cli/provider/model/effort` from `entry.preset` (already synthetic).

3. Skill: replace “global preset” wording with “frozen modelPool entry id (`presetId` / `id`)”.

4. Fix all `GenerateModelPoolEntry(presetId: x)` in tests to inline factory, e.g.:
```dart
GenerateModelPoolEntry(
  id: preset.id,
  cli: preset.cli,
  provider: preset.provider,
  model: preset.model,
  effort: preset.effort,
)
```

- [ ] **Step 4: Run team_generation tests**

Run: `cd client && flutter test test/services/team_generation test/models/team_generation_settings_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team_generation \
  client/test/services/team_generation \
  client/test/models/team_generation_settings_test.dart
git commit -m "$(cat <<'EOF'
feat(team-generation): wire pool entry ids through context and validator

Keep plan member presetId as the frozen pool entry id; document in
team-builder skill.
EOF
)"
```

---

### Task 3: Cascade builder flag `showSavePreset`

**Files:**
- Modify: `client/lib/widgets/compose/compose_model_preset_chip.dart`
- Modify: existing compose cascade tests if any (`client/test/**/compose*cascade*`)

**Interfaces:**
- Produces: `buildComposeModelCascadeMenuSpecs(..., {bool showSavePreset = true, bool showManagePresets = true})`
- When `showSavePreset: false`, omit the save-preset action row
- When `showManagePresets: false`, omit manage row

- [ ] **Step 1: Write failing test** (or extend existing)

```dart
test('omits save preset when showSavePreset is false', () {
  final specs = buildComposeModelCascadeMenuSpecs(
    presets: const [],
    selectedPresetId: null,
    emptyHintLabel: 'empty',
    emptyProvidersLabel: 'none',
    presetsLabel: 'Presets',
    defaultEffortLabel: 'Default',
    customModelIdLabel: 'Custom',
    noModelsLabel: 'No models',
    savePresetLabel: 'Save',
    managePresetsLabel: 'Manage',
    cliGroups: const [],
    groupByCli: true,
    showSavePreset: false,
    showManagePresets: true,
  );
  final labels = specs.map((s) => s.label).whereType<String>().toList();
  expect(labels, isNot(contains('Save')));
  expect(labels, contains('Manage'));
});
```

(If `TpActionMenuSpec` exposes `label` differently, assert on `value != ComposeModelPresetChipAction.savePreset`.)

- [ ] **Step 2: Run test — expect FAIL**

- [ ] **Step 3: Implement optional flags** (default `true` so Simple compose unchanged)

- [ ] **Step 4: Run test — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(compose): allow hiding save-preset in cascade menu"
```

---

### Task 4: `LaunchFourTuplePicker` widget

**Files:**
- Create: `client/lib/widgets/cli_launch_config/launch_four_tuple_picker.dart`
- Create: `client/test/widgets/cli_launch_config/launch_four_tuple_picker_test.dart`

**Interfaces:**
```dart
class LaunchFourTuplePicker extends StatefulWidget {
  const LaunchFourTuplePicker({
    required this.value, // SimpleLaunchFourTuple? ; null = unconfigured
    required this.cliItems,
    required this.presets,
    required this.onChanged,
    this.showManagePresets = true,
    this.showSavePreset = false,
    this.emptyLabel, // falls back to l10n
    super.key,
  });

  final SimpleLaunchFourTuple? value;
  final List<CliTool> cliItems;
  final List<CliPreset> presets;
  final ValueChanged<SimpleLaunchFourTuple> onChanged;
  final bool showManagePresets;
  final bool showSavePreset;
}
```

Behavior:
- Trigger: `TpActionMenuButton` (or same pattern as compose chip) with `CliBrandIcon` + `simpleLaunchChipLabel(...)`.
- Menu: filter `presets` to those whose `cli` is in `cliItems`; build groups via `resolveComposeCascadeCliGroups` for `cliItems` only.
- On preset id selected: snapshot `CliPreset` → `SimpleLaunchFourTuple` → `onChanged` (do **not** keep preset id).
- On `decodeComposeCascadeValue`: `onChanged`.
- On `CascadeCustomModelRequest`: `showComposeCustomModelIdDialog` then `onChanged`.
- On manage: `CliPresetsManageDialog` (same as compose).
- Attach `CascadeCatalogListenable` for catalog refresh while mounted.

- [ ] **Step 1: Write failing widget test**

```dart
testWidgets('selecting cascade model calls onChanged with four-tuple', (tester) async {
  SimpleLaunchFourTuple? got;
  // Pump picker with a fake registry / provider cubit harness used elsewhere
  // Tap trigger → open provider → tap a model leaf
  expect(got!.cli, CliTool.claude);
  expect(got.modelId, isNotEmpty);
});
```

Use existing test harness patterns from compose cascade / `setUpTestAppStorage` if providers need AppStorage. Prefer the lightest harness that supplies `CliToolRegistryScope`, `AppProviderCubit`, `CliPresetsCubit`.

If full cascade pump is too heavy for one task, test a **pure helper** first:

```dart
SimpleLaunchFourTuple? tupleFromCascadeSelection({
  required Object? value,
  required List<CliPreset> presets,
});
```

implemented in the same file — preset id string → snapshot; else `decodeComposeCascadeValue`. Widget test can be minimal smoke (builds without throw).

- [ ] **Step 2: Run test — expect FAIL**

- [ ] **Step 3: Implement picker + helper**

- [ ] **Step 4: Run test — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/cli_launch_config/launch_four_tuple_picker.dart \
  client/test/widgets/cli_launch_config/launch_four_tuple_picker_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): add LaunchFourTuplePicker for shared cascade launch config

Reusable Simple-mode cascade for generate settings (and later compose).
EOF
)"
```

---

### Task 5: Wire generate settings dialog

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog.dart`
- Modify l10n only if new strings needed (prefer reusing `teamGenerate*` / compose cascade strings)
- Optional: `client/test/pages/...` or widget test for dialog save clearing `activePresetId` (if no page test harness, cover via a small unit on save mapping)

**Interfaces:**
- Consumes: `LaunchFourTuplePicker`, `hydrateTeamGenerationSettings`, `GenerateModelPoolEntry` inline factory
- On load: `hydrateTeamGenerationSettings(settings: loaded, presets: widget.presets)`
- Generator: `LaunchFourTuplePicker` bound to draft four-tuple derived from resolved `AiFeatureSetting` (ignore `activePresetId` when displaying/saving)
- Pool row: show picker for that row’s four-tuple; description/tags fields unchanged
- Add row: create `GenerateModelPoolEntry(id: Uuid().v4(), cli: …, …)` after picker confirms (or add with placeholder and require picker before save — prefer: open picker first; only append on success)
- Native: `cliItems: _teamMode == TeamMode.native ? [_nativeCli] : launchableIds`
- `_canSave`: effective pool non-empty + generator configured via `aiFeatureIsConfigured` on draft setting **without** preset id
- Save:
```dart
await cubit.updateSetting(
  AiFeatureId.teamGenerate,
  AiFeatureSetting(
    activePresetId: null,
    cli: generator.cli,
    providerId: generator.providerId,
    model: generator.modelId,
    effort: generator.effort,
  ),
);
await _store.save(TeamGenerationSettings(
  teamMode: _teamMode,
  nativeCli: _nativeCli,
  modelPool: _rows.map((r) => r.toEntry()).toList(),
));
```
- Remove `AiFeatureConfigurePanel` usage from this dialog (panel may remain for AI Features page).

- [ ] **Step 1: Update dialog `_PoolRow` to hold inline fields + id**

```dart
class _PoolRow {
  _PoolRow({
    required this.id,
    required this.cli,
    required this.provider,
    required this.model,
    this.effort = '',
    this.description = '',
    List<String>? tags,
  });
  String id;
  CliTool cli;
  String provider;
  String model;
  String effort;
  String description;
  List<String> tags;
  GenerateModelPoolEntry toEntry() => GenerateModelPoolEntry(
    id: id,
    cli: cli,
    provider: provider,
    model: model,
    effort: effort,
    description: description,
    tags: tags,
  );
}
```

Visibility: `_isVisibleRow` uses `row.cli` vs `_nativeCli` (not preset lookup).

- [ ] **Step 2: Replace generator + add/pool pickers with `LaunchFourTuplePicker`**

- [ ] **Step 3: Manual/analyze check**

Run: `cd client && dart analyze lib/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog.dart lib/widgets/cli_launch_config/launch_four_tuple_picker.dart --no-fatal-infos --no-fatal-warnings`

Expected: No issues.

- [ ] **Step 4: Run related tests**

Run: `cd client && flutter test test/models/team_generation_settings_test.dart test/services/team_generation test/widgets/cli_launch_config/launch_four_tuple_picker_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations*.dart
git commit -m "$(cat <<'EOF'
feat(team-generation): use LaunchFourTuplePicker in generate settings

Generator and model pool both pick inline four-tuples; native mode
limits cascade CLIs to nativeCli.
EOF
)"
```

---

### Task 6: Final verification

**Files:** none new

- [ ] **Step 1: Full analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: clean for touched areas (no new errors).

- [ ] **Step 2: Full or targeted test suite**

Run: `cd client && dart run tool/run_tests.dart`

Expected: PASS (or only pre-existing failures unrelated to this work — do not ignore new failures in team_generation / models / picker).

- [ ] **Step 3: Spec checklist**

Confirm against `docs/superpowers/specs/2026-09-03-generate-settings-four-tuple-picker-design.md`:

- [ ] Pool custom models without named preset
- [ ] Native CLI filter on pickers
- [ ] Generator cascade + `activePresetId: null` on save
- [ ] Legacy `presetId` load hydrate
- [ ] Context/validator use pool entry ids

- [ ] **Step 4: Commit any leftover fixes** (only if needed)

---

## Self-review (plan vs spec)

| Spec requirement | Task |
|------------------|------|
| Inline four-tuple pool + legacy hydrate | Task 1 |
| Effective/context/validator by entry id | Task 2 |
| Snapshot presets; no live bind | Tasks 1, 4, 5 |
| `LaunchFourTuplePicker` extraction | Task 4 |
| Generator + pool use picker | Task 5 |
| Native `cliItems = [nativeCli]` | Task 5 |
| No Simple compose migration | Non-goal (global) |
| No save-as-preset in settings | Task 3 flag + Task 4 default |
| Skill/docs update | Task 2 |

Type consistency: `SimpleLaunchFourTuple` from `compose_model_preset_chip.dart`; pool entry `id` == synthetic `CliPreset.id` == context `id`/`presetId` == plan member `presetId`.
