# Configurable Generated Team Minimum Members Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted, snapshot-frozen minimum generated-team member count defaulting to 3, while removing the generated-plan hard maximum of 5.

**Architecture:** Store `minimumMemberCount` in `TeamGenerationSettings`, normalize legacy and invalid values to at least 3, and carry it through `TeamGenerationSettingsSnapshot` into the durable generation job. Expose only that frozen minimum to the Builder context, update both managed-skill sources, and enforce the minimum in `GeneratedTeamPlanValidator`; no new maximum is introduced.

**Tech Stack:** Dart, Flutter widgets, Flutter localization ARB files, Bloc/Cubit state access, JSON persistence, Flutter unit/widget tests, repository test runner.

## Global Constraints

- Count the minimum by distinct generated plan member entries, not expanded `replicas` seats.
- Default and legacy fallback are `3`; accepted settings are integers `>= 3` with no product maximum.
- Do not modify existing `TeamProfile` behavior or ordinary team configuration member rules.
- Edit only `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb` for localization source text; do not hand-edit generated localization Dart files.
- Never invoke `flutter test` directly; use `cd client && dart run tool/run_tests.dart <paths/options>`.
- Before completion run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Preserve unrelated worktree changes and commit only files belonging to each task.

---

## File Map

- Modify `client/lib/models/team_generation_settings.dart`: persisted settings, frozen snapshot, normalization, JSON, equality, and snapshot revision inputs.
- Modify `client/test/models/team_generation_settings_test.dart` and `client/test/services/team_generation/team_generation_settings_store_test.dart`: model, snapshot, and persisted-setting coverage.
- Modify `client/lib/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog.dart`: load, edit, validate, and save the minimum member count.
- Modify `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb`: label, hint, and invalid-value copy.
- Modify `client/test/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog_test.dart`: field behavior; retain existing registry coverage.
- Modify `client/lib/services/team_generation/models/generated_team_plan.dart`, `team_generation_context_payload.dart`, and both Team Builder skill sources: remove fixed count bounds and publish the frozen minimum.
- Modify `client/lib/services/team_generation/generated_team_plan_validator.dart`: enforce the frozen minimum.
- Modify `client/test/services/team_generation/team_generation_context_service_test.dart`, `generated_team_plan_test.dart`, `generated_team_plan_validator_test.dart`, and `managed_team_builder_skill_provider_test.dart`: contract and validation coverage.

## Interfaces

- `TeamGenerationSettings.minimumMemberCount: int` — persisted user preference, default `3`, normalized to `>= 3`.
- `TeamGenerationSettingsSnapshot.minimumMemberCount: int` — immutable workflow value, default `3` for old job JSON.
- `teamGenerationContextPayload(job)['constraints']['memberCountMin']` — frozen integer consumed by Team Builder.
- Validator issue code `member_count_below_minimum` — emitted when `plan.members.length < input.settings.minimumMemberCount`.

### Task 1: Persist and Freeze the Minimum Member Count

**Files:**

- Modify: `client/lib/models/team_generation_settings.dart`
- Test: `client/test/models/team_generation_settings_test.dart`
- Test: `client/test/services/team_generation/team_generation_settings_store_test.dart`

**Interfaces:**

- Consumes: existing settings, snapshot, hydration, and snapshot-resolution APIs.
- Produces: `minimumMemberCount` on settings and snapshots, with default/legacy behavior available to the dialog and generation context.

- [ ] **Step 1: Write the failing model and store tests**

Add tests like:

```dart
test('defaults the generated team minimum to three', () {
  expect(TeamGenerationSettings().minimumMemberCount, 3);
  expect(TeamGenerationSettings.fromJson({}).minimumMemberCount, 3);
  expect(TeamGenerationSettings(minimumMemberCount: 2).minimumMemberCount, 3);
});

test('snapshot round-trip preserves and versions the minimum', () {
  final low = resolveTeamGenerationSettingsSnapshot(
    settings: TeamGenerationSettings(minimumMemberCount: 3),
    presets: const [],
    registry: CliToolRegistry.builtIn(),
    capturedAt: 42,
  );
  final high = resolveTeamGenerationSettingsSnapshot(
    settings: TeamGenerationSettings(minimumMemberCount: 8),
    presets: const [],
    registry: CliToolRegistry.builtIn(),
    capturedAt: 42,
  );
  expect(low.minimumMemberCount, 3);
  expect(high.minimumMemberCount, 8);
  expect(TeamGenerationSettingsSnapshot.fromJson(high.toJson()), high);
  expect(high.revision, isNot(low.revision));
});
```

Add a store test that saves `minimumMemberCount: 9`, reloads it, and verifies `9`, plus a legacy JSON load without the field that verifies `3`.

- [ ] **Step 2: Run the focused tests to verify the failure**

Run:

```bash
cd client && dart run tool/run_tests.dart test/models/team_generation_settings_test.dart test/services/team_generation/team_generation_settings_store_test.dart
```

Expected: FAIL because the settings and snapshot types do not yet expose or serialize `minimumMemberCount`.

- [ ] **Step 3: Implement the settings and snapshot field**

In `team_generation_settings.dart`, add a shared default and normalization helper:

```dart
const kDefaultMinimumGeneratedTeamMembers = 3;

int normalizeMinimumGeneratedTeamMembers(int value) =>
    value < kDefaultMinimumGeneratedTeamMembers
        ? kDefaultMinimumGeneratedTeamMembers
        : value;
```

Add `minimumMemberCount` to both settings and snapshot constructors with default 3. Decode it with fallback 3, normalize it in settings `normalized()`, include it in JSON, equality, and hash code, and pass it through `hydrateTeamGenerationSettings`. Include it in the canonical map in `resolveTeamGenerationSettingsSnapshot` so the revision changes when only this setting changes. Keep `schemaVersion` at 1 because the field has a backward-compatible default.

- [ ] **Step 4: Run the focused tests to verify the pass**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit the persistence change**

```bash
git add client/lib/models/team_generation_settings.dart client/test/models/team_generation_settings_test.dart client/test/services/team_generation/team_generation_settings_store_test.dart
git commit -m "feat(team-generation): persist minimum member count"
```

### Task 2: Add the Setting to the Generate-and-Launch Dialog

**Files:**

- Modify: `client/lib/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Modify: `client/test/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog_test.dart`

**Interfaces:**

- Consumes: `TeamGenerationSettings.minimumMemberCount`, `TeamGenerationSettingsStore.load/save`, and Task 1’s normalization constant.
- Produces: a saved minimum value used by the next generation workflow.

- [ ] **Step 1: Write the failing dialog tests**

Extend the existing dialog test fixture using the seeded `HomeStorage`, `AppProviderCubit`, `AiFeatureSettingsCubit`, `CliPresetsCubit`, and `CliToolRegistryScope` pattern. Open the dialog, wait for loading, find `ValueKey('team-generate-minimum-members')`, and cover loading 3, saving 8, and rejecting 2:

```dart
testWidgets('loads three and saves a larger minimum', (tester) async {
  await tester.pumpWidget(buildGenerateSettingsTestHost());
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('team-generate-minimum-members')), findsOneWidget);
  expect(find.text('3'), findsOneWidget);
  await tester.enterText(
    find.byKey(const ValueKey('team-generate-minimum-members')),
    '8',
  );
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
  expect((await testSettingsStore.load()).minimumMemberCount, 8);
});

testWidgets('blocks values below three', (tester) async {
  await tester.pumpWidget(buildGenerateSettingsTestHost());
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('team-generate-minimum-members')),
    '2',
  );
  await tester.pump();
  expect(find.text('Minimum must be at least 3.'), findsOneWidget);
});
```

Use the actual localized English string in assertions; the shown copy is the required `app_en.arb` value.

- [ ] **Step 2: Run the dialog test to verify the failure**

```bash
cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog_test.dart
```

Expected: FAIL because the field, localized keys, and save wiring do not exist.

- [ ] **Step 3: Add localized copy**

Add matching keys near the existing generation settings keys:

```json
"teamGenerateMinimumMemberCount": "Minimum team members",
"teamGenerateMinimumMemberCountHint": "The generated team will include at least this many distinct roles.",
"teamGenerateMinimumMemberCountInvalid": "Minimum must be at least 3."
```

Use equivalent Chinese copy in `app_zh.arb`. Run the configured localization generation as needed, but do not hand-edit generated localization Dart files.

- [ ] **Step 4: Implement load, edit, validation, and save**

Add a text controller or equivalent state to `_GenerateSettingsDialogState`; initialize it from the normalized setting in `_loadInitial` and dispose it. Render a numeric `TextFormField` with key `ValueKey('team-generate-minimum-members')`, label, hint, and `errorText` when the input is empty, non-integer, or below 3. Include the parsed value in `_canSave`; in `_save`, pass the parsed integer as `minimumMemberCount` to `TeamGenerationSettings`. Do not silently clamp invalid UI text on save.

- [ ] **Step 5: Run the dialog test to verify the pass**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 6: Commit the settings UI**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog_test.dart
git commit -m "feat(team-generation): configure minimum generated members"
```

### Task 3: Remove the Fixed Plan Maximum and Publish the Frozen Minimum

**Files:**

- Modify: `client/lib/services/team_generation/models/generated_team_plan.dart`
- Modify: `client/lib/services/team_generation/team_generation_context_payload.dart`
- Modify: `client/lib/services/team_generation/providers/team_builder_skill_md.dart`
- Modify: `client/lib/services/team_generation/managed_skills/team-builder/SKILL.md`
- Test: `client/test/services/team_generation/team_generation_context_service_test.dart`
- Test: `client/test/services/team_generation/generated_team_plan_test.dart`
- Test: `client/test/services/team_generation/managed_team_builder_skill_provider_test.dart`

**Interfaces:**

- Consumes: `TeamGenerationSettingsSnapshot.minimumMemberCount` from Task 1.
- Produces: context `constraints.memberCountMin`, a schema with no fixed member maximum, and synchronized Builder instructions.

- [ ] **Step 1: Write failing contract tests**

Use a job snapshot with `minimumMemberCount: 8` and assert:

```dart
final constraints = structured['constraints'] as Map;
expect(constraints['memberCountMin'], 8);
expect(constraints.containsKey('memberCountMax'), isFalse);
```

Update the plan contract test to parse a six-member plan successfully; semantic minimum enforcement remains in Task 4. Preserve the source/disk byte-identical assertion and add checks that both Builder sources mention `memberCountMin` and do not mention `memberCountMax` or `2–5`/`2-5`.

- [ ] **Step 2: Run focused contract tests to verify the failure**

```bash
cd client && dart run tool/run_tests.dart test/services/team_generation/team_generation_context_service_test.dart test/services/team_generation/generated_team_plan_test.dart test/services/team_generation/managed_team_builder_skill_provider_test.dart
```

Expected: FAIL because the context and schema still expose the old fixed bounds and the Builder text still says `2–5`.

- [ ] **Step 3: Implement the context, schema, and skill changes**

Remove the fixed `memberCount: {min: 2, max: 5}` entry from `GeneratedTeamPlan.wireSchema`. In `teamGenerationContextPayload`, publish:

```dart
'constraints': {
  'leadMemberName': TeamMemberNaming.teamLeadName,
  'memberCountMin': job.settings.minimumMemberCount,
  'replicasMin': 1,
  'replicasMax': 8,
  'leadReplicas': 1,
},
```

Update both Builder sources so the roster must have at least the frozen `constraints.memberCountMin` distinct roles, exactly one leader, and no hardcoded maximum. Keep the two files byte-identical through the existing provider test.

- [ ] **Step 4: Run focused contract tests to verify the pass**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit the protocol contract change**

```bash
git add client/lib/services/team_generation/models/generated_team_plan.dart client/lib/services/team_generation/team_generation_context_payload.dart client/lib/services/team_generation/providers/team_builder_skill_md.dart client/lib/services/team_generation/managed_skills/team-builder/SKILL.md client/test/services/team_generation/team_generation_context_service_test.dart client/test/services/team_generation/generated_team_plan_test.dart client/test/services/team_generation/managed_team_builder_skill_provider_test.dart
git commit -m "feat(team-generation): publish configurable member minimum"
```

### Task 4: Enforce the Frozen Minimum in Plan Validation

**Files:**

- Modify: `client/lib/services/team_generation/generated_team_plan_validator.dart`
- Test: `client/test/services/team_generation/generated_team_plan_validator_test.dart`

**Interfaces:**

- Consumes: `GeneratedTeamValidationInput.settings.minimumMemberCount` and plan member entries.
- Produces: `member_count_below_minimum` issue code and acceptance of valid plans with more than five entries.

- [ ] **Step 1: Write failing validator tests**

Make the test input helper accept `minimumMemberCount`, then add:

```dart
test('rejects a plan below the frozen minimum', () async {
  final result = await validator.validate(
    input: input(minimumMemberCount: 4),
    planJson: planJson(memberCount: 3),
  );
  expect(result.isValid, isFalse);
  expect(result.issueCodes, contains('member_count_below_minimum'));
  expect(result.issueCodes, isNot(contains('member_count_out_of_range')));
});

test('accepts a valid plan with more than five member entries', () async {
  final result = await validator.validate(
    input: input(minimumMemberCount: 3),
    planJson: planJson(memberCount: 6),
  );
  expect(result.isValid, isTrue);
  expect(result.roster, hasLength(6));
});
```

Replace the old “requires 2-5 roles” test with a duplicate-lead test that proves six distinct roles are not rejected solely for count.

- [ ] **Step 2: Run the validator test to verify the failure**

```bash
cd client && dart run tool/run_tests.dart test/services/team_generation/generated_team_plan_validator_test.dart
```

Expected: FAIL because the validator still requires 2–5 entries and does not use the frozen minimum.

- [ ] **Step 3: Implement the semantic count check**

Replace the fixed block:

```dart
if (plan.members.length < 2 || plan.members.length > 5) {
  issues.add(_error('member_count_out_of_range'));
}
```

with:

```dart
if (plan.members.length < frozen.minimumMemberCount) {
  issues.add(
    _error(
      'member_count_below_minimum',
      detail: '\${plan.members.length} < \${frozen.minimumMemberCount}',
    ),
  );
}
```

Keep leader, unique ID, role, replicas, placement, resource, and workspace checks unchanged; do not add a replacement maximum.

- [ ] **Step 4: Run the validator test to verify the pass**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit validation behavior**

```bash
git add client/lib/services/team_generation/generated_team_plan_validator.dart client/test/services/team_generation/generated_team_plan_validator_test.dart
git commit -m "feat(team-generation): enforce frozen minimum roster size"
```

### Task 5: Full Verification and Review

**Files:**

- Verify all files changed in Tasks 1–4; no new production files are required.

**Interfaces:**

- Consumes: all persisted settings, UI, context, skill, and validator changes.
- Produces: evidence that old settings/jobs remain readable and plans support arbitrary member counts above the configured minimum.

- [ ] **Step 1: Run all focused generation and UI tests**

```bash
cd client && dart run tool/run_tests.dart \
  test/models/team_generation_settings_test.dart \
  test/services/team_generation/team_generation_settings_store_test.dart \
  test/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog_test.dart \
  test/services/team_generation/generated_team_plan_test.dart \
  test/services/team_generation/generated_team_plan_validator_test.dart \
  test/services/team_generation/team_generation_context_service_test.dart \
  test/services/team_generation/managed_team_builder_skill_provider_test.dart
```

Expected: all selected tests pass.

- [ ] **Step 2: Run static analysis**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no analyzer errors or warnings introduced by this change.

- [ ] **Step 3: Run the complete repository test suite**

```bash
cd client && dart run tool/run_tests.dart
```

Expected: the complete suite exits successfully. Do not run another test process concurrently.

- [ ] **Step 4: Inspect the final diff and worktree**

```bash
git diff --check
git status --short
```

Confirm no generated localization Dart files were hand-edited and unrelated pre-existing changes remain untouched.
