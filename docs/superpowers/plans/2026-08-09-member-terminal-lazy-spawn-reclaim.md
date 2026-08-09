# Member Terminal Lazy Spawn & Idle Reclaim — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lazy-load mixed/team member terminals (spawn on demand) and auto-reclaim idle member terminals (Chrome-style discard) with transparent `--resume` restore, for both team and Simple mode.

**Architecture:** Flip `autoLaunchAllMembersOnConnect` default to `false` so sessions open with only the lead connected. Add a new `PtyClosed` TeamBus event (`running|materializing → declared`, inbox preserved) so the existing materialize funnel re-brings members online. Add a pure `TerminalReclaimPolicy`, a 1-second `TabMemberReclaimWatch` that fires `discardMemberTerminal`, and `ensureMemberTerminalForView` for lazy spawn / tap-to-restore. Reclaim protects the lead, the displayed terminal, and working/unread/connecting members.

**Tech Stack:** Dart/Flutter, `flutter_bloc` cubits, TeamBus state machine (`PresenceReducer`), `flutter_alacritty` terminals, package:test (`@Tags(['integration'])`).

**Spec:** `docs/superpowers/specs/2026-08-09-member-terminal-lazy-spawn-reclaim-design.md`

## Global Constraints

- Repo root is the git root (`/home/hhoa/git/hhoa/teampilot`); app code lives under `client/lib/`; tests under `client/test/`.
- Run `flutter analyze --no-fatal-infos --no-fatal-warnings` and `flutter test --exclude-tags integration` from `client/` before claiming done on a task.
- l10n: user-facing strings go in `client/lib/l10n/app_en.arb` **and** `app_zh.arb` only.
- Logging: diagnostics via `AppLogger` (`appLogger.d` / `appLogger.w`); no `print`.
- No new generic controls under `client/lib/widgets/` — reuse `Tp*` from `shared_ui`.
- `PresenceReducer` stays pure (no IO, no `DateTime.now()` — clock is injected via context/env).
- Integration tests use `@Tags(['integration'])` from `package:test` and `setUpIntegrationAppStorage()` / `tearDownIntegrationAppStorage()` from `test/integration/support/integration_test_setup.dart`.
- Reclaim threshold must be runtime-configurable (`SessionPreferences`) so integration tests can set a few seconds.

---

### Task 1: SessionPreferences — reclaim fields + default flip

**Files:**
- Modify: `client/lib/models/session_preferences.dart`
- Modify: `client/lib/cubits/session_preferences_cubit.dart`
- Test: `client/test/models/session_preferences_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `SessionPreferences.reclaimIdleTerminals` (`bool`, default `true`)
  - `SessionPreferences.reclaimIdleTerminalAfterSeconds` (`int`, default `180`)
  - `SessionPreferences.autoLaunchAllMembersOnConnect` default flips to `false`
  - `SessionPreferencesCubit.setReclaimIdleTerminals(bool)`
  - `SessionPreferencesCubit.setReclaimIdleTerminalAfterMinutes(int)` — clamps to `1..120`, stores `minutes * 60` seconds.

- [ ] **Step 1: Write the failing tests**

Create `client/test/models/session_preferences_test.dart` if it does not exist (check first — if it exists, add to it):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_preferences.dart';

void main() {
  test('reclaim defaults: enabled, 3 minutes; auto-launch all defaults off', () {
    const p = SessionPreferences();
    expect(p.reclaimIdleTerminals, isTrue);
    expect(p.reclaimIdleTerminalAfterSeconds, 180);
    expect(p.autoLaunchAllMembersOnConnect, isFalse);
  });

  test('reclaim fields survive JSON round-trip', () {
    const p = SessionPreferences(
      reclaimIdleTerminals: false,
      reclaimIdleTerminalAfterSeconds: 7,
    );
    final back = SessionPreferences.fromJson(p.toJson());
    expect(back.reclaimIdleTerminals, isFalse);
    expect(back.reclaimIdleTerminalAfterSeconds, 7);
  });

  test('fromJson falls back to defaults for missing reclaim keys', () {
    final p = SessionPreferences.fromJson(const {});
    expect(p.reclaimIdleTerminals, isTrue);
    expect(p.reclaimIdleTerminalAfterSeconds, 180);
  });

  test('copyWith updates reclaim fields', () {
    const p = SessionPreferences();
    final q = p.copyWith(
      reclaimIdleTerminals: false,
      reclaimIdleTerminalAfterSeconds: 12,
    );
    expect(q.reclaimIdleTerminals, isFalse);
    expect(q.reclaimIdleTerminalAfterSeconds, 12);
    // untouched fields keep defaults
    expect(q.autoLaunchAllMembersOnConnect, isFalse);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/models/session_preferences_test.dart`
Expected: compile errors — `reclaimIdleTerminals` / `reclaimIdleTerminalAfterSeconds` do not exist.

- [ ] **Step 3: Implement the preference fields**

In `session_preferences.dart`:
1. Constructor: change `this.autoLaunchAllMembersOnConnect = true` → `= false`; add
   `this.reclaimIdleTerminals = true`, `this.reclaimIdleTerminalAfterSeconds = 180`.
2. `fromJson`: `autoLaunchAllMembersOnConnect: json[...] as bool? ?? false` (was `?? true`); add
   `reclaimIdleTerminals: json['reclaimIdleTerminals'] as bool? ?? true`,
   `reclaimIdleTerminalAfterSeconds: (json['reclaimIdleTerminalAfterSeconds'] as num?)?.toInt() ?? 180`.
3. `copyWith`: add `bool? reclaimIdleTerminals`, `int? reclaimIdleTerminalAfterSeconds` params and wire through.
4. `toJson`: add `'reclaimIdleTerminals': reclaimIdleTerminals`, `'reclaimIdleTerminalAfterSeconds': reclaimIdleTerminalAfterSeconds`.
5. Update the existing `autoLaunchAllMembersOnConnect` doc comment: "When true... Default false (lazy spawn)."

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/models/session_preferences_test.dart`
Expected: PASS.

- [ ] **Step 5: Add cubit setters + tests**

In `session_preferences_cubit.dart` (mirror `setAutoLaunchAllMembersOnConnect` at line 202):

```dart
Future<void> setReclaimIdleTerminals(bool value) {
  return _save(state.preferences.copyWith(reclaimIdleTerminals: value));
}

Future<void> setReclaimIdleTerminalAfterMinutes(int minutes) {
  final clamped = minutes.clamp(1, 120);
  return _save(
    state.preferences.copyWith(
      reclaimIdleTerminalAfterSeconds: clamped * 60,
    ),
  );
}
```

Add a cubit test in the existing `session_preferences_cubit_test.dart` (find it under `client/test/cubits/`) asserting `setReclaimIdleTerminalAfterMinutes(2)` stores `120` and `setReclaimIdleTerminals(false)` flips the flag. Follow the file's existing setUp/`_save` conventions (it likely uses `setUpTestAppStorage()`).

- [ ] **Step 6: Run the cubit tests**

Run: `flutter test test/cubits/session_preferences_cubit_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/models/session_preferences.dart client/lib/cubits/session_preferences_cubit.dart client/test/models/session_preferences_test.dart client/test/cubits/session_preferences_cubit_test.dart
git commit -m "feat(prefs): reclaimIdleTerminals config + lazy-launch-all default"
```

---

### Task 2: TeamBus `PtyClosed` event + `markMemberDiscarded`

**Files:**
- Modify: `client/lib/services/team_bus/state/bus_event.dart`
- Modify: `client/lib/services/team_bus/state/presence_reducer.dart`
- Modify: `client/lib/services/team_bus/team_bus.dart`
- Test: `client/test/services/team_bus/state/presence_reducer_test.dart`
- Test: `client/test/services/team_bus/team_bus_test.dart`

**Interfaces:**
- Consumes: existing `BusEvent` sealed class, `Presence`, `MemberLifecycle`, `MemberActivity`.
- Produces:
  - `class PtyClosed extends BusEvent` (const, no fields).
  - `void TeamBus.markMemberDiscarded(String memberId)` — applies `PtyClosed`, no effect/doorbell.
  - Reducer rule: `running|materializing → declared`, `activity = hasUnread ? mailQueued : none`, inbox untouched.

- [ ] **Step 1: Write the failing reducer tests**

Add to `client/test/services/team_bus/state/presence_reducer_test.dart` (reuse the `_run` helper and `_atPrompt`/`_parked` consts already there):

```dart
group('PtyClosed', () {
  test('running (at prompt) → declared + none, no effect', () {
    final t = _run(_atPrompt, const PtyClosed());
    expect(t.presence.lifecycle, MemberLifecycle.declared);
    expect(t.presence.activity, MemberActivity.none);
    expect(t.effects, isEmpty);
  });

  test('running active → declared + none', () {
    final t = _run(_active, const PtyClosed());
    expect(t.presence.lifecycle, MemberLifecycle.declared);
    expect(t.presence.activity, MemberActivity.none);
  });

  test('materializing → declared', () {
    final t = _run(
      const Presence(MemberLifecycle.materializing, MemberActivity.active),
      const PtyClosed(),
    );
    expect(t.presence.lifecycle, MemberLifecycle.declared);
  });

  test('running + unread → declared + mailQueued (inbox preserved)', () {
    final t = _run(_parked, const PtyClosed(), hasUnread: true);
    expect(t.presence.lifecycle, MemberLifecycle.declared);
    expect(t.presence.activity, MemberActivity.mailQueued);
  });

  test('declared → no change', () {
    expect(_run(_declared, const PtyClosed()).presence, _declared);
  });
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/services/team_bus/state/presence_reducer_test.dart`
Expected: compile error — `PtyClosed` undefined.

- [ ] **Step 3: Add the event + reducer case**

In `bus_event.dart`, after `PtySpawned`:

```dart
/// 空闲回收:PTY 被丢弃(running|materializing → declared)。inbox 保留,消息不丢。
class PtyClosed extends BusEvent {
  const PtyClosed();
}
```

In `presence_reducer.dart`, add before the closing `}` of the `switch`:

```dart
case PtyClosed():
  if (!s.ptyRunning) return _stay(s);
  return _to(
    s.copyWith(
      lifecycle: MemberLifecycle.declared,
      activity: ctx.hasUnread
          ? MemberActivity.mailQueued
          : MemberActivity.none,
    ),
  );
```

- [ ] **Step 4: Run reducer tests to verify they pass**

Run: `flutter test test/services/team_bus/state/presence_reducer_test.dart`
Expected: PASS.

- [ ] **Step 5: Add `markMemberDiscarded` + TeamBus test**

In `team_bus.dart`, next to `markMemberRunning` (line 151):

```dart
/// 空闲回收:PTY 被丢弃 → 复位为 declared(保留 inbox),以便 materialize 漏斗按需重拉。
void markMemberDiscarded(String memberId) {
  final node = _members[memberId];
  if (node == null) return;
  _apply(node, const PtyClosed());
}
```

Add a test in `client/test/services/team_bus/team_bus_test.dart` (follow the file's existing bus-with-fake-launcher setup; if the harness is complex, mirror the pattern from `team_bus_lifecycle_test.dart`):

```dart
test('markMemberDiscarded returns a running member to declared, inbox kept', () async {
  final bus = await newRunningTestBus(); // existing helper, if any
  bus.declareMember(busNodeWithShell(bus, 'm')); // mark running via markMemberRunning
  // seed an unread so we assert inbox is preserved
  await bus.send(const TeamMessage(id: '1', from: 'l', to: 'm', content: 'hi'));
  final node = bus.memberById('m')!;
  expect(node.lifecycle, MemberLifecycle.running);

  bus.markMemberDiscarded('m');

  expect(node.lifecycle, MemberLifecycle.declared);
  expect(await bus.unreadCountFor('m'), 1, reason: 'inbox must survive discard');
  expect(node.activity, MemberActivity.mailQueued);
});
```

If no existing "running bus" helper exists, write the test against a minimal `TeamBus` with a recording `MemberLauncher` fake (the file already has one) and drive `declareMember` → `markMemberRunning` → `markMemberDiscarded`.

- [ ] **Step 6: Run TeamBus tests**

Run: `flutter test test/services/team_bus/team_bus_test.dart test/services/team_bus/state/presence_reducer_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/team_bus/state/bus_event.dart client/lib/services/team_bus/state/presence_reducer.dart client/lib/services/team_bus/team_bus.dart client/test/services/team_bus/state/presence_reducer_test.dart client/test/services/team_bus/team_bus_test.dart
git commit -m "feat(team-bus): PtyClosed event returns running members to declared on reclaim"
```

---

### Task 3: Pure `TerminalReclaimPolicy`

**Files:**
- Create: `client/lib/services/terminal/terminal_reclaim_policy.dart`
- Test: `client/test/services/terminal/terminal_reclaim_policy_test.dart`

**Interfaces:**
- Consumes: nothing app-level (pure Dart).
- Produces:
  - `class TerminalReclaimSnapshot { final String sessionId; final String memberId; final bool shellRunning; final bool shellConnecting; final bool isTeamLead; final bool isDisplayed; final bool inTurn; final bool hasUnread; const TerminalReclaimSnapshot({...}); }`
  - `class TerminalReclaimPolicy { const TerminalReclaimPolicy({required this.idleAfter}); final Duration idleAfter; bool isProtected(TerminalReclaimSnapshot s); bool shouldReclaim(TerminalReclaimSnapshot s, DateTime? idleSince, DateTime now); }`

- [ ] **Step 1: Write the failing tests**

Create `client/test/services/terminal/terminal_reclaim_policy_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_reclaim_policy.dart';

TerminalReclaimSnapshot _snap({
  bool shellRunning = true,
  bool shellConnecting = false,
  bool isTeamLead = false,
  bool isDisplayed = false,
  bool inTurn = false,
  bool hasUnread = false,
}) => TerminalReclaimSnapshot(
  sessionId: 's',
  memberId: 'm',
  shellRunning: shellRunning,
  shellConnecting: shellConnecting,
  isTeamLead: isTeamLead,
  isDisplayed: isDisplayed,
  inTurn: inTurn,
  hasUnread: hasUnread,
);

void main() {
  final policy = TerminalReclaimPolicy(idleAfter: const Duration(minutes: 3));
  final now = DateTime(2026, 8, 9, 12, 0, 0);

  test('reclaimable when idle past threshold and nothing protects', () {
    final idleSince = now.subtract(const Duration(minutes: 4));
    expect(policy.shouldReclaim(_snap(), idleSince, now), isTrue);
  });

  test('not reclaimable before threshold', () {
    final idleSince = now.subtract(const Duration(minutes: 2));
    expect(policy.shouldReclaim(_snap(), idleSince, now), isFalse);
  });

  test('idleSince null means never reclaimable (not yet seeded)', () {
    expect(policy.shouldReclaim(_snap(), null, now), isFalse);
  });

  test('each guard blocks reclaim regardless of idle duration', () {
    final idleSince = now.subtract(const Duration(hours: 1));
    for (final s in [
      _snap(shellConnecting: true),
      _snap(isTeamLead: true),
      _snap(isDisplayed: true),
      _snap(inTurn: true),
      _snap(hasUnread: true),
    ]) {
      expect(policy.shouldReclaim(s, idleSince, now), isFalse,
        reason: 'guard failed for $s');
    }
  });

  test('shell not running is not reclaimable (nothing live to reclaim)', () {
    expect(policy.shouldReclaim(_snap(shellRunning: false), now, now), isFalse);
  });
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/services/terminal/terminal_reclaim_policy_test.dart`
Expected: compile error — files/classes missing.

- [ ] **Step 3: Implement the policy**

Create `client/lib/services/terminal/terminal_reclaim_policy.dart`:

```dart
/// Per-member terminal snapshot the reclaim watch feeds to [TerminalReclaimPolicy].
class TerminalReclaimSnapshot {
  const TerminalReclaimSnapshot({
    required this.sessionId,
    required this.memberId,
    required this.shellRunning,
    required this.shellConnecting,
    required this.isTeamLead,
    required this.isDisplayed,
    required this.inTurn,
    required this.hasUnread,
  });

  final String sessionId;
  final String memberId;
  final bool shellRunning;
  final bool shellConnecting;
  final bool isTeamLead;
  final bool isDisplayed;
  final bool inTurn;
  final bool hasUnread;
}

/// Pure reclaim decision. Single source of truth for the protection set:
/// lead, displayed terminal, working/in-turn, unread, or connecting/pending.
class TerminalReclaimPolicy {
  const TerminalReclaimPolicy({required this.idleAfter});

  final Duration idleAfter;

  bool isProtected(TerminalReclaimSnapshot s) =>
      !s.shellRunning ||
      s.shellConnecting ||
      s.isTeamLead ||
      s.isDisplayed ||
      s.inTurn ||
      s.hasUnread;

  /// true when the member has been idle since [idleSince] for at least
  /// [idleAfter] and no protection guard applies.
  bool shouldReclaim(
    TerminalReclaimSnapshot s,
    DateTime? idleSince,
    DateTime now,
  ) {
    if (isProtected(s)) return false;
    if (idleSince == null) return false;
    return !now.difference(idleSince).isBefore(idleAfter);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/terminal/terminal_reclaim_policy_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/terminal/terminal_reclaim_policy.dart client/test/services/terminal/terminal_reclaim_policy_test.dart
git commit -m "feat(terminal): pure TerminalReclaimPolicy for idle discard guards"
```

---

### Task 4: `ChatTab.reclaimedMemberIds` + `discardMemberTerminal` + `ensureMemberTerminalForView`

**Files:**
- Modify: `client/lib/cubits/chat/model/chat_tab.dart`
- Modify: `client/lib/cubits/chat/session_launch_service.dart`
- Modify: `client/lib/cubits/chat/session_launch_host.dart`
- Test: `client/test/services/launch/session_launch_service_test.dart` (or the existing ChatCubit-level test that covers `disconnectMemberShell` — find it with `grep -rn "disconnectMemberShell" client/test`)

**Interfaces:**
- Consumes:
  - `TeamBus.markMemberDiscarded` (Task 2).
  - `SessionLaunchHost.teamProfileById(String) -> Future<TeamProfile?>` (exists, host line 141).
  - `sessionRosterMembers(session, team)` (exists, `models/app_session.dart`).
  - `SessionMemberConnectScheduler.schedule(team, member, tab)`.
- Produces:
  - `ChatTab.reclaimedMemberIds` — `final Set<String>`.
  - `void SessionLaunchService.discardMemberTerminal(String sessionId, String memberId)` — synchronous.
  - `Future<void> SessionLaunchService.ensureMemberTerminalForView(String sessionId, String memberId)` — mixed/team only; no-op for Simple sessions (Simple restore is the existing connect path).
  - `SessionLaunchService.reclaimedMemberIdsForTab(String sessionId)` (or read `tab.reclaimedMemberIds` directly via `openTabBySessionId` — pick the read used by UI).

- [ ] **Step 1: Add `reclaimedMemberIds` to `ChatTab`**

In `chat_tab.dart`, next to `membersPendingConnect` (line 100):

```dart
/// Members whose live terminal was reclaimed for idle and not yet re-materialized.
final Set<String> reclaimedMemberIds = {};
```

- [ ] **Step 2: Write the failing service test**

Find the existing test covering `disconnectMemberShell` (grep `client/test`). Add a test group there (or create `client/test/cubits/chat/session_launch_service_test.dart` if none exists, mirroring the harness used by `session_idle_busy_integration_test.dart` but at widget-test level — the existing `disconnectMemberShell` test is the best template; copy its setup verbatim):

```dart
test('discardMemberTerminal disconnects shell, resets bus, marks reclaimed', () async {
  final opened = await openMixedSessionWithShells(cubit: cubit, repo: repo, postFrame: postFrame);
  final tab = cubit.activeTab!;
  final bus = tab.teamBus!;

  cubit.discardMemberTerminal(opened.sessionId, 'worker-1');

  expect(tab.memberShells.containsKey('worker-1'), isFalse);
  expect(tab.reclaimedMemberIds, contains('worker-1'));
  expect(bus.memberById('worker-1')!.lifecycle, MemberLifecycle.declared);
});

test('discardMemberTerminal is a no-op when the shell is not running', () async {
  final opened = await openMixedSessionWithShells(cubit: cubit, repo: repo, postFrame: postFrame);
  final tab = cubit.activeTab!;
  tab.memberShells.remove('worker-1');

  cubit.discardMemberTerminal(opened.sessionId, 'worker-1');

  expect(tab.reclaimedMemberIds, isNot(contains('worker-1')));
});
```

Note: these may live best as integration-style tests (they need a running bus). If `disconnectMemberShell` only has integration coverage today, put these two in Task 8's integration file instead and keep this task's test at the widget level for the pure logic. Decide by grep — if `disconnectMemberShell` is tested only in `test/integration/`, move these assertions to Task 8.

- [ ] **Step 3: Implement `discardMemberTerminal`**

In `session_launch_service.dart`, after `disconnectMemberShell` (line 706):

```dart
/// Reclaims an idle member's live terminal (Chrome-style discard).
///
/// Synchronous: flips the TeamBus lifecycle to `declared` before tearing down
/// the shell so no send-into-dead-PTY window exists. The materialize funnel or
/// [ensureMemberTerminalForView] re-brings the member online on demand (resume).
void discardMemberTerminal(String sessionId, String memberId) {
  final id = sessionId.trim();
  final mid = memberId.trim();
  if (id.isEmpty || mid.isEmpty) return;
  final tab = _tabStore.openTabBySessionId(id);
  if (tab == null) return;
  final shell = tab.memberShells[mid];
  if (shell == null || !shell.isRunning) return;
  tab.teamBus?.markMemberDiscarded(mid);
  tab.membersPendingConnect.remove(mid);
  shell.disconnect();
  tab.memberShells.remove(mid);
  tab.reclaimedMemberIds.add(mid);
  unawaited(tab.closeMemberRemotePlane(mid));
  _h.clearAgentStatusSeat(sessionId: tab.info.id, memberId: mid);
  _h.clearLaunchError(tab.info.id);
  _h.updateTabRunning(tab.info.id);
}
```

- [ ] **Step 4: Implement `ensureMemberTerminalForView`**

In `session_launch_service.dart`, after `discardMemberTerminal`:

```dart
/// Lazy-spawn / restore entry for "member selected + terminal view visible".
///
/// No-op when the shell is already up, connecting, or a connect is pending.
/// Team sessions resolve the roster member and schedule a connect (resume).
/// Simple sessions are intentionally not handled here — their restore is the
/// existing chat-submit / history-review connect path.
Future<void> ensureMemberTerminalForView(
  String sessionId,
  String memberId,
) async {
  final id = sessionId.trim();
  final mid = memberId.trim();
  if (id.isEmpty || mid.isEmpty) return;
  final tab = _tabStore.openTabBySessionId(id);
  if (tab == null) return;
  final shell = tab.memberShells[mid];
  if (shell != null && (shell.isRunning || shell.isConnecting)) return;
  if (tab.membersPendingConnect.contains(mid)) return;
  final session = tab.persistedSession;
  if (session == null) return;
  final teamId = session.sessionTeam.trim();
  if (teamId.isEmpty) return; // Simple mode — not this path.
  final team = await _h.teamProfileById(teamId);
  if (team == null) return;
  final member = sessionRosterMembers(session, team)
      .where((m) => m.id == mid)
      .firstOrNull;
  if (member == null || !member.isValid) return;
  _memberConnectScheduler.schedule(team, member, tab);
}
```

Import `sessionRosterMembers` (already imported at top? check `app_session.dart` import in this file — add `import '../../models/app_session.dart';` if missing).

- [ ] **Step 5: Clear the reclaimed flag on successful attach**

In `session_launch_service.dart`, `_scheduleShellConnect` (line 362) on `ConnectShellResult.attached`, add:

```dart
case ConnectShellResult.attached:
  if (member != null) {
    tab.reclaimedMemberIds.remove(member.id);
  }
  ...
```

And in `session_member_connect_scheduler.dart`, in the `schedule` success branch after `_host.updateTabRunning` (line 163), add the same removal:

```dart
tab.reclaimedMemberIds.remove(member.id);
```

- [ ] **Step 6: Expose reclaim reads on `ChatCubit`**

In `chat_cubit.dart`, next to `disconnectMemberShell` (line 1994), add:

```dart
void discardMemberTerminal(String sessionId, String memberId) =>
    _launchService.discardMemberTerminal(sessionId, memberId);

Future<void> ensureMemberTerminalForView(String sessionId, String memberId) =>
    _launchService.ensureMemberTerminalForView(sessionId, memberId);

bool isMemberTerminalReclaimed(String sessionId, String memberId) =>
    _tabStore.openTabBySessionId(sessionId)?.reclaimedMemberIds
        .contains(memberId) ?? false;
```

- [ ] **Step 7: Run tests / analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings` and `flutter test test/cubits/chat/ test/services/launch/ --exclude-tags integration` (or the exact test file you used).
Expected: no new issues; the tests from Step 2 pass (or are deferred to Task 8 if you decided to).

- [ ] **Step 8: Commit**

```bash
git add client/lib/cubits/chat/model/chat_tab.dart client/lib/cubits/chat/session_launch_service.dart client/lib/cubits/chat_cubit.dart
git commit -m "feat(session): discardMemberTerminal + ensureMemberTerminalForView lazy restore"
```

---

### Task 5: `TabMemberReclaimWatch` + wiring

**Files:**
- Create: `client/lib/cubits/chat/tab_member_reclaim_watch.dart`
- Modify: `client/lib/cubits/chat/tab_session_runtime_coordinator.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Modify: `client/lib/app/app_shell.dart`
- Test: `client/test/cubits/chat/tab_member_reclaim_watch_test.dart`

**Interfaces:**
- Consumes:
  - `ChatTabStore` (`.openTabs`, `.hasOpenTabs`).
  - `ChatTab` (`.memberShells`, `.teamBus`, `.selectedMemberId`, `.workbenchView`, `.info.id`, `.reclaimedMemberIds`, `.membersPendingConnect`).
  - `TeamBus.isMemberInTurn`, `TeamBus.hasPendingDoorbell`, `TeamBus.unreadCountFor` (async), `TeamBus.memberById` (for `ptyRunning`).
  - `TerminalReclaimPolicy` (Task 3).
  - `void Function(String sessionId, String memberId)` discard callback → `SessionLaunchService.discardMemberTerminal`.
  - `bool Function()` config resolvers: reclaim enabled, idle-after seconds.
  - `TeamProfile? Function()` activeTeam (to compute `isTeamLead` via `sessionRosterMembers`).
- Produces:
  - `class TabMemberReclaimWatch { void ensureStarted(); void maybeStop(); void dispose(); @visibleForTesting void debugTick(); }`
  - Constructor signature (see Step 3) wired from `TabSessionRuntimeCoordinator`.

- [ ] **Step 1: Write the failing watch test**

Create `client/test/cubits/chat/tab_member_reclaim_watch_test.dart`. Build a real `ChatTabStore` with one `ChatTab`, a real `TeamBus` (fake `MemberLauncher`), and a tiny local fake shell. The watch takes a `DateTime Function()` clock (`now:`), so no real sleeping is needed. Full concrete file:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/model/session_workbench_view.dart';
import 'package:teampilot/cubits/chat/tab_member_reclaim_watch.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/member_launcher.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';
import 'package:teampilot/services/team_bus/teammate_roster_profile.dart';
import 'package:teampilot/services/terminal/terminal_reclaim_policy.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

class _FakeLauncher implements MemberLauncher {
  final materialized = <String>[];
  @override
  Future<void> materialize(String memberId, TeamMessage bootstrap) async {
    materialized.add(memberId);
  }

  @override
  void wake(String memberId, String notice) {}

  @override
  void retryDelivery(String memberId, String notice) {}
}

class _FakeShell extends TerminalSession {
  _FakeShell({required super.executable}) : super(validateLaunch: false);

  @override
  bool get isRunning => true;

  @override
  bool get isConnecting => false;

  @override
  bool get isConnected => true;

  @override
  void dispose() {}
}

// TeamMemberConfig has no isTeamLead field — lead is derived from the id
// ("team-lead") via TeamMemberNaming.isTeamLead (see team_member_naming.dart).
const _lead = TeamMemberConfig(id: 'team-lead', name: 'lead');
const _worker = TeamMemberConfig(id: 'worker-1', name: 'worker');
const _team = TeamProfile(
  id: 't',
  name: 'T',
  teamMode: TeamMode.mixed,
  members: [_lead, _worker],
);

void main() {
  test('reclaims an idle worker after threshold, never the lead', () async {
    final store = ChatTabStore();
    final tab = ChatTab(
      info: ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
      cliTeamName: 'ct',
    );
    tab.workbenchView = SessionWorkbenchView.chat; // worker not displayed
    store.append(tab);

    final bus = TeamBus(launcher: _FakeLauncher());
    tab.teamBus = bus;
    bus.declareMember(AgentNode.test(
      memberId: 'team-lead',
      isTeamLead: true,
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.turnDoneReady,
    ));
    bus.declareMember(AgentNode.test(
      memberId: 'worker-1',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.turnDoneBusWait, // parked, idle
    ));
    tab.memberShells['team-lead'] = _FakeShell(executable: 'claude');
    tab.memberShells['worker-1'] = _FakeShell(executable: 'claude');

    final discarded = <(String, String)>[];
    var now = DateTime(2026, 8, 9, 12, 0, 0);
    final watch = TabMemberReclaimWatch(
      tabStore: store,
      reclaimEnabled: () => true,
      idleAfterSeconds: () => 2,
      activeTeam: () => _team,
      policy: () => const TerminalReclaimPolicy(idleAfter: Duration(seconds: 2)),
      onDiscardMember: (s, m) => discarded.add((s, m)),
      now: () => now,
    );

    watch.debugTick(); // seeds idleSince
    expect(discarded, isEmpty);
    now = now.add(const Duration(seconds: 3));
    watch.debugTick();

    expect(discarded, contains(('sess', 'worker-1')));
    expect(discarded, isNot(contains(('sess', 'team-lead'))));
  });

  test('working or unread members are never reclaimed', () async {
    final store = ChatTabStore();
    final tab = ChatTab(
      info: ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
      cliTeamName: 'ct',
    );
    store.append(tab);
    final bus = TeamBus(launcher: _FakeLauncher());
    tab.teamBus = bus;
    bus.declareMember(AgentNode.test(
      memberId: 'worker-1',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active, // in turn
    ));
    tab.memberShells['worker-1'] = _FakeShell(executable: 'claude');

    final discarded = <(String, String)>[];
    final watch = TabMemberReclaimWatch(
      tabStore: store,
      reclaimEnabled: () => true,
      idleAfterSeconds: () => 2,
      activeTeam: () => _team,
      policy: () => const TerminalReclaimPolicy(idleAfter: Duration(seconds: 2)),
      onDiscardMember: (s, m) => discarded.add((s, m)),
      now: () => DateTime(2026, 8, 9, 12, 0, 0),
    );

    watch.debugTick();
    expect(discarded, isEmpty, reason: 'in-turn member is protected');
  });
}
```

Notes: `ChatTabInfo(id:, title:, subtitle:)` (see `chat_tab_info.dart`) and `AgentNode.test(...)` (see `agent_node.dart`) and `ChatTabStore.append(tab)` (see `chat_tab_store.dart:184`) are the real APIs. `TeamMemberConfig`/`TeamProfile` match `team_config.dart` (the harness file `session_idle_busy_harness.dart` shows a real `TeamProfile(...)` const, so that shape is valid).

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/cubits/chat/tab_member_reclaim_watch_test.dart`
Expected: compile error — `TabMemberReclaimWatch` missing.

- [ ] **Step 3: Implement the watch**

Create `client/lib/cubits/chat/tab_member_reclaim_watch.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/team_config.dart';
import '../../services/terminal/terminal_reclaim_policy.dart';
import '../../utils/logging/logger.dart';
import 'chat_tab_store.dart';

/// Chrome-style idle discard: reclaims a member terminal that has been idle
/// (not working, no unread, not the lead, not displayed) past the threshold.
/// Restoration is lazy — via the TeamBus materialize funnel or
/// `ensureMemberTerminalForView` — so reclaim is cheap to reverse.
class TabMemberReclaimWatch {
  TabMemberReclaimWatch({
    required ChatTabStore tabStore,
    required bool Function() reclaimEnabled,
    required int Function() idleAfterSeconds,
    required TeamProfile? Function() activeTeam,
    required TerminalReclaimPolicy Function() policy,
    required void Function(String sessionId, String memberId) onDiscardMember,
    DateTime Function()? now,
  }) : _tabStore = tabStore,
       _reclaimEnabled = reclaimEnabled,
       _idleAfterSeconds = idleAfterSeconds,
       _activeTeam = activeTeam,
       _policy = policy,
       _onDiscardMember = onDiscardMember,
       _now = now ?? DateTime.now;

  final ChatTabStore _tabStore;
  final bool Function() _reclaimEnabled;
  final int Function() _idleAfterSeconds;
  final TeamProfile? Function() _activeTeam;
  final TerminalReclaimPolicy Function() _policy;
  final void Function(String sessionId, String memberId) _onDiscardMember;
  final DateTime Function() _now;

  Timer? _timer;

  /// Per (session, member) idle-start timestamp. Null = not yet idle.
  final Map<(String, String), DateTime> _idleSince = {};

  void ensureStarted() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void maybeStop() {
    if (!_tabStore.hasOpenTabs) {
      _timer?.cancel();
      _timer = null;
      _idleSince.clear();
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _idleSince.clear();
  }

  @visibleForTesting
  void debugTick() => tick();

  void tick() {
    if (!_reclaimEnabled()) {
      _idleSince.clear();
      return;
    }
    final policy = _policy();
    final team = _activeTeam();
    final now = _now();
    for (final tab in _tabStore.openTabs) {
      final sessionId = tab.info.id;
      for (final entry in tab.memberShells.entries.toList()) {
        final memberId = entry.key;
        final shell = entry.value;
        final snapshot = _snapshotFor(tab, memberId, shell, team);
        final key = (sessionId, memberId);
        if (policy.isProtected(snapshot)) {
          _idleSince.remove(key);
          continue;
        }
        final idleSince = _idleSince[key] ?? now;
        _idleSince[key] = idleSince;
        if (policy.shouldReclaim(snapshot, idleSince, now)) {
          appLogger.d(
            '[reclaim-watch] discard member=$memberId session=$sessionId '
            'idle=${now.difference(idleSince).inSeconds}s',
          );
          _idleSince.remove(key);
          _onDiscardMember(sessionId, memberId);
        }
      }
    }
  }

  TerminalReclaimSnapshot _snapshotFor(
    ChatTab tab,
    String memberId,
    TerminalSession shell,
    TeamProfile? team,
  ) {
    final bus = tab.teamBus;
    final isTeamLead = _isTeamLead(team, memberId);
    return TerminalReclaimSnapshot(
      sessionId: tab.info.id,
      memberId: memberId,
      shellRunning: shell.isRunning,
      shellConnecting: shell.isConnecting ||
          tab.membersPendingConnect.contains(memberId),
      isTeamLead: isTeamLead,
      isDisplayed: tab.workbenchView == SessionWorkbenchView.terminal &&
          tab.selectedMemberId == memberId,
      inTurn: bus?.isMemberInTurn(memberId) ?? shell.userTurnActive,
      hasUnread: (bus?.memberById(memberId)?.inbox.unreadCount ?? 0) > 0,
    );
  }

  bool _isTeamLead(TeamProfile? team, String memberId) {
    if (team == null) return false;
    for (final m in team.members) {
      if (m.id == memberId) return TeamMemberNaming.isTeamLead(m);
    }
    return false;
  }
}
```

Imports for this file: `TerminalSession` from `services/terminal/terminal_session.dart`; `SessionWorkbenchView` from `model/session_workbench_view.dart` (the enum file); `TeamMemberNaming` from `utils/team/team_member_naming.dart`; `TerminalReclaimPolicy`/`TerminalReclaimSnapshot` from `services/terminal/terminal_reclaim_policy.dart`; `TeamProfile` from `models/team_config.dart`. `hasUnread` reads `MemberInbox.unreadCount` — a synchronous field (see `team_bus.dart` `_hotUnreadCount`).

- [ ] **Step 4: Wire into `TabSessionRuntimeCoordinator`**

In `tab_session_runtime_coordinator.dart`, add optional constructor params (mirroring `idleWatch`) and pass through:
- `TabMemberReclaimWatch? reclaimWatch`
- `bool Function()? reclaimEnabled`
- `int Function()? reclaimIdleAfterSeconds`
- `void Function(String, String)? onReclaimMember`

Build the watch in the factory when `reclaimWatch == null` (only if a `discardMemberTerminal` callback or `onReclaimMember` is provided — when null, skip creation). Add `ensureStarted`/`maybeStop`/`dispose`/`debugTick` delegators alongside the idle-watch ones (lines 162-168).

- [ ] **Step 5: Wire in `ChatCubit`**

In `chat_cubit.dart`, add constructor params (all optional):
```dart
bool Function()? reclaimIdleTerminalsEnabled,
int Function()? reclaimIdleTerminalAfterSeconds,
```
Wire into `_sessionRuntime`:
```dart
reclaimEnabled: () => reclaimIdleTerminalsEnabled?.call() ?? false,
reclaimIdleAfterSeconds: () => reclaimIdleTerminalAfterSeconds?.call() ?? 180,
onReclaimMember: _launchService.discardMemberTerminal,
```
Add `@visibleForTesting void debugTickReclaimWatch() => _sessionRuntime.debugTickReclaimWatch();` and ensure `ensureIdleWatch()`/`maybeStopIdleWatch()`/`disposeIdleWatch()` also drive the reclaim watch (call the coordinator's combined methods). When a tab's `teamBus` installs (mixed), the coordinator's `ensureIdleWatch` already runs every tick for all tabs — reclaim tick runs in the same heartbeat.

- [ ] **Step 6: Wire resolvers in `app_shell.dart`**

In `app_shell.dart` `ChatCubit(...)` construction (near line 1170), add:
```dart
reclaimIdleTerminalsEnabled: () =>
    sessionPreferencesCubit.state.preferences.reclaimIdleTerminals,
reclaimIdleTerminalAfterSeconds: () =>
    sessionPreferencesCubit.state.preferences.reclaimIdleTerminalAfterSeconds,
```

- [ ] **Step 7: Run watch test + analyze**

Run: `flutter test test/cubits/chat/tab_member_reclaim_watch_test.dart` and `flutter analyze --no-fatal-infos --no-fatal-warnings`.
Expected: PASS; no new analyzer issues.

- [ ] **Step 8: Commit**

```bash
git add client/lib/cubits/chat/tab_member_reclaim_watch.dart client/lib/cubits/chat/tab_session_runtime_coordinator.dart client/lib/cubits/chat_cubit.dart client/lib/app/app_shell.dart client/test/cubits/chat/tab_member_reclaim_watch_test.dart
git commit -m "feat(chat): TabMemberReclaimWatch drives idle terminal discard"
```

---

### Task 6: Lazy spawn triggers (select member / terminal view)

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/cubits/chat_cubit_lazy_spawn_test.dart` (or extend the existing mixed-session cubit test)

**Interfaces:**
- Consumes: `SessionLaunchService.ensureMemberTerminalForView` (Task 4).
- Produces: behavior — `selectMember` and `setSessionWorkbenchView` trigger a lazy spawn for the selected member when the terminal view is (or becomes) visible.

- [ ] **Step 1: Write the failing test**

Extend the mixed-session cubit test (same harness as `session_idle_busy_integration_test.dart`, widget-level or integration as appropriate):

```dart
test('selecting a declared member while terminal view is shown spawns it', () async {
  final opened = await openMixedSessionWithShells(cubit: cubit, repo: repo, postFrame: postFrame);
  final tab = cubit.activeTab!;
  tab.memberShells.remove('worker-1');           // worker is declared, no shell
  tab.workbenchView = SessionWorkbenchView.terminal;
  tab.reclaimedMemberIds.add('worker-1');

  cubit.selectMember('worker-1');
  await drainPendingAsyncWork();

  expect(tab.membersPendingConnect, contains('worker-1'),
    reason: 'selecting a non-running member with terminal view must schedule connect');
});

test('setSessionWorkbenchView(terminal) spawns the selected member', () async {
  final opened = await openMixedSessionWithShells(cubit: cubit, repo: repo, postFrame: postFrame);
  final tab = cubit.activeTab!;
  tab.memberShells.remove('team-lead');
  tab.workbenchView = SessionWorkbenchView.chat;

  cubit.setSessionWorkbenchView(opened.sessionId, SessionWorkbenchView.terminal);
  await drainPendingAsyncWork();

  expect(tab.membersPendingConnect, contains('team-lead'));
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/cubits/chat_cubit_lazy_spawn_test.dart`
Expected: FAIL — selecting/viewing does not yet schedule a connect.

- [ ] **Step 3: Implement the triggers**

In `chat_cubit.dart`, `selectMember` (line 1904) — after the state emit, add:

```dart
@override
void selectMember(String memberId) {
  if (state.selectedMemberId == memberId) return;
  _activeTab?.selectedMemberId = memberId;
  emit(state.copyWith(selectedMemberId: memberId));
  final tab = _activeTab;
  if (tab != null && tab.workbenchView == SessionWorkbenchView.terminal) {
    unawaited(ensureMemberTerminalForView(tab.info.id, memberId));
  }
}
```

In `setSessionWorkbenchView` (line 1785) — after the view is applied and it is `liveTerminal`, ensure the selected member:

```dart
void setSessionWorkbenchView(String sessionId, SessionWorkbenchView view) {
  // ...existing body...
  if (view == SessionWorkbenchView.terminal) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    final memberId = tab?.selectedMemberId ?? state.selectedMemberId;
    if (memberId.isNotEmpty) {
      unawaited(ensureMemberTerminalForView(sessionId, memberId));
    }
  }
}
```

(Read the existing `setSessionWorkbenchView` body first and splice the trigger into it, preserving its current early-returns and emit logic.)

- [ ] **Step 4: Run the test + analyze**

Run: `flutter test test/cubits/chat_cubit_lazy_spawn_test.dart` and `flutter analyze --no-fatal-infos --no-fatal-warnings`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat_cubit.dart client/test/cubits/chat_cubit_lazy_spawn_test.dart
git commit -m "feat(chat): lazy-spawn member terminal on select/terminal-view"
```

---

### Task 7: UI — placeholder, members panel, config, l10n

**Files:**
- Modify: `client/lib/pages/chat/chat_workbench_terminal.dart` (or the widget that renders a non-running member terminal)
- Modify: `client/lib/widgets/right_tools/members_panel.dart`
- Modify: `client/lib/pages/config/session_config_section.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/widgets/app_keys.dart` (if `AppKeys` lives there — grep it)

**Interfaces:**
- Consumes: `ChatCubit.isMemberTerminalReclaimed(sessionId, memberId)`, `ensureMemberTerminalForView`, `discardMemberTerminal` (Task 4), `SessionPreferences` setters (Task 1).
- Produces: user-facing reclaim/restore UI + settings.

- [ ] **Step 1: Terminal placeholder (reclaimed / not-started, tap to restore)**

In `chat_workbench_terminal.dart`, where a non-running member's terminal is rendered (the `'chat-terminal-placeholder'` path at line 420), render a placeholder that:
- reads `chat.state.selectedMemberId` + `chat.isMemberTerminalReclaimed(sessionId, memberId)`;
- shows `l10n.memberTerminalReclaimedTitle` + `l10n.memberTerminalReclaimedBody` when reclaimed, else `l10n.memberTerminalNotStartedTitle`;
- wraps the text in a `GestureDetector`/`InkWell` whose `onTap` calls `chat.ensureMemberTerminalForView(sessionId, memberId)`.

Add the strings to both `.arb` files, e.g.:

`app_en.arb`:
```json
"memberTerminalReclaimedTitle": "Terminal reclaimed to save memory",
"memberTerminalReclaimedBody": "Tap to reconnect (session resumes)",
"memberTerminalNotStartedTitle": "Terminal not started — tap to launch",
"reclaimIdleTerminalsTitle": "Reclaim idle terminals",
"reclaimIdleTerminalsDescription": "Close idle member/session terminals after a timeout to free memory; they reconnect on demand.",
"reclaimIdleTerminalMinutesTitle": "Idle reclaim timeout (minutes)",
"reclaimIdleTerminalMinutesDescription": "Minutes a terminal may sit idle before it is reclaimed.",
```

`app_zh.arb` mirrors these in Chinese.

- [ ] **Step 2: Members panel label**

In `members_panel.dart`, when rendering a member's status, if `chat.isMemberTerminalReclaimed(sessionId, member.id)` show a "已回收 / reclaimed" tag in place of the offline label. (Grep how the panel already maps `MemberPresence` → label at line 155-157 and add the reclaimed override first.)

- [ ] **Step 3: Config UI rows**

In `session_config_section.dart`, after the `autoLaunchAllMembersOnConnect` row (line 254), add two rows using the existing `TpPreferenceRow` pattern:
- a `Switch` bound to `snapshot.reclaimIdleTerminals` → `cubit.setReclaimIdleTerminals(...)`;
- a numeric `TextFormField` (minutes) bound to `snapshot.reclaimIdleTerminalAfterSeconds ~/ 60` → `cubit.setReclaimIdleTerminalAfterMinutes(...)`.
Add both to the `_SessionControlsSnapshot` (lines 317+) and its mapping (lines 348+).

- [ ] **Step 4: Run analyze + a config-section widget test**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`. Then run any existing config-section test (`grep -rn "session_config_section\|SessionConfigSection" client/test`) and add a smoke test asserting the two new rows render with the new l10n keys.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/chat_workbench_terminal.dart client/lib/widgets/right_tools/members_panel.dart client/lib/pages/config/session_config_section.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/widgets/app_keys.dart
git commit -m "feat(ui): reclaimed terminal placeholder, member label, reclaim settings"
```

---

### Task 8: Integration tests (configurable fast timeout)

**Files:**
- Create: `client/test/integration/member_terminal_reclaim_integration_test.dart`
- Reuse: `test/integration/support/session_idle_busy_harness.dart` (`openMixedSessionWithShells`, `RunningConnectedFakeShell`), `test/integration/support/integration_test_setup.dart`, `connected_recording_shell.dart`.

**Interfaces:**
- Consumes: everything above (Task 1 config, Task 2 bus, Task 4 service methods, Task 5 watch).
- Produces: end-to-end proof of lazy spawn → demand spawn → idle reclaim → re-materialize, and Simple-mode reclaim → submit restore.

- [ ] **Step 1: Write the mixed lazy-spawn + reclaim + re-materialize test**

```dart
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/services/team_bus/team_message.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../support/post_frame_test_harness.dart';
import 'support/integration_test_setup.dart';
import 'support/session_idle_busy_harness.dart';

void main() {
  setUp(setUpIntegrationAppStorage);
  tearDown(tearDownIntegrationAppStorage);

  group('mixed team terminal lazy spawn + reclaim', () {
    late ChatCubit cubit;
    late SessionRepository repo;
    late PostFrameTestHarness postFrame;

    setUp(() async {
      repo = await newTempSessionRepository(); // reuse harness temp-dir helper
      postFrame = PostFrameTestHarness();
      cubit = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
        reclaimIdleTerminalsEnabled: () => true,
        reclaimIdleTerminalAfterSeconds: () => 2,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                RunningConnectedFakeShell(executable: executable),
      );
    });

    tearDown(() async {
      await postFrame.flush();
      await drainPendingAsyncWork();
      await cubit.close();
      await drainPendingAsyncWork();
    });

    test('worker stays declared, spawns on message, reclaims when idle, respawns', () async {
      final opened = await openMixedSessionWithShells(
        cubit: cubit, repo: repo, postFrame: postFrame);
      final tab = cubit.activeTab!;
      final bus = tab.teamBus!;

      // Worker starts running (harness pre-wires both shells).
      expect(tab.memberShells.containsKey('worker-1'), isTrue);
      expect(bus.memberById('worker-1')!.lifecycle, MemberLifecycle.running);

      // Idle past the 2s threshold (worker is not lead, not displayed, no unread).
      await Future<void>.delayed(const Duration(seconds: 3));
      cubit.debugTickReclaimWatch();
      await drainPendingAsyncWork();

      expect(tab.memberShells.containsKey('worker-1'), isFalse,
        reason: 'idle worker terminal should be reclaimed');
      expect(bus.memberById('worker-1')!.lifecycle, MemberLifecycle.declared,
        reason: 'bus state resets so the funnel can re-materialize');

      // Leader sends a message → worker re-materializes and receives it.
      await bus.send(const TeamMessage(
        id: 're-engage', from: 'team-lead', to: 'worker-1', content: 'status?'));
      await drainPendingAsyncWork();

      expect(bus.memberById('worker-1')!.ptyRunning, isTrue,
        reason: 'message must re-materialize the reclaimed worker');
      expect(await bus.unreadCountFor('worker-1'), 1);
    });
  });
}
```

Note: the leader and the selected member are protected, so only `worker-1` (non-lead, not displayed) gets reclaimed — this also implicitly verifies the protection set. If `openMixedSessionWithShells` pre-wires both shells and marks both running, that is exactly the "lazy → but harness pre-runs" shape; for the pure lazy-spawn assertion (worker never starts until message), add a separate test that opens the session with the worker NOT pre-wired (see Step 2).

- [ ] **Step 2: Lazy-spawn assertion (worker never auto-starts)**

```dart
test('worker is declared at open and only spawns when targeted', () async {
  final opened = await openMixedSessionWithShells(
    cubit: cubit, repo: repo, postFrame: postFrame);
  final tab = cubit.activeTab!;
  final bus = tab.teamBus!;

  // Remove the pre-wired worker to model the lazy default: only the lead
  // (selected) member holds a shell.
  tab.memberShells.remove('worker-1');
  bus.markMemberDiscarded('worker-1');
  await drainPendingAsyncWork();
  expect(bus.memberById('worker-1')!.lifecycle, MemberLifecycle.declared);

  await bus.send(const TeamMessage(
    id: 'wake', from: 'team-lead', to: 'worker-1', content: 'go'));
  await drainPendingAsyncWork();

  expect(tab.memberShells.containsKey('worker-1'), isTrue,
    reason: 'bus message must lazily spawn the worker shell');
  expect(bus.memberById('worker-1')!.ptyRunning, isTrue);
});
```

- [ ] **Step 3: Simple-mode reclaim + submit restore test**

```dart
group('simple mode reclaim + restore', () {
  // Same ChatCubit setup as Step 1 (reclaimIdleTerminalAfterSeconds: () => 2).

  test('idle simple terminal is reclaimed; submit reconnects', () async {
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/tmp')]);
    final session = await repo.createSession(workspace.workspaceId);
    await cubit.loadWorkspaceData(repo);
    await cubit.requestOpenSession(SessionOpenRequest(
      session: session, workspace: workspace, repo: repo, connectImmediately: true));
    await drainPendingAsyncWork();
    final tab = cubit.activeTab!;
    final shell = tab.memberShells.values.single;

    await Future<void>.delayed(const Duration(seconds: 3));
    cubit.debugTickReclaimWatch();
    await drainPendingAsyncWork();

    expect(tab.memberShells, isEmpty,
      reason: 'idle simple terminal should be reclaimed');
    expect(tab.reclaimedMemberIds, isNotEmpty);

    // Submit from chat reconnects (existing connect path).
    await cubit.connectWorkspaceSession(SessionConnectRequest(
      sessionId: session.sessionId, repo: repo, connectImmediately: true));
    await drainPendingAsyncWork();

    expect(tab.memberShells.values.single.isRunning, isTrue,
      reason: 'submit must restore the reclaimed simple terminal');
  });
});
```

(The exact `SessionConnectRequest` shape and the `loadWorkspaceData` call must match `session_idle_busy_integration_test.dart`'s simple-mode group at lines 597-631 — copy its setup verbatim.)

- [ ] **Step 4: Run the integration tests**

Run: `flutter test test/integration/member_terminal_reclaim_integration_test.dart`
Expected: PASS. If the fake shells don't honor `disconnect()`, make `RunningConnectedFakeShell` track a `disconnected` flag and override `isRunning => !disconnected` (update `session_idle_busy_harness.dart`).

- [ ] **Step 5: Commit**

```bash
git add client/test/integration/member_terminal_reclaim_integration_test.dart client/test/integration/support/session_idle_busy_harness.dart
git commit -m "test(integration): member terminal lazy spawn, reclaim, re-materialize"
```

---

### Task 9: Full gate — analyze + unit + integration

**Files:** none new.

- [ ] **Step 1: Full analyze + unit tests**

Run from `client/`:
```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags integration
```
Expected: no errors; all unit tests pass.

- [ ] **Step 2: Full integration suite (reclaim + nearby)**

Run: `flutter test test/integration --tags integration` (or at least `test/integration/member_terminal_reclaim_integration_test.dart` plus `session_idle_busy_integration_test.dart` and `mixed_team_claude_idle_busy_integration_test.dart`).
Expected: PASS; no regressions in the idle/busy behavior the reclaim watch now shares a heartbeat with.

- [ ] **Step 3: Manual smoke (optional, desktop)**

Launch the app, open a mixed session with a worker, watch the worker terminal get reclaimed after the configured timeout, then send a message and confirm it reconnects and the session resumes. (Follow `docs/DEVELOPMENT.md` launch instructions.)

- [ ] **Step 4: Commit any fixups**

```bash
git add -A
git commit -m "chore: finalize member terminal lazy spawn & reclaim"
```

---

## Self-review notes

- **Spec coverage:** prefs (T1), bus reset (T2), policy/protection set (T3), teardown+restore service methods + reclaimed flag (T4), watch + wiring + app resolvers (T5), lazy triggers (T6), UI/placeholder/l10n/config (T7), integration coverage with configurable timeout (T8), final gate (T9). Spec's "SSH remote member" and "task-claim during reclaim" edge cases fall out of the reuse of `closeMemberRemotePlane`/`ptyRunning` — no extra code, noted in T4.
- **Consistency:** `PtyClosed` (T2) consumed by `markMemberDiscarded` (T2) → `discardMemberTerminal` (T4) → watch (T5). `ensureMemberTerminalForView` (T4) consumed by `selectMember`/`setSessionWorkbenchView` (T6) and placeholder tap (T7). `reclaimIdleTerminals`/`reclaimIdleTerminalAfterSeconds` (T1) consumed by app_shell resolvers (T5) and config UI (T7). Test-seam `debugTickReclaimWatch` mirrors `debugTickIdleWatch`.
