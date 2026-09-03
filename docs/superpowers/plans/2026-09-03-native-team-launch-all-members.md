# Native Team Launch All Members Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native teams always launch every valid member shell on Connect and Restart; the `autoLaunchAllMembersOnConnect` preference applies to mixed teams only.

**Architecture:** Add a pure predicate `shouldLaunchAllMembers` in `session_launch_pipeline.dart` and swap the four existing `autoLaunchAllMembersOnConnect` / `teamMode == mixed` gates in the launch layer to use it. No new services, no state-model changes; per-member failure isolation already exists in `SessionMemberConnectScheduler`.

**Tech Stack:** Flutter / Dart, `flutter_bloc`, existing launch-layer classes (`SessionLaunchPipeline`, `SessionLaunchService`, `SessionDefaultMaterializer`). Spec: `docs/superpowers/specs/2026-09-03-native-team-launch-all-members-design.md`.

## Global Constraints

- Follow AGENTS.md: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart` before claiming done.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only (arb edits regenerate `app_localizations*.dart`).
- `TeamProfile.teamMode` defaults to `TeamMode.native` (`client/lib/models/team_config.dart:342`) — a `TeamProfile` without explicit `teamMode` in tests is native.
- `TeamMemberConfig.isValid` is `name.trim().isNotEmpty` (`client/lib/models/team_config.dart:202`).
- Do not change `_runOpenMemberTab` semantics (explicit single-member entry point).
- Do not change the default value of `autoLaunchAllMembersOnConnect` in `session_preferences.dart` (stays `false`).
- Test runner: `cd client && dart run tool/run_tests.dart <path>` (or `--plain-name="…"`).

---

### Task 1: `shouldLaunchAllMembers` predicate (TDD)

**Files:**
- Modify: `client/lib/services/launch/session_launch_pipeline.dart` (add function near `shouldSerializeConnect` at bottom of file)
- Test: `client/test/services/launch/session_launch_pipeline_all_members_test.dart` (new file)

**Interfaces:**
- Consumes: `TeamProfile` (`teamMode`), `TeamMode` from `package:teampilot/models/team_config.dart`.
- Produces:
  ```dart
  @visibleForTesting
  bool shouldLaunchAllMembers({
    required TeamProfile team,
    required bool autoLaunchAllMembersOnConnect,
  })
  ```
  Used by Tasks 2 and 3.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/launch/session_launch_pipeline_all_members_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/launch/session_launch_pipeline.dart';

void main() {
  TeamProfile team(TeamMode mode) => TeamProfile(
    id: 'team-1',
    name: 'Team',
    members: const [
      TeamMemberConfig(id: 'team-lead', name: 'Lead'),
      TeamMemberConfig(id: 'builder', name: 'Builder'),
    ],
    cli: CliTool.claude,
    teamMode: mode,
  );

  group('shouldLaunchAllMembers', () {
    test('native team launches all members regardless of preference', () {
      expect(
        shouldLaunchAllMembers(
          team: team(TeamMode.native),
          autoLaunchAllMembersOnConnect: false,
        ),
        isTrue,
        reason: 'native teams break when members are missing',
      );
      expect(
        shouldLaunchAllMembers(
          team: team(TeamMode.native),
          autoLaunchAllMembersOnConnect: true,
        ),
        isTrue,
      );
    });

    test('mixed team honors the preference', () {
      expect(
        shouldLaunchAllMembers(
          team: team(TeamMode.mixed),
          autoLaunchAllMembersOnConnect: true,
        ),
        isTrue,
      );
      expect(
        shouldLaunchAllMembers(
          team: team(TeamMode.mixed),
          autoLaunchAllMembersOnConnect: false,
        ),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/session_launch_pipeline_all_members_test.dart`
Expected: FAIL — `shouldLaunchAllMembers` is not defined (compile error).

- [ ] **Step 3: Write minimal implementation**

In `client/lib/services/launch/session_launch_pipeline.dart`, after the `shouldSerializeConnect` function at the bottom of the file, add:

```dart
/// Whether connecting this team must launch every valid member shell.
///
/// Native teams break when any member is missing (the CLI coordinates the
/// roster itself), so they always launch all members regardless of the
/// user preference. Mixed teams honor [autoLaunchAllMembersOnConnect].
@visibleForTesting
bool shouldLaunchAllMembers({
  required TeamProfile team,
  required bool autoLaunchAllMembersOnConnect,
}) => team.teamMode != TeamMode.mixed || autoLaunchAllMembersOnConnect;
```

(`package:flutter/foundation.dart` is already imported — `shouldSerializeConnect` uses `@visibleForTesting`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/session_launch_pipeline_all_members_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/launch/session_launch_pipeline.dart client/test/services/launch/session_launch_pipeline_all_members_test.dart
git commit -m "Add shouldLaunchAllMembers predicate for native team full launch"
```

---

### Task 2: Gate the pipeline on the predicate (connect, restart, post-materialize)

**Files:**
- Modify: `client/lib/services/launch/session_launch_pipeline.dart` — `_connectTeamSession` (~line 548), `_restartTeamSession` (~line 584), `_runLaunchAllMembers` mixed branch (~line 396)
- Test: `client/test/services/launch/session_launch_pipeline_all_members_test.dart` (extend)

**Interfaces:**
- Consumes: `shouldLaunchAllMembers` from Task 1.
- Produces: behavior — `TeamSessionConnect`/`RestartWorkspaceOperation` with a native team routes through `_runLaunchAllMembers`; `_runLaunchAllMembers` schedules `_scheduleMemberConnect` per valid member for both modes.

- [ ] **Step 1: Write the failing test**

Extend `client/test/services/launch/session_launch_pipeline_all_members_test.dart`. Model the harness on `session_launch_pipeline_stable_task_id_test.dart` (which builds a `SessionLaunchPipeline` with fake host/tabStore and a `scheduleMemberConnect` no-op — see its `_pipelineForStaging` around line 300). Add inside `main()`:

```dart
  group('native team connect schedules every valid member', () {
    test('TeamSessionConnect with pref off still launches all members',
        () async {
      final tabStore = ChatTabStore()..setActiveWorkspaceId('ws-1');
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/proj')],
        createdAt: 1,
        updatedAt: 1,
      );
      final nativeTeam = TeamProfile(
        id: 'team-1',
        name: 'Team',
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'Lead'),
          TeamMemberConfig(id: 'builder', name: 'Builder'),
        ],
        cli: CliTool.claude,
      );
      final scheduled = <String>[];

      final pipeline = _pipelineForAllMembers(
        tabStore: tabStore,
        workspace: workspace,
        team: nativeTeam,
        autoLaunchAllMembersOnConnect: () => false,
        onScheduleMemberConnect: (member) => scheduled.add(member.id),
      );

      await pipeline.run(
        ConnectWorkspaceOperation(TeamSessionConnect(nativeTeam)),
      );

      expect(scheduled, containsAll(['team-lead', 'builder']),
          reason: 'native connect must schedule every valid member');
    });

    test('mixed team with pref off schedules only via single-member path',
        () async {
      final mixedTeam = TeamProfile(
        id: 'team-1',
        name: 'Team',
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'Lead'),
          TeamMemberConfig(id: 'builder', name: 'Builder'),
        ],
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
      );
      final scheduled = <String>[];

      final pipeline = _pipelineForAllMembers(
        tabStore: ChatTabStore()..setActiveWorkspaceId('ws-1'),
        workspace: Workspace(
          workspaceId: 'ws-1',
          folders: const [WorkspaceFolder(path: '/proj')],
          createdAt: 1,
          updatedAt: 1,
        ),
        team: mixedTeam,
        autoLaunchAllMembersOnConnect: () => false,
        onScheduleMemberConnect: (member) => scheduled.add(member.id),
      );

      await pipeline.run(
        ConnectWorkspaceOperation(TeamSessionConnect(mixedTeam)),
      );

      expect(scheduled, isNot(contains('builder')),
          reason: 'mixed pref-off starts only the selected member');
    });
  });
```

Add the helper below `main()` in the same test file. It mirrors `_pipelineForStaging` from `session_launch_pipeline_stable_task_id_test.dart` (fake host, fake tab surface, fake materializer, captured `scheduleMemberConnect`); copy the fake classes from that file — `_CapturingHost`, `_StubTabSurface`/equivalents, `_StubMaterializer` — and adapt the constructor:

```dart
SessionLaunchPipeline _pipelineForAllMembers({
  required ChatTabStore tabStore,
  required Workspace workspace,
  required TeamProfile team,
  required bool Function() autoLaunchAllMembersOnConnect,
  required void Function(TeamMemberConfig member) onScheduleMemberConnect,
}) {
  // Build host/tabSurface/materializer fakes exactly as
  // _pipelineForStaging does in session_launch_pipeline_stable_task_id_test.dart,
  // then:
  return SessionLaunchPipeline(
    host: host,
    tabStore: tabStore,
    state: () => host.state,
    workspaceIndex: () => SessionLaunchWorkspaceIndex(
      workspaces: host.state.workspaces,
      sessions: host.state.sessions,
    ),
    tabSurface: tabSurface,
    materializer: materializer,
    scheduleMemberConnect: (t, member, tab) =>
        onScheduleMemberConnect(member),
    disconnectSession: () {},
    ensureSession: (_) => null,
    appendLocalTab: (_, {required emitChange}) =>
        throw UnsupportedError('unused'),
    ensureActiveSessionTab: (_, {required emitChange}) =>
        throw UnsupportedError('unused'),
    resetTeamConfigValidationSurface: () {},
    scheduleTeamConfigValidation: (_) async {},
    activeTab: () => host.activeTab,
    autoLaunchAllMembersOnConnect: autoLaunchAllMembersOnConnect,
    uuid: const Uuid(),
  );
}
```

Note: with `activeTabsIsEmpty` false (register a session tab for the team first, as `session_launch_pipeline_stable_task_id_test.dart` line ~120 does via `tabStore.registerSession`), `_runLaunchAllMembers` takes the bottom path `_ensureActiveSessionTab` + per-member scheduling — no repository/materialize needed. If the fake host's `ensureActiveSessionTab` throws as above, instead register a real `ChatTab` for the team in the tabStore so the pipeline uses it; check which path `_runLaunchAllMembers` takes (`session_launch_pipeline.dart:386`) and set up the tabStore accordingly.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/session_launch_pipeline_all_members_test.dart`
Expected: the native test FAILS (`scheduled` empty — only selected member started), mixed test PASSes.

- [ ] **Step 3: Implement the gate changes**

In `client/lib/services/launch/session_launch_pipeline.dart`:

1. `_connectTeamSession` (~548) — replace the gate:

```dart
    if (shouldLaunchAllMembers(
      team: team,
      autoLaunchAllMembersOnConnect: _autoLaunchAllMembersOnConnect(),
    )) {
```

2. `_restartTeamSession` (~584) — same replacement.

3. `_runLaunchAllMembers` (~396) — change the post-materialize branch from `if (team.teamMode == TeamMode.mixed)` to an unconditional schedule (this branch only runs on the all-members path, so no extra gate is needed):

```dart
        if (_host.isClosed) return LaunchCompleted();
        final tab = _activeTab();
        if (tab != null) {
          for (final member in validMembers) {
            _scheduleMemberConnect(team, member, tab);
          }
        }
```

(Delete the `team.teamMode == TeamMode.mixed` condition around it; the `_runOpenMemberTab` mixed check at line 357 stays as-is.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/session_launch_pipeline_all_members_test.dart`
Expected: all PASS.

- [ ] **Step 5: Run the full launch-layer test suite for regressions**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/`
Expected: PASS. If `session_launch_pipeline_stable_task_id_test.dart` or other suites fail because native teams now schedule all members, update their expectations to match the new behavior (the pipeline is constructed there with `autoLaunchAllMembersOnConnect: () => false`, which no longer suppresses native full launch).

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/launch/session_launch_pipeline.dart client/test/services/launch/session_launch_pipeline_all_members_test.dart
git commit -m "Gate native team connect/restart on shouldLaunchAllMembers"
```

---

### Task 3: Unconditional chained fallback in `SessionLaunchService`

**Files:**
- Modify: `client/lib/cubits/chat/session_launch_service.dart:415-420` (`_scheduleShellConnect` attach callback)
- Test: existing suites in `client/test/cubits/chat_cubit_session_launch_test.dart` and `client/test/cubits/chat_cubit_test.dart` (they construct `ChatCubit` with `autoLaunchAllMembersOnConnect`); adjust expectations where they assume native single-member behavior with pref off.

**Interfaces:**
- Consumes: `shouldLaunchAllMembers` from Task 1 (import from `package:teampilot/services/launch/session_launch_pipeline.dart` — check existing imports in `session_launch_service.dart`; it already imports launch-layer files).
- Produces: behavior — after the first member shell attaches for a native team, `_launchRemainingMembersForTab` runs regardless of preference.

- [ ] **Step 1: Locate the assertion surface**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat_cubit_session_launch_test.dart test/cubits/chat_cubit_test.dart`
Expected: PASS before the change (baseline). Note which tests construct a **native** team and assert only one member shell connects — those are the ones to update.

- [ ] **Step 2: Write the failing test (extend if none covers it)**

If no existing test exercises `_launchRemainingMembersForTab` for a native team with pref off, add one to `client/test/cubits/chat_cubit_session_launch_test.dart` modeled on its existing native-team connect tests (see the file's harness around line 251, `autoLaunchAllMembersOnConnect: () => true` — clone the nearest native-team connect test, flip the pref to `() => false`, and assert that shells for both members end up running/connected). Assertion shape: after connect settles, every member of the native team has a running shell in `tab.memberShells` (or the harness's equivalent member-started signal).

- [ ] **Step 3: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat_cubit_session_launch_test.dart`
Expected: new test FAILS (only the selected member started).

- [ ] **Step 4: Implement**

In `client/lib/cubits/chat/session_launch_service.dart`, `_scheduleShellConnect` (~415):

```dart
            if (!request.isPersonal &&
                team != null &&
                member != null &&
                shouldLaunchAllMembers(
                  team: team,
                  autoLaunchAllMembersOnConnect:
                      _h.autoLaunchAllMembersOnConnect?.call() == true,
                )) {
              _launchRemainingMembersForTab(team, member.id, tab);
            }
```

(Add the import of `session_launch_pipeline.dart` if not already present.)

- [ ] **Step 5: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat_cubit_session_launch_test.dart test/cubits/chat_cubit_test.dart`
Expected: PASS, with prior native single-member expectations updated to full-launch.

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/chat/session_launch_service.dart client/test/cubits/
git commit -m "Launch remaining native members after first shell attaches"
```

---

### Task 4: Preference copy (l10n) — mixed-only semantics

**Files:**
- Modify: `client/lib/l10n/app_en.arb:1357`, `client/lib/l10n/app_zh.arb:1249`
- Regenerated by arb tooling: `client/lib/l10n/app_localizations*.dart` (do not hand-edit)

**Interfaces:**
- Consumes: existing keys `autoLaunchAllMembersTitle`, `autoLaunchAllMembersDescription` (used by `client/lib/pages/config/session_config_section.dart:248`).
- Produces: updated description strings; no new keys.

- [ ] **Step 1: Update the arb values**

`client/lib/l10n/app_en.arb` — replace the `autoLaunchAllMembersDescription` value:

```json
  "autoLaunchAllMembersDescription": "Mixed teams only: when enabled, Connect and Restart launch every valid member shell; native teams always launch all members.",
```

`client/lib/l10n/app_zh.arb`:

```json
  "autoLaunchAllMembersDescription": "仅对混合团队生效：开启后连接或重启会为每个有效成员启动终端；native 团队始终全员启动。",
```

- [ ] **Step 2: Regenerate localizations and check usages**

Run: `cd client && flutter gen-l10n` (or the repo's standard regen step — check `docs/DEVELOPMENT.md`; if the repo regenerates on `flutter analyze`/build, run that instead). Then:

Run: `cd client && grep -rn "autoLaunchAllMembersDescription" lib/l10n/app_localizations_en.dart`
Expected: the new string appears in generated code.

- [ ] **Step 3: Run tests + analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: PASS (full suite).

- [ ] **Step 4: Commit**

```bash
git add client/lib/l10n/
git commit -m "Narrow autoLaunchAllMembers copy to mixed teams only"
```

---

### Task 5: Full verification

**Files:** none new.

- [ ] **Step 1: Analyze + full test suite**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: clean analyze, all tests PASS.

- [ ] **Step 2: Manual smoke (if a desktop run is available)**

Launch the app (`flutter run -d linux` from `client/`), create/open a native team session, press Connect with the "Start all members on connect" preference OFF, and confirm every member terminal starts. Then toggle the preference ON for a mixed team and confirm it still gates mixed behavior.

- [ ] **Step 3: Final commit if anything remains**

```bash
git status --short
```

Expected: clean tree (all work committed in Tasks 1-4).
