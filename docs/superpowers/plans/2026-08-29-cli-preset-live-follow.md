# CLI Preset Live-Follow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sessions that still hang a CLI preset (`presetId` set) re-expand live provider/model/effort on reconnect; editing an existing preset locks CLI (create can still set CLI).

**Architecture:** Keep `presetId` as the follow switch. Simple reconnect already calls `enrichSimpleLaunchIdentityFromPreset` — stop treating pinned provider/model as frozen. Team reconnect already looks up the live preset, then `applySessionContinueOverrides` overwrites it with the create-time snapshot — skip that overwrite when following and the live preset still exists. A pure follow-sync helper dirty-checks field equality (not timestamps) and `SessionShellConnector` persists + updates the in-memory snapshot. Cubit + edit dialog refuse CLI changes on update.

**Tech Stack:** Flutter, `flutter_bloc`, existing `CliPreset` / `AppSession` / `SessionRepository`.

**Spec:** `docs/superpowers/specs/2026-08-29-cli-preset-live-follow-design.md`

## Global Constraints

- Applies to every launchable CLI (`claude` / `flashskyai` / `codex` / `opencode` / `cursor`) — no `if (cli == …)` branches
- Analyze: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
- Tests: `cd client && dart run tool/run_tests.dart <path>` (optional `--plain-name=`)
- l10n: none expected; do not add keys unless a task shows arb entries
- Follow vs detach is `presetId` empty/non-empty — no new session fields, no timestamp comparison
- Running PTYs are not hot-reloaded
- `updatePreset` keeps its `cli` parameter for call-site compatibility but must not write it

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/cubits/cli_presets_cubit.dart` | Ignore `cli` on `updatePreset` |
| `client/lib/pages/home_workspace/workspace/config/cli_preset_edit_dialog.dart` | Disable CLI dropdown when `isEditing` |
| `client/lib/utils/workspace/landing_draft_resolver.dart` | Live-expand following Simple identities |
| `client/lib/models/simple_launch_identity.dart` | Comments: follow, do not re-fetch only when detached |
| `client/lib/services/session/session_continue_overrides_apply.dart` | Team: skip snapshot stamp when following a live preset |
| `client/lib/services/session/session_preset_follow_sync.dart` | **Create.** Pure dirty-check: return patched `AppSession` or null |
| `client/lib/services/launch/session_shell_connector.dart` | Persist patched session + cubit/tab snapshot after prepare |
| Tests listed per task | TDD first |

---

### Task 1: `updatePreset` cannot change CLI

**Files:**
- Modify: `client/lib/cubits/cli_presets_cubit.dart` (`updatePreset`)
- Test: `client/test/cubits/cli_presets_cubit_test.dart`

**Interfaces:**
- Consumes: `CliPresetsCubit.updatePreset({required String id, required String name, required CliTool cli, required String provider, required String model, String effort = ''})`
- Produces: same signature; persisted `CliPreset.cli` stays the value from `addPreset` / existing row

- [ ] **Step 1: Write the failing test**

In `cli_presets_cubit_test.dart`, change `updatePreset modifies an existing preset` so CLI must stay `claude`, and add a focused case:

```dart
  test('updatePreset modifies an existing preset', () async {
    await cubit.load();
    await cubit.addPreset(
      name: 'Old',
      cli: CliTool.claude,
      provider: 'p',
      model: 'm',
    );
    final id = cubit.state.presets.first.id;

    await cubit.updatePreset(
      id: id,
      name: 'Updated',
      cli: CliTool.flashskyai,
      provider: 'p2',
      model: 'm2',
      effort: 'low',
    );

    final updated = cubit.state.presets.first;
    expect(updated.name, 'Updated');
    expect(updated.cli, CliTool.claude);
    expect(updated.provider, 'p2');
    expect(updated.model, 'm2');
    expect(updated.effort, 'low');
  });

  test('updatePreset ignores cli argument', () async {
    await cubit.load();
    await cubit.addPreset(
      name: 'Cursor',
      cli: CliTool.cursor,
      provider: 'cursor-account',
      model: 'composer-2.5',
    );
    final id = cubit.state.presets.first.id;

    await cubit.updatePreset(
      id: id,
      name: 'Cursor',
      cli: CliTool.codex,
      provider: 'other-account',
      model: 'gpt-5',
    );

    expect(cubit.state.presets.single.cli, CliTool.cursor);
    expect(cubit.state.presets.single.provider, 'other-account');
    expect(cubit.state.presets.single.model, 'gpt-5');
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/cli_presets_cubit_test.dart --plain-name="updatePreset ignores cli argument"`

Expected: FAIL — `cli` is `codex` (or `flashskyai` on the renamed test)

- [ ] **Step 3: Write minimal implementation**

In `updatePreset`, stop copying `cli`:

```dart
    next[index] = next[index].copyWith(
      name: trimmedName,
      provider: provider.trim(),
      model: model.trim(),
      effort: effort.trim(),
      updatedAt: now,
    );
```

Leave the `cli` parameter on the method so `CliPresetEditDialog` / onboarding still compile.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/cli_presets_cubit_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/cli_presets_cubit.dart client/test/cubits/cli_presets_cubit_test.dart
git commit -m "$(cat <<'EOF'
fix: keep CLI frozen when updating an existing preset

EOF
)"
```

---

### Task 2: Edit-preset dialog locks the CLI dropdown

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/config/cli_preset_edit_dialog.dart`
- Test: `client/test/pages/home_workspace/workspace/config/cli_preset_edit_dialog_test.dart`

**Interfaces:**
- Consumes: `CliPresetEditDialog.isEditing` (`existing != null`)
- Produces: CLI `TpSelect` `key: Key('preset-cli-select')`; `enabled: lockCli == null && !isEditing`

- [ ] **Step 1: Write the failing tests**

Append to `cli_preset_edit_dialog_test.dart`:

```dart
  testWidgets('edit dialog disables CLI select; add dialog leaves it enabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpManageDialog(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final editCli = tester.widget<TpSelect<String>>(
      find.byKey(const Key('preset-cli-select')),
    );
    expect(editCli.enabled, isFalse);
    expect(editCli.initialItem, CliTool.claude.value);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.tap(find.widgetWithText(TextButton, l10n.cancel).last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(OutlinedButton, l10n.workspaceCliAddPresetTitle),
    );
    await tester.pumpAndSettle();

    final addCli = tester.widget<TpSelect<String>>(
      find.byKey(const Key('preset-cli-select')),
    );
    expect(addCli.enabled, isTrue);
  });
```

Also assert provider select stays enabled while editing:

```dart
  testWidgets('edit dialog keeps provider select enabled', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpManageDialog(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final providerField = tester.widget<TpSelectFormField<String>>(
      find.byKey(const ValueKey('preset-provider-form-claude')),
    );
    expect(providerField.enabled, isNot(false));
  });
```

If `TpSelectFormField` has no `enabled` getter, skip the second test and only lock CLI.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/config/cli_preset_edit_dialog_test.dart --plain-name="edit dialog disables CLI select"`

Expected: FAIL — `Key('preset-cli-select')` not found, or `enabled` is true on edit

- [ ] **Step 3: Write minimal implementation**

On the CLI `TpSelect<String>` in `cli_preset_edit_dialog.dart`:

```dart
                trailing: TpSelect<String>(
                  key: const Key('preset-cli-select'),
                  items: [for (final def in registry.launchable) def.id.value],
                  initialItem: _cli.value,
                  decoration: dropdownDeco,
                  enabled: widget.lockCli == null && !widget.isEditing,
                  onChanged: (value) {
                    if (value == null ||
                        widget.lockCli != null ||
                        widget.isEditing) {
                      return;
                    }
                    setState(() {
                      _cli = CliTool.decode(value);
                      _providerId = '';
                      _modelId = '';
                      _effortId = '';
                    });
                  },
```

Do not disable the provider `TpSelectFormField`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/config/cli_preset_edit_dialog_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/config/cli_preset_edit_dialog.dart \
  client/test/pages/home_workspace/workspace/config/cli_preset_edit_dialog_test.dart
git commit -m "$(cat <<'EOF'
fix: disable CLI picker when editing an existing preset

EOF
)"
```

---

### Task 3: Simple reconnect re-expands a followed preset

**Files:**
- Modify: `client/lib/utils/workspace/landing_draft_resolver.dart` (`enrichSimpleLaunchIdentityFromPreset`)
- Modify: `client/lib/models/simple_launch_identity.dart` (class / `presetId` comments)
- Test: `client/test/utils/workspace/landing_draft_resolver_test.dart`

**Interfaces:**
- Consumes: `SimpleLaunchIdentity.presetId`, `presetById`, `identity.cli`
- Produces: `enrichSimpleLaunchIdentityFromPreset` always copies live provider/model/effort when `presetId` is set, the preset exists, and `preset.cli == identity.cli`; otherwise returns `identity` unchanged (including pinned provider/model)

- [ ] **Step 1: Write the failing tests**

Replace `keeps session-pinned provider and model when already set` and add missing/mismatch cases in the existing `enrichSimpleLaunchIdentityFromPreset` group:

```dart
    test('following identity takes live preset provider and model', () {
      const identity = SimpleLaunchIdentity(
        cli: CliTool.cursor,
        presetId: 'cursor-composer',
        provider: 'old-account',
        model: 'old-model',
        effort: 'low',
      );

      final enriched = enrichSimpleLaunchIdentityFromPreset(
        identity: identity,
        presets: presets,
      );

      expect(enriched.provider, 'cursor-account');
      expect(enriched.model, 'composer-2.5');
      expect(enriched.effort, '');
      expect(enriched.cli, CliTool.cursor);
      expect(enriched.presetId, 'cursor-composer');
    });

    test('missing preset keeps pinned provider and model', () {
      const identity = SimpleLaunchIdentity(
        cli: CliTool.cursor,
        presetId: 'gone',
        provider: 'old-account',
        model: 'old-model',
      );

      final enriched = enrichSimpleLaunchIdentityFromPreset(
        identity: identity,
        presets: presets,
      );

      expect(enriched.provider, 'old-account');
      expect(enriched.model, 'old-model');
      expect(enriched.presetId, 'gone');
    });

    test('preset CLI mismatch keeps pinned launch fields', () {
      const identity = SimpleLaunchIdentity(
        cli: CliTool.codex,
        presetId: 'cursor-composer',
        provider: 'openai',
        model: 'gpt',
      );

      final enriched = enrichSimpleLaunchIdentityFromPreset(
        identity: identity,
        presets: presets,
      );

      expect(enriched.cli, CliTool.codex);
      expect(enriched.provider, 'openai');
      expect(enriched.model, 'gpt');
    });

    test('empty presetId does not expand', () {
      const identity = SimpleLaunchIdentity(
        cli: CliTool.cursor,
        provider: 'pinned',
        model: 'pinned-m',
      );

      final enriched = enrichSimpleLaunchIdentityFromPreset(
        identity: identity,
        presets: presets,
      );

      expect(enriched.provider, 'pinned');
      expect(enriched.model, 'pinned-m');
    });
```

Keep `expands presetId-only identity into model and provider`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/utils/workspace/landing_draft_resolver_test.dart --plain-name="following identity takes live preset"`

Expected: FAIL — still returns `old-account`

- [ ] **Step 3: Write minimal implementation**

Replace `enrichSimpleLaunchIdentityFromPreset` and its doc comment:

```dart
/// Expands [identity.presetId] into provider/model/effort when the session
/// still follows that preset.
///
/// Following = non-empty [SimpleLaunchIdentity.presetId]. Detached Custom
/// rows have an empty presetId and are returned unchanged. If the preset is
/// missing or its CLI does not match [identity.cli], pinned fields are kept.
SimpleLaunchIdentity enrichSimpleLaunchIdentityFromPreset({
  required SimpleLaunchIdentity identity,
  required List<CliPreset> presets,
}) {
  final presetId = identity.presetId.trim();
  if (presetId.isEmpty) return identity;
  final preset = presetById(presetId, presets);
  if (preset == null) return identity;
  if (preset.cli != identity.cli) return identity;
  return SimpleLaunchIdentity.resolve(
    preset: preset,
    presetId: presetId,
    cli: identity.cli,
    expertKey: identity.expertKey,
    officialProviderId: _officialProviderId,
  );
}
```

`SimpleLaunchIdentity.resolve` already prefers `preset.provider/model/effort` and `cli: identity.cli` keeps the session lock. Confirm `resolve` uses `preset?.cli ?? cli` for `resolvedCli` — pass `cli: identity.cli` **and** the preset; if `resolve` would switch CLI to `preset.cli`, force the result:

After resolve, if needed:

```dart
  final resolved = SimpleLaunchIdentity.resolve(
    preset: preset,
    presetId: presetId,
    cli: identity.cli,
    expertKey: identity.expertKey,
    officialProviderId: _officialProviderId,
  );
  return resolved.copyWith(cli: identity.cli);
```

Always `copyWith(cli: identity.cli)` so a followed preset cannot change session CLI.

Update comments on `SimpleLaunchIdentity`:

```dart
/// Denormalized Simple (unteamed) launch identity.
///
/// Persisted on [AppSession]. Create resolves once. Reconnect re-expands
/// provider/model/effort from the global preset when [presetId] is non-empty
/// (see [enrichSimpleLaunchIdentityFromPreset]). Empty [presetId] means the
/// session was detached via Custom continue chrome and must keep these fields.
```

And `presetId`:

```dart
  /// Follow switch and provenance. Non-empty: reconnect expands this preset.
  /// Empty: detached Custom launch; do not re-fetch a global preset.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/utils/workspace/landing_draft_resolver_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/utils/workspace/landing_draft_resolver.dart \
  client/lib/models/simple_launch_identity.dart \
  client/test/utils/workspace/landing_draft_resolver_test.dart
git commit -m "$(cat <<'EOF'
fix: re-expand followed Simple preset provider on reconnect

EOF
)"
```

---

### Task 4: Team continue overrides skip snapshot when following a live preset

**Files:**
- Modify: `client/lib/services/session/session_continue_overrides_apply.dart`
- Test: `client/test/services/session/session_continue_overrides_apply_test.dart`
- Test: `client/test/services/session/session_continue_overrides_launch_test.dart`

**Interfaces:**
- Consumes: `finalizeSessionLaunchMember.preset` (already the live `CliPreset?`)
- Produces: `applySessionContinueOverrides(..., {CliPreset? livePreset})`  
  Following = `memberOverride.presetId` non-empty **and** `livePreset != null` **and** `livePreset.id == presetId` **and** `livePreset.cli == baseMember.cli`. Then: do not stamp snapshot provider/model/effort; set `activePresetId` to that preset id; still merge security policy.  
  Otherwise keep today's snapshot stamp (detached or deleted preset), including clearing `activePresetId` when concrete fields are applied.

- [ ] **Step 1: Write the failing tests**

In `session_continue_overrides_apply_test.dart`:

Rename the existing team merge test comment to say it is the **deleted-preset / no livePreset** fallback (snapshot wins). Keep expectations (`provider: 'new'`, `activePresetId` null) when `livePreset` is omitted.

Add:

```dart
  test(
    'team follow with live preset keeps withPreset fields and activePresetId',
    () {
      const live = CliPreset(
        id: 'p1',
        name: 'Live',
        cli: CliTool.claude,
        provider: 'live-provider',
        model: 'live-model',
        effort: 'low',
        createdAt: 1,
        updatedAt: 2,
      );
      const base = TeamMemberConfig(
        id: 'builder-0',
        name: 'Builder',
        cli: CliTool.claude,
        provider: 'live-provider',
        model: 'live-model',
        effort: 'low',
        launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
      );
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        sessionTeam: 'team',
        createdAt: 1,
        continueOverrides: const SessionContinueOverrides(
          memberOverrides: {
            'builder-0': SessionMemberContinueOverride(
              presetId: 'p1',
              provider: 'stale-provider',
              model: 'stale-model',
              effort: 'high',
            ),
          },
        ),
      );
      final out = applySessionContinueOverrides(
        baseMember: base,
        session: session,
        memberId: 'builder-0',
        isSimple: false,
        livePreset: live,
      );
      expect(out.provider, 'live-provider');
      expect(out.model, 'live-model');
      expect(out.effort, 'low');
      expect(out.activePresetId, 'p1');
      expect(out.cli, CliTool.claude);
    },
  );

  test('team follow CLI mismatch still stamps snapshot', () {
    const live = CliPreset(
      id: 'p1',
      name: 'Live',
      cli: CliTool.cursor,
      provider: 'cursor-account',
      model: 'composer-2.5',
      createdAt: 1,
      updatedAt: 2,
    );
    const base = TeamMemberConfig(
      id: 'builder-0',
      name: 'Builder',
      cli: CliTool.claude,
      provider: 'keep',
      model: 'keep-m',
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team',
      createdAt: 1,
      continueOverrides: const SessionContinueOverrides(
        memberOverrides: {
          'builder-0': SessionMemberContinueOverride(
            presetId: 'p1',
            provider: 'snap',
            model: 'snap-m',
          ),
        },
      ),
    );
    final out = applySessionContinueOverrides(
      baseMember: base,
      session: session,
      memberId: 'builder-0',
      isSimple: false,
      livePreset: live,
    );
    expect(out.provider, 'snap');
    expect(out.model, 'snap-m');
    expect(out.activePresetId, isNull);
    expect(out.cli, CliTool.claude);
  });
```

In `session_continue_overrides_launch_test.dart`, change `finalize then memberForLaunch keeps continue provider (team staging)`:

That session has `presetId: 'p-template'` **and** a live `preset` passed into `finalizeSessionLaunchMember`. New expectation: live preset wins (`preset-provider` / `preset-model`), `activePresetId == 'p-template'`. Remove the "buggy memberForLaunch expands template" assertion that treated follow as a bug.

Keep `shell launch member: continue overrides win over template preset` — that override has **no** `presetId` (detached). It must still expect `override-provider`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/session/session_continue_overrides_apply_test.dart --plain-name="team follow with live preset"`

Expected: FAIL — `provider` is `stale-provider` (named arg `livePreset` may also be a compile error until Step 3)

- [ ] **Step 3: Write minimal implementation**

Add optional `livePreset` and pass it from `finalizeSessionLaunchMember`:

```dart
  var merged = applySessionContinueOverrides(
    baseMember: afterPreset,
    session: session,
    memberId: memberId,
    isSimple: isSimple,
    livePreset: isSimple ? null : preset,
  );
```

In `applySessionContinueOverrides`, after `memberOverride == null` / policy merge, before stamping concrete fields:

```dart
  final followId = memberOverride.presetId?.trim() ?? '';
  final liveId = livePreset?.id.trim() ?? '';
  final following = followId.isNotEmpty &&
      livePreset != null &&
      liveId == followId &&
      livePreset.cli == baseMember.cli;

  if (following) {
    return merged.copyWith(
      activePresetId: followId,
      updateActivePresetId: true,
    );
  }
```

Then the existing concrete-field stamp + `activePresetId: null` path. Never change `baseMember.cli`.

Update the doc comment on `applySessionContinueOverrides`: following live preset skips snapshot provider/model/effort; detached / missing preset still stamps.

Need `import` for `CliPreset` — already present.

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd client && dart run tool/run_tests.dart \
  test/services/session/session_continue_overrides_apply_test.dart \
  test/services/session/session_continue_overrides_launch_test.dart
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/session/session_continue_overrides_apply.dart \
  client/test/services/session/session_continue_overrides_apply_test.dart \
  client/test/services/session/session_continue_overrides_launch_test.dart
git commit -m "$(cat <<'EOF'
fix: team reconnect follows live preset instead of launch snapshot

EOF
)"
```

---

### Task 5: Pure follow-sync dirty check

**Files:**
- Create: `client/lib/services/session/session_preset_follow_sync.dart`
- Create: `client/test/services/session/session_preset_follow_sync_test.dart`

**Interfaces:**
- Consumes: `enrichSimpleLaunchIdentityFromPreset`, `presetById`
- Produces:

```dart
AppSession? staleFollowingSimpleSession({
  required AppSession session,
  required List<CliPreset> presets,
});

AppSession? staleFollowingTeamSession({
  required AppSession session,
  required String memberId,
  required List<CliPreset> presets,
  CliTool? lockedCli,
});
```

Return `null` when not following, preset missing, CLI mismatch, or provider/model/effort already match. Otherwise return `session.copyWith` of only those launch fields (Simple: top-level; Team: that member's `SessionMemberContinueOverride`, keep `presetId` and security policy).

- [ ] **Step 1: Write the failing tests**

`session_preset_follow_sync_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/session/session_preset_follow_sync.dart';

void main() {
  const cursorPreset = CliPreset(
    id: 'p-cursor',
    name: 'Cursor',
    cli: CliTool.cursor,
    provider: 'new-account',
    model: 'composer-2.5',
    effort: 'high',
    createdAt: 1,
    updatedAt: 9,
  );

  test('simple stale following session is patched', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      cli: CliTool.cursor,
      presetId: 'p-cursor',
      provider: 'old-account',
      model: 'old-model',
      effort: 'low',
      createdAt: 1,
    );
    final patched = staleFollowingSimpleSession(
      session: session,
      presets: const [cursorPreset],
    );
    expect(patched, isNotNull);
    expect(patched!.provider, 'new-account');
    expect(patched.model, 'composer-2.5');
    expect(patched.effort, 'high');
    expect(patched.presetId, 'p-cursor');
    expect(patched.cli, CliTool.cursor);
  });

  test('simple matching fields returns null', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      cli: CliTool.cursor,
      presetId: 'p-cursor',
      provider: 'new-account',
      model: 'composer-2.5',
      effort: 'high',
      createdAt: 1,
    );
    expect(
      staleFollowingSimpleSession(
        session: session,
        presets: const [cursorPreset],
      ),
      isNull,
    );
  });

  test('simple detached (empty presetId) returns null', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      cli: CliTool.cursor,
      provider: 'old-account',
      model: 'old-model',
      createdAt: 1,
    );
    expect(
      staleFollowingSimpleSession(
        session: session,
        presets: const [cursorPreset],
      ),
      isNull,
    );
  });

  test('team stale following member override is patched', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team',
      createdAt: 1,
      continueOverrides: const SessionContinueOverrides(
        memberOverrides: {
          'builder-0': SessionMemberContinueOverride(
            presetId: 'p-cursor',
            provider: 'old-account',
            model: 'old-model',
            effort: 'low',
          ),
        },
      ),
    );
    final patched = staleFollowingTeamSession(
      session: session,
      memberId: 'builder-0',
      presets: const [cursorPreset],
      lockedCli: CliTool.cursor,
    );
    expect(patched, isNotNull);
    final override =
        patched!.continueOverrides.memberOverrides['builder-0']!;
    expect(override.presetId, 'p-cursor');
    expect(override.provider, 'new-account');
    expect(override.model, 'composer-2.5');
    expect(override.effort, 'high');
  });

  test('team matching override returns null', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team',
      createdAt: 1,
      continueOverrides: const SessionContinueOverrides(
        memberOverrides: {
          'builder-0': SessionMemberContinueOverride(
            presetId: 'p-cursor',
            provider: 'new-account',
            model: 'composer-2.5',
            effort: 'high',
          ),
        },
      ),
    );
    expect(
      staleFollowingTeamSession(
        session: session,
        memberId: 'builder-0',
        presets: const [cursorPreset],
        lockedCli: CliTool.cursor,
      ),
      isNull,
    );
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/session/session_preset_follow_sync_test.dart`

Expected: FAIL — library not found

- [ ] **Step 3: Write minimal implementation**

Create `session_preset_follow_sync.dart`:

```dart
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/session_continue_overrides.dart';
import '../../models/team_config.dart';
import '../../utils/workspace/landing_draft_resolver.dart';
import '../cli/preset_resolver.dart';

AppSession? staleFollowingSimpleSession({
  required AppSession session,
  required List<CliPreset> presets,
}) {
  if (!session.isSimple) return null;
  final identity = enrichSimpleLaunchIdentityFromPreset(
    identity: session.simpleIdentity,
    presets: presets,
  );
  if (identity.provider == session.provider &&
      identity.model == session.model &&
      identity.effort == session.effort) {
    return null;
  }
  return session.copyWith(
    provider: identity.provider,
    model: identity.model,
    effort: identity.effort,
  );
}

AppSession? staleFollowingTeamSession({
  required AppSession session,
  required String memberId,
  required List<CliPreset> presets,
  CliTool? lockedCli,
}) {
  if (session.isSimple) return null;
  final id = memberId.trim();
  if (id.isEmpty) return null;
  final existing = session.continueOverrides.memberOverrides[id];
  final presetId = existing?.presetId?.trim() ?? '';
  if (existing == null || presetId.isEmpty) return null;
  final preset = presetById(presetId, presets);
  if (preset == null) return null;
  if (lockedCli != null && preset.cli != lockedCli) return null;

  final provider = preset.provider.trim();
  final model = preset.model.trim();
  final effort = preset.effort.trim();
  if ((existing.provider ?? '') == provider &&
      (existing.model ?? '') == model &&
      (existing.effort ?? '') == effort) {
    return null;
  }

  final members = Map<String, SessionMemberContinueOverride>.from(
    session.continueOverrides.memberOverrides,
  );
  members[id] = existing.copyWith(
    provider: provider,
    model: model,
    effort: effort.isEmpty ? null : effort,
  );
  return session.copyWith(
    continueOverrides: session.continueOverrides.copyWith(
      memberOverrides: members,
    ),
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/session/session_preset_follow_sync_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/session/session_preset_follow_sync.dart \
  client/test/services/session/session_preset_follow_sync_test.dart
git commit -m "$(cat <<'EOF'
feat: dirty-check followed preset fields against live CliPreset

EOF
)"
```

---

### Task 6: Persist follow-sync on connect

**Files:**
- Modify: `client/lib/services/launch/session_shell_connector.dart`
- Test: `client/test/services/session/session_preset_follow_sync_test.dart` (add persist helper tests if you extract persist; otherwise connector-only wiring — keep persist in connector using existing `SessionRepository` methods already covered by repo tests)

**Interfaces:**
- Consumes: `staleFollowingSimpleSession`, `staleFollowingTeamSession`, `_host.lifecycle.globalPresets`, `_host.sessionRepository`, `_host.replaceSessionSnapshot`, `SessionContinueOverridesController.mergeOntoTabCache`
- Produces: after `prepareSimpleConnect` / `prepareTeamConnect` succeeds, if helper returns a patched session: persist (`updateSimpleLaunchIdentity` or `updateContinueOverrides`), `replaceSessionSnapshot`, merge onto `tab.persistedSession`

- [ ] **Step 1: Add a connector-free persist helper test (optional but preferred)**

If adding persist into `session_preset_follow_sync.dart` pulls `SessionRepository` into a unit that should stay pure, **do not**. Instead add a small function in the same file:

```dart
Future<void> persistFollowedSession({
  required SessionRepository repo,
  required AppSession patched,
  required bool isSimple,
}) {
  if (isSimple) {
    return repo.updateSimpleLaunchIdentity(
      patched.sessionId,
      provider: patched.provider,
      model: patched.model,
      effort: patched.effort,
    );
  }
  return repo.updateContinueOverrides(
    patched.sessionId,
    patched.continueOverrides,
  );
}
```

Skip a new repo integration test unless one already uses `setUpTestAppStorage` nearby; `updateSimpleLaunchIdentity` is already tested in repository tests. Task 5's dirty-check is the behavior gate.

- [ ] **Step 2: Wire `SessionShellConnector`**

Add a private method and call it once Simple prepare returns and once Team prepare returns (after `connectResult` is assigned, while `activeSession` / `tab` are still valid):

```dart
  Future<AppSession> _syncFollowedPresetOnConnect({
    required AppSession session,
    required ChatTab tab,
    required bool isPersonal,
    required String memberId,
    CliTool? lockedCli,
  }) async {
    final presets = _host.lifecycle.globalPresets;
    final patched = isPersonal
        ? staleFollowingSimpleSession(session: session, presets: presets)
        : staleFollowingTeamSession(
            session: session,
            memberId: memberId,
            presets: presets,
            lockedCli: lockedCli,
          );
    if (patched == null) return session;
    final repo = _host.sessionRepository;
    if (repo != null) {
      await persistFollowedSession(
        repo: repo,
        patched: patched,
        isSimple: isPersonal,
      );
    }
    if (_host.isClosed) return patched;
    _host.replaceSessionSnapshot(patched);
    final cached = tab.persistedSession;
    if (cached != null && cached.sessionId == patched.sessionId) {
      tab.persistedSession =
          SessionContinueOverridesController.mergeOntoTabCache(
            cached: cached,
            patched: patched,
          );
    }
    return patched;
  }
```

Imports:

```dart
import '../session/session_preset_follow_sync.dart';
import '../../cubits/chat/session_continue_overrides_controller.dart';
```

Call sites:

- Personal: after `prepareSimpleConnect` returns, `activeSession = await _syncFollowedPresetOnConnect(session: activeSession, tab: tab, isPersonal: true, memberId: activeSession.sessionId);`  
  (`launchCli` already came from `simpleIdentity.cli` — CLI is unchanged.)
- Team: after `prepareTeamConnect` returns, pass `memberId: preflightMemberId` and `lockedCli: launchCli`.

Do not rebuild `ShellLaunchSpec`; orchestrator already launched with live fields from Tasks 3–4. This write-back is for continue-chrome / next disk read.

- [ ] **Step 3: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no new issues in touched files

- [ ] **Step 4: Run related tests**

Run:

```bash
cd client && dart run tool/run_tests.dart \
  test/services/session/session_preset_follow_sync_test.dart \
  test/services/session/session_continue_overrides_apply_test.dart \
  test/utils/workspace/landing_draft_resolver_test.dart \
  test/cubits/cli_presets_cubit_test.dart \
  test/pages/home_workspace/workspace/config/cli_preset_edit_dialog_test.dart \
  test/services/session/session_continue_overrides_launch_test.dart
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/launch/session_shell_connector.dart \
  client/lib/services/session/session_preset_follow_sync.dart
git commit -m "$(cat <<'EOF'
fix: persist followed preset launch fields on session connect

EOF
)"
```

---

### Task 7: Spec status + full gate

**Files:**
- Modify: `docs/superpowers/specs/2026-08-29-cli-preset-live-follow-design.md` (status line only)

- [ ] **Step 1: Mark spec confirmed**

Change `状态：待确认` to `状态：已确认`.

- [ ] **Step 2: Full analyze + targeted tests**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Run the test command from Task 6 Step 4.

Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-08-29-cli-preset-live-follow-design.md
git commit -m "$(cat <<'EOF'
docs: mark CLI preset live-follow spec confirmed

EOF
)"
```

---

## Spec coverage

| Spec rule | Task |
|-----------|------|
| All launch CLIs, no CLI branches | 3–6 (shared helpers) |
| Follow = non-empty `presetId` | 3, 4, 5 |
| Detach = Custom clears `presetId` | 3, 5 (null path); continue chrome already clears |
| Edit locks CLI; create does not | 1, 2 |
| Provider/model/effort editable | 1, 2 (unchanged fields) |
| Simple live expand on reconnect | 3 (`prepareSimpleConnect` already calls enrich) |
| Team snapshot must not cover live preset | 4 |
| Deleted preset keeps pinned | 3, 4 |
| CLI mismatch does not follow | 3, 4, 5 |
| Dirty check by field equality | 5 |
| Persist on connect, not full-library sweep | 6 |
| No timestamp LWW / no running-PTY hot swap / no resume UX | omitted |

## Out of scope (do not implement)

- Restart dialogs when a preset is saved
- Locking provider on edit
- Per-CLI resume failure UX
- Team Custom four-tuple
