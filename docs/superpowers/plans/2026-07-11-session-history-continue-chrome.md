# Session History Continue Chrome Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add session-scoped permission and same-CLI model/preset continue chrome on History review, persist overrides on `AppSession`, apply them on every connect via one merge function, and make Landing permission real.

**Architecture:** Introduce `SessionContinueOverrides` on `AppSession`. Chip edits and Landing create write concrete bools / same-CLI preset fields. `applySessionContinueOverrides` is the only merge entry point used by lifecycle connect. History gets a continue toolbar (identity read-only, model, permission, team settings); Landing shares chip widgets and writes session-level permission at create.

**Tech Stack:** Flutter, `flutter_bloc`, existing `AppSession` / `SessionRepository` / `SessionLifecycleService` / compose chip patterns from `WorkspaceChatLanding`.

**Spec:** `docs/superpowers/specs/2026-07-11-session-history-continue-chrome-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/session_continue_overrides.dart` | `SessionContinueOverrides`, `SessionMemberContinueOverride` JSON models |
| `client/lib/models/app_session.dart` | Own `continueOverrides`; copyWith / JSON |
| `client/lib/services/session/session_continue_overrides_apply.dart` | Pure merge + effective permission resolution |
| `client/lib/repositories/session_repository.dart` | Persist continue overrides + Simple identity patch |
| `client/lib/cubits/chat_cubit.dart` (or thin helper under `cubits/chat/`) | Snapshot update + repo call for UI |
| `client/lib/services/session/session_lifecycle_service.dart` | Call merge after base member resolve |
| `client/lib/models/landing_launch_context.dart` | `dangerouslySkipPermissions` on draft |
| `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart` | Wire permission into draft + create |
| `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` | Pass permission into createSession path |
| `client/lib/widgets/compose/compose_permission_chip.dart` | Shared permission menu chip |
| `client/lib/widgets/compose/compose_model_preset_chip.dart` | Shared same-CLI preset chip |
| `client/lib/pages/chat/session_review_compose_card.dart` | Continue toolbar slot |
| `client/lib/pages/chat/session_history_review.dart` | Own chip state, persist, pass specs |
| `client/test/models/session_continue_overrides_test.dart` | JSON round-trip |
| `client/test/services/session/session_continue_overrides_apply_test.dart` | Merge / permission chain |
| `client/test/repositories/session_continue_overrides_persist_test.dart` | Repo persist (use test AppStorage harness) |

---

### Task 1: `SessionContinueOverrides` model + `AppSession` field

**Files:**
- Create: `client/lib/models/session_continue_overrides.dart`
- Modify: `client/lib/models/app_session.dart`
- Test: `client/test/models/session_continue_overrides_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_continue_overrides.dart';

void main() {
  test('SessionContinueOverrides round-trips JSON', () {
    const o = SessionContinueOverrides(
      dangerouslySkipPermissions: true,
      memberOverrides: {
        'builder-0': SessionMemberContinueOverride(
          presetId: 'p1',
          provider: 'anthropic',
          model: 'claude',
          effort: 'high',
          dangerouslySkipPermissions: false,
        ),
      },
    );
    final back = SessionContinueOverrides.fromJson(o.toJson());
    expect(back.dangerouslySkipPermissions, isTrue);
    expect(back.memberOverrides['builder-0']?.presetId, 'p1');
    expect(back.memberOverrides['builder-0']?.dangerouslySkipPermissions, isFalse);
  });

  test('empty / missing JSON is unset', () {
    expect(
      SessionContinueOverrides.fromJson(null).dangerouslySkipPermissions,
      isNull,
    );
    expect(SessionContinueOverrides.fromJson(const {}).memberOverrides, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/session_continue_overrides_test.dart`
Expected: FAIL (library missing)

- [ ] **Step 3: Implement models + wire `AppSession`**

`session_continue_overrides.dart`:

```dart
@immutable
class SessionMemberContinueOverride {
  const SessionMemberContinueOverride({
    this.presetId,
    this.provider,
    this.model,
    this.effort,
    this.dangerouslySkipPermissions,
  });
  final String? presetId;
  final String? provider;
  final String? model;
  final String? effort;
  final bool? dangerouslySkipPermissions;
  // fromJson / toJson / == / hashCode / copyWith — omit empty strings
}

@immutable
class SessionContinueOverrides {
  const SessionContinueOverrides({
    this.dangerouslySkipPermissions,
    this.memberOverrides = const {},
  });
  final bool? dangerouslySkipPermissions;
  final Map<String, SessionMemberContinueOverride> memberOverrides;
  // fromJson accepts Map? or null → empty; toJson omits nulls / empty map
}
```

On `AppSession`: add `continueOverrides` (default `const SessionContinueOverrides()`), include in `fromJson` / `toJson` / `copyWith` / `==` / `hashCode`. Key name: `continueOverrides`.

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/models/session_continue_overrides_test.dart`
Expected: PASS

Also run any existing `app_session` JSON tests if present; fix equality breakages.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/session_continue_overrides.dart \
  client/lib/models/app_session.dart \
  client/test/models/session_continue_overrides_test.dart
git commit -m "$(cat <<'EOF'
feat(session): add SessionContinueOverrides on AppSession

EOF
)"
```

---

### Task 2: Pure merge + permission resolution

**Files:**
- Create: `client/lib/services/session/session_continue_overrides_apply.dart`
- Test: `client/test/services/session/session_continue_overrides_apply_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
test('permission: member > session > launchDefault', () {
  expect(
    resolveContinueSkipPermissions(
      sessionLevel: true,
      memberLevel: false,
      launchDefault: true,
    ),
    isFalse,
  );
  expect(
    resolveContinueSkipPermissions(
      sessionLevel: true,
      memberLevel: null,
      launchDefault: false,
    ),
    isTrue,
  );
  expect(
    resolveContinueSkipPermissions(
      sessionLevel: null,
      memberLevel: null,
      launchDefault: true,
    ),
    isTrue,
  );
});

test('team merge applies provider/model/effort/preset and permission; CLI unchanged', () {
  const base = TeamMemberConfig(
    id: 'builder-0',
    name: 'Builder',
    cli: CliTool.claude,
    provider: 'old',
    model: 'old-m',
    dangerouslySkipPermissions: true,
  );
  final session = AppSession(
    sessionId: 's1',
    workspaceId: 'w1',
    sessionTeam: 'team',
    createdAt: 1,
    continueOverrides: const SessionContinueOverrides(
      dangerouslySkipPermissions: true,
      memberOverrides: {
        'builder-0': SessionMemberContinueOverride(
          presetId: 'p1',
          provider: 'new',
          model: 'new-m',
          effort: 'high',
          dangerouslySkipPermissions: false,
        ),
      },
    ),
  );
  final out = applySessionContinueOverrides(
    baseMember: base,
    session: session,
    memberId: 'builder-0',
    isSimple: false,
  );
  expect(out.cli, CliTool.claude);
  expect(out.provider, 'new');
  expect(out.model, 'new-m');
  expect(out.effort, 'high');
  expect(out.activePresetId, 'p1'); // or whatever field TeamMemberConfig uses
  expect(out.dangerouslySkipPermissions, isFalse);
});

test('simple merge applies session-level permission only; keeps base provider/model', () {
  // Simple identity already on base from session.cli/provider/model;
  // merge sets dangerouslySkipPermissions from session continueOverrides.
});

test('other member overrides do not affect this member', () { /* ... */ });
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `cd client && flutter test test/services/session/session_continue_overrides_apply_test.dart`

- [ ] **Step 3: Implement**

```dart
bool resolveContinueSkipPermissions({
  required bool? sessionLevel,
  required bool? memberLevel,
  required bool launchDefault,
}) =>
    memberLevel ?? sessionLevel ?? launchDefault;

/// [isSimple]: launchDefault for permission is `false`.
/// Team: launchDefault is [baseMember.dangerouslySkipPermissions] **before**
/// override (template / already staged value).
///
/// Simple: do **not** re-apply provider/model from memberOverrides (unused);
/// those live on AppSession identity and must already be on [baseMember].
/// Only permission (and any future session-level fields) come from continueOverrides.
///
/// Team: apply memberOverrides[memberId] provider/model/effort/presetId + permission.
/// Never change [baseMember.cli].
TeamMemberConfig applySessionContinueOverrides({
  required TeamMemberConfig baseMember,
  required AppSession session,
  required String memberId,
  required bool isSimple,
}) { /* ... */ }
```

Map Team `presetId` onto `TeamMemberConfig.activePresetId` (confirm field name in `team_config.dart`).

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/session/session_continue_overrides_apply.dart \
  client/test/services/session/session_continue_overrides_apply_test.dart
git commit -m "$(cat <<'EOF'
feat(session): apply continue overrides in pure merge

EOF
)"
```

---

### Task 3: Repository persist APIs

**Files:**
- Modify: `client/lib/repositories/session_repository.dart`
- Test: `client/test/repositories/session_continue_overrides_persist_test.dart` (follow existing session repo test harness / `setUpTestAppStorage`)

- [ ] **Step 1: Write failing persist tests**

Cover:
1. `updateContinueOverrides(sessionId, overrides)` round-trip on disk
2. `updateSimpleLaunchIdentity(sessionId, {presetId, provider, model, effort})` updates those fields without clearing `continueOverrides`
3. Unknown sessionId throws / no-ops per existing repo conventions

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

Add methods that `_read` session → `copyWith` → `_writeSession`. Do not invent a second storage file.

Also extend `createSession` to accept optional `SessionContinueOverrides? continueOverrides` (or `bool? dangerouslySkipPermissions` that builds overrides) so Landing can set session-level permission at create.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(session): persist continue overrides and simple identity patches

EOF
)"
```

---

### Task 4: Wire merge into every connect path

**Files:**
- Modify: `client/lib/services/session/session_lifecycle_service.dart` (and/or `session_runtime_plan_builder.dart` / connect orchestrator — **one choke point only**)
- Test: extend or add `client/test/services/session/session_continue_overrides_launch_test.dart` with mocked presets / minimal session

**Rule:** After base `TeamMemberConfig` is resolved (`memberForLaunch` / simple `plan.member` from session identity), call `applySessionContinueOverrides` before env/CLI args use `dangerouslySkipPermissions` or provider/model.

- [ ] **Step 1: Locate the single best insertion point**

Prefer applying once where both Simple and Team produce the final `launchMember` / `memberForLaunch` (near `_prepareLaunchPlanFromRuntimePlan` or plan builder). Document the chosen call site in a one-line comment: `// session continue overrides (History / Landing permission)`.

For Simple base member construction: ensure `provider`/`model`/`effort`/`cli` come from `AppSession` **before** merge; merge then applies permission from `continueOverrides`.

For Team: `memberId` = roster instance id (`memberBinding.rosterMemberId`).

- [ ] **Step 2: Write a focused test** that builds a session with member override and asserts the staged launch member’s provider/permission after the resolve helper (extract a package-visible helper if lifecycle is hard to unit-test).

- [ ] **Step 3: Implement wiring**

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/services/session/session_continue_overrides_apply_test.dart test/services/session/session_continue_overrides_launch_test.dart`

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(session): apply continue overrides on connect launch path

EOF
)"
```

---

### Task 5: Landing permission → create session

**Files:**
- Modify: `client/lib/models/landing_launch_context.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` (+ any `SessionPersistParams` / create request types)
- Modify: `client/lib/cubits/chat/session_launch_service.dart` / `session_persist_params.dart` as needed
- Test: unit test that draft → create params include `continueOverrides.dangerouslySkipPermissions`

- [ ] **Step 1: Add `bool dangerouslySkipPermissions` to `LandingLaunchContext`** (concrete; default `false`). Include in `copyWith` / `==` / draft persist JSON if drafts are persisted — **permission should be part of draft persistence** so Landing remount restores chip.

- [ ] **Step 2: Wire `_permissionMode` → draft**

```dart
// default → false, fullAccess → true
dangerouslySkipPermissions:
  _permissionMode == _LandingPermissionMode.fullAccess,
```

Include in `_currentDraft()`. On draft restore, set `_permissionMode` from draft bool.

- [ ] **Step 3: Thread into `createSession`**

`submitWorkspaceLandingMessage` / persist params → `createSession(..., continueOverrides: SessionContinueOverrides(dangerouslySkipPermissions: draft.dangerouslySkipPermissions))`.

Do **not** fan out into `memberOverrides` at create.

- [ ] **Step 4: Test** Landing draft / create params carry the bool; Simple create with `true` → session JSON has `continueOverrides.dangerouslySkipPermissions: true`.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(landing): persist permission chip into session continue overrides

EOF
)"
```

---

### Task 6: Shared compose chips

**Files:**
- Create: `client/lib/widgets/compose/compose_permission_chip.dart`
- Create: `client/lib/widgets/compose/compose_model_preset_chip.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_landing_compose_card.dart` (and/or landing) to use shared chips where practical
- Optional test: smoke widget test for menu specs

**Behavior:**
- Permission: two specs — default / full access; `selected` from effective bool; `onSelected` returns concrete bool (not null).
- Model preset: takes `List<CliPreset> sameCliPresets`, selected id, labels; optional “manage presets” action. **Caller filters with `presetsForCli`.**

- [ ] **Step 1: Extract widgets** matching existing `_ToolbarMenuChip` / `SidebarActionMenuSpec` visuals from landing compose card (reuse palette).

- [ ] **Step 2: Switch Landing to shared permission chip** (behavior unchanged except draft wiring from Task 5).

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
refactor(compose): extract shared permission and model preset chips

EOF
)"
```

---

### Task 7: ChatCubit / UI persist helpers

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart` or add `client/lib/cubits/chat/session_continue_overrides_controller.dart`
- Test: cubit/unit test with fake repo

API sketch:

```dart
Future<void> setSessionContinuePermission({
  required String sessionId,
  required bool dangerouslySkipPermissions,
  String? memberId, // null → session-level (Simple / Landing); non-null → Team member
});

Future<void> setSessionContinuePreset({
  required String sessionId,
  required CliPreset preset,
  String? memberId, // Simple: null → update AppSession identity fields; Team: member override
  required CliTool lockedCli,
});
```

**Cross-CLI guard:** if `preset.cli != lockedCli` → do not write; throw or return false for UI toast.

Team preset select **expands** `provider`/`model`/`effort`/`presetId` into `SessionMemberContinueOverride` (same fields Simple writes onto `AppSession`).

Update in-memory session snapshot the same way other session patches do.

- [ ] **Step 1: Failing tests** for same-CLI write, cross-CLI reject, Team member isolation

- [ ] **Step 2: Implement**

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(chat): session continue override update APIs

EOF
)"
```

---

### Task 8: History continue chrome UI

**Files:**
- Modify: `client/lib/pages/chat/session_review_compose_card.dart`
- Modify: `client/lib/pages/chat/session_history_review.dart`
- Modify: `client/lib/pages/chat_workbench.dart` if team settings / session snapshot callbacks need plumbing
- l10n: `client/lib/l10n/app_en.arb`, `app_zh.arb` only if new strings needed (prefer reuse landing strings)

- [ ] **Step 1: Extend `SessionReviewComposeCard`** with optional continue toolbar:

  - read-only identity label
  - model preset chip
  - permission chip
  - optional team settings button (reuse landing gear pattern)

- [ ] **Step 2: In `SessionHistoryReview`**

  - Resolve `isSimple`, locked CLI (`session.cli` / member launch CLI), effective permission via `resolveContinueSkipPermissions`
  - Simple model chip: `presetsForCli(presets, lockedCli)`; selection updates via cubit (`setSessionContinuePreset` with `memberId: null`)
  - Team: same filter for **selected member** CLI; write member override; show team name read-only; wire `onTeamSettings` to existing team settings dialog (same as landing — edits template)
  - Expert / team identity: read-only label only
  - On persist failure: toast + revert local chip selection

- [ ] **Step 3: Manual checklist** (document in commit body): no project/worktree/mode/expert edit controls appear

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(history): add continue chrome for permission and same-CLI presets

EOF
)"
```

---

### Task 9: End-to-end / acceptance tests

**Files:**
- Test: `client/test/pages/chat/session_history_continue_chrome_test.dart` (and/or service-level acceptance tests)

Cover acceptance from spec:

1. Simple preset change persists and merge sees new provider/model  
2. Team member override does not mutate team template object  
3. Permission full access → effective skip true on merge  
4. Cross-CLI preset rejected  
5. Landing create permission → session-level → History effective display / merge for **unedited** team member uses session default (not template) when session-level set  
6. Member switch uses that member’s override map entry  

Prefer pure/service tests over full widget pumps where faster; add one widget test that continue chips are present and mode/project chips are absent.

- [ ] **Step 1: Write tests**

- [ ] **Step 2: Run**

```bash
cd client && flutter test \
  test/models/session_continue_overrides_test.dart \
  test/services/session/session_continue_overrides_apply_test.dart \
  test/services/session/session_continue_overrides_launch_test.dart \
  test/repositories/session_continue_overrides_persist_test.dart \
  test/pages/chat/session_history_continue_chrome_test.dart
```

- [ ] **Step 3: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
test(session): cover history continue chrome acceptance paths

EOF
)"
```

---

### Task 10: Spec status + History Review cross-check

**Files:**
- Modify: `docs/superpowers/specs/2026-07-11-session-history-continue-chrome-design.md` → Status: Implemented (when done)
- Verify: `docs/superpowers/specs/2026-07-10-session-history-review-design.md` already points at continue chrome (done in design phase)

- [ ] **Step 1: Mark design Implemented** after Task 9 green

- [ ] **Step 2: Commit**

```bash
git commit -m "$(cat <<'EOF'
docs: mark session history continue chrome implemented

EOF
)"
```

---

## Execution notes

- **TDD:** each task writes failing tests first.
- **No backward-compat shims** for old Landing UI-only permission.
- **CLI lock:** UI filters + cubit reject; merge never changes `cli`.
- **Running PTY:** overrides apply on next connect only (existing disconnect → review → edit → submit).
- After implementation: prefer `subagent-driven-development` for task-by-task execution.
