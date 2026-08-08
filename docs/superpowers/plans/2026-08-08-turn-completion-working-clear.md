# Turn Completion & Working-State Clear Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every CLI's session reliably leave `workingSessionIds` after a conversation ends — via a CLI-declared turn-completion capability, a PTY-quiet fallback, and a fixed mixed-mode `/idle`→bus turn end — so the "运行中…" History footer clears instead of hanging on Cursor.

**Architecture:** Add `TurnCompletionCapability` to the CLI capability registry (each of the 5 launch-supported CLIs declares done-event names, whether it needs a PTY-quiet fallback, and whether it's doorbell-push). Wire a new `onAfterTurnEnded` callback from the idle-watch turn-end edge into `ChatCubit`, which clears the `AgentAttentionCubit` working seat only for fallback CLIs when no doorbell is pending. Fix `TeammateBusMcpHttpDelegate.handleIdleRequest` to call the existing (dead) `notifyIdle`, ending the bus turn for push CLIs. Add a parameterized 5-CLI × 2-mode integration matrix that asserts done-event clears, PTY-quiet fallback clears, and `waiting` seats are never mis-cleared.

**Tech Stack:** Dart, Flutter, flutter_bloc, TeamBus, AgentAttentionCubit, integration test harness (`RunningConnectedFakeShell`, `simulateFingerprintQuietGap`, `postMemberIdle`).

## Global Constraints

- Follow `docs/CODE_QUALITY.md`: no `print`; use `AppLogger`; l10n for user errors; cubits under `cubits/`, services under `services/`, models under `models/`.
- CLI wiring only via capabilities — no new `if (cli == …)` scattering (per AGENTS.md "CLIs" rule).
- Spec: `docs/superpowers/specs/2026-08-08-turn-completion-working-clear-design.md` (approved).
- Never clear a `waiting` seat via PTY-quiet fallback.
- Every task ends with `flutter analyze --no-fatal-infos --no-fatal-warnings` (from `client/`) passing for the files touched, and its own test green, then a commit.
- Test files: unit tests in `client/test/` mirroring the lib path; integration tests tagged `@Tags(['integration'])` from `package:test`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`.

---

### Task 1: Add `TurnCompletionCapability` interface + 5 CLI declarations

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/turn_completion_capability.dart`
- Create: `client/test/services/cli/registry/capabilities/turn_completion_capability_test.dart`
- Modify: `client/lib/services/cli/registry/tools/claude_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/tools/cursor_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/tools/codex_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/tools/opencode_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/tools/flashskyai_cli_tool.dart`

**Interfaces:**
- Produces:
  - `abstract interface class TurnCompletionCapability implements CliCapability { Set<String> get doneEventNames; bool get requiresPtyFallback; bool get usesDoorbellPush; }`
  - `CliToolRegistry.capability<TurnCompletionCapability>(CliTool id)` returns the declared instance or `null` (already supported generically via `capability<T extends CliCapability>`).

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/cli/registry/capabilities/turn_completion_capability_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/capabilities/turn_completion_capability.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  test('cursor declares stop done + PTY fallback + doorbell push', () {
    final cap = registry.capability<TurnCompletionCapability>(CliTool.cursor);
    expect(cap, isNotNull);
    expect(cap!.doneEventNames, {'stop'});
    expect(cap.requiresPtyFallback, isTrue);
    expect(cap.usesDoorbellPush, isTrue);
  });

  test('claude declares Stop/StopFailure done, no fallback, no push', () {
    final cap = registry.capability<TurnCompletionCapability>(CliTool.claude);
    expect(cap, isNotNull);
    expect(cap!.doneEventNames, {'Stop', 'StopFailure'});
    expect(cap.requiresPtyFallback, isFalse);
    expect(cap.usesDoorbellPush, isFalse);
  });

  test('opencode declares session.idle done, no fallback', () {
    final cap = registry.capability<TurnCompletionCapability>(CliTool.opencode);
    expect(cap, isNotNull);
    expect(cap!.doneEventNames, {'session.idle'});
    expect(cap.requiresPtyFallback, isFalse);
  });

  test('codex and flashskyai declare Stop/StopFailure done, no fallback', () {
    for (final cli in [CliTool.codex, CliTool.flashskyai]) {
      final cap = registry.capability<TurnCompletionCapability>(cli);
      expect(cap, isNotNull);
      expect(cap!.doneEventNames, {'Stop', 'StopFailure'});
      expect(cap.requiresPtyFallback, isFalse);
      expect(cap.usesDoorbellPush, isFalse);
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/capabilities/turn_completion_capability_test.dart -v`
Expected: FAIL — compile error, `turn_completion_capability.dart` not found.

- [ ] **Step 3: Add the interface**

```dart
// client/lib/services/cli/registry/capabilities/turn_completion_capability.dart
import '../cli_capability.dart';

/// Declares a CLI's "turn ended" signals, driving reliable session
/// working-state clearing (see 2026-08-08-turn-completion-working-clear-design.md).
abstract interface class TurnCompletionCapability implements CliCapability {
  /// Agent-status hook event names that mean "turn ended" (→ done).
  Set<String> get doneEventNames;

  /// Whether the PTY-quiet turn-end fallback may clear the seat
  /// (done event may be unreliable for this CLI).
  bool get requiresPtyFallback;

  /// Whether this is a doorbell-push CLI (mixed mode: `/idle` must end the
  /// bus turn).
  bool get usesDoorbellPush;
}
```

- [ ] **Step 4: Add per-CLI implementations and register them**

For each tool file, add a small implementation class and include it in the `capabilities` list. Example for cursor (`client/lib/services/cli/registry/tools/cursor_cli_tool.dart`):

```dart
import '../capabilities/turn_completion_capability.dart';

final class CursorTurnCompletion implements TurnCompletionCapability {
  const CursorTurnCompletion();
  @override
  Set<String> get doneEventNames => const {'stop'};
  @override
  bool get requiresPtyFallback => true;
  @override
  bool get usesDoorbellPush => true;
}
```

In the constructor body of `CursorCliTool`, add a field + default:

```dart
this.turnCompletion = const CursorTurnCompletion(),
```

declare `final TurnCompletionCapability turnCompletion;` and add `turnCompletion` to the `capabilities => [...]` list.

For the other four tools use the same pattern:

| CLI | file | class | doneEventNames | requiresPtyFallback | usesDoorbellPush |
|-----|------|-------|----------------|--------------------|------------------|
| claude | `tools/claude_cli_tool.dart` | `ClaudeTurnCompletion` | `{'Stop', 'StopFailure'}` | false | false |
| flashskyai | `tools/flashskyai_cli_tool.dart` | `FlashskyaiTurnCompletion` | `{'Stop', 'StopFailure'}` | false | false |
| codex | `tools/codex_cli_tool.dart` | `CodexTurnCompletion` | `{'Stop', 'StopFailure'}` | false | false |
| opencode | `tools/opencode_cli_tool.dart` | `OpencodeTurnCompletion` | `{'session.idle'}` | false | false |

- [ ] **Step 5: Run test to verify it passes**

Run: `cd client && flutter test test/services/cli/registry/capabilities/turn_completion_capability_test.dart -v`
Expected: PASS.

- [ ] **Step 6: Analyze + commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

```bash
git add client/lib/services/cli/registry/capabilities/turn_completion_capability.dart \
  client/lib/services/cli/registry/tools/ \
  client/test/services/cli/registry/capabilities/turn_completion_capability_test.dart
git commit -m "feat(cli): add TurnCompletionCapability with per-CLI declarations"
```

---

### Task 2: Add `AgentAttentionCubit.clearWorkingIfWorking`

**Files:**
- Modify: `client/lib/cubits/agent_attention_cubit.dart` (add method after `clearSeat`, ~line 317)
- Create: `client/test/cubits/agent_attention_clear_working_test.dart`

**Interfaces:**
- Consumes: `AgentAttentionState.seats` (Map<String, AgentSeatAttentionEntry>), `AgentSeatAttention` enum, `agentSeatKey(sessionId, memberId)` (already imported in cubit).
- Produces: `void clearWorkingIfWorking({required String sessionId, required String memberId})` — reads current seat; only if `attention == AgentSeatAttention.working` removes the seat; never touches `waiting`.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/cubits/agent_attention_clear_working_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';

void main() {
  test('clearWorkingIfWorking removes a working seat', () {
    final cubit = AgentAttentionCubit(pruneInterval: null);
    cubit.applyEvent(
      sessionId: 's1',
      memberId: 'm1',
      event: const AgentStatusEvent(state: AgentSeatAttention.working),
      skipPermissions: false,
    );
    cubit.clearWorkingIfWorking(sessionId: 's1', memberId: 'm1');
    expect(
      cubit.state.attentionFor(sessionId: 's1', memberId: 'm1'),
      isNull,
    );
  });

  test('clearWorkingIfWorking does NOT remove a waiting seat', () {
    final cubit = AgentAttentionCubit(pruneInterval: null);
    cubit.applyEvent(
      sessionId: 's1',
      memberId: 'm1',
      event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
      skipPermissions: false,
    );
    cubit.clearWorkingIfWorking(sessionId: 's1', memberId: 'm1');
    expect(
      cubit.state.attentionFor(sessionId: 's1', memberId: 'm1'),
      AgentSeatAttention.waiting,
    );
  });

  test('clearWorkingIfWorking is a no-op when seat absent', () {
    final cubit = AgentAttentionCubit(pruneInterval: null);
    cubit.clearWorkingIfWorking(sessionId: 's1', memberId: 'm1'); // no throw
    expect(cubit.state.seats, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/agent_attention_clear_working_test.dart -v`
Expected: FAIL — `clearWorkingIfWorking` undefined.

- [ ] **Step 3: Implement the method**

```dart
/// Remove the seat only when it is currently [AgentSeatAttention.working].
/// Never touches [AgentSeatAttention.waiting] (permission prompts) so a
/// PTY-quiet turn-end fallback cannot mis-clear a pending question.
void clearWorkingIfWorking({
  required String sessionId,
  required String memberId,
}) {
  final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
  final entry = state.seats[key];
  if (entry == null) return;
  if (entry.attention != AgentSeatAttention.working) return;
  final seats = Map<String, AgentSeatAttentionEntry>.of(state.seats)
    ..remove(key);
  emit(AgentAttentionState(seats: seats, clock: _clock));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/agent_attention_clear_working_test.dart -v`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

```bash
git add client/lib/cubits/agent_attention_cubit.dart \
  client/test/cubits/agent_attention_clear_working_test.dart
git commit -m "feat(attention): add clearWorkingIfWorking (waiting-safe)"
```

---

### Task 3: Thread `onAfterTurnEnded` from idle-watch into ChatCubit

**Files:**
- Modify: `client/lib/cubits/chat/tab_session_runtime_coordinator.dart` (add callback param + pass-through)
- Modify: `client/lib/cubits/chat/tab_session_idle_watch.dart` (call the callback inside the `endTurn` closure)
- Modify: `client/lib/cubits/chat_cubit.dart` (add `onAfterTurnEnded` param, wire `_onTurnEnded`)

**Interfaces:**
- Consumes: `TabSessionRuntimeCoordinator` constructor params `onAfterTurnLatched`, `onAfterIdleWatchTick` (existing). `TabSessionIdleWatch.tick` closure `endTurn`.
- Produces:
  - `TabSessionRuntimeCoordinator({void Function(String sessionId, String memberId)? onAfterTurnEnded, ...})`
  - `TabSessionIdleWatch({void Function(String sessionId, String memberId)? onAfterTurnEnded, ...})`
  - `ChatCubit._onTurnEnded(String sessionId, String memberId)` private method.

- [ ] **Step 1: Write the failing unit test for the threading**

Create `client/test/cubits/chat/tab_session_idle_watch_test.dart` if it does not exist; otherwise add a test. It constructs `TabSessionIdleWatch` with a fake `ChatTabStore`, a shell whose tracker is boot-latched, calls `markUserTurnStarted`, then `simulateFingerprintQuietGap`, then `tick()`, and asserts the `onAfterTurnEnded` callback fired with the session/member ids.

```dart
// client/test/cubits/chat/tab_session_idle_watch_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/tab_session_idle_watch.dart';
import 'package:teampilot/cubits/chat/tab_member_coordination_factory.dart';
import 'package:teampilot/cubits/chat/tab_member_pty_delivery.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/session_working_resolver.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../../integration/support/connected_recording_shell.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  test('onAfterTurnEnded fires on PTY-quiet turn end', () async {
    final store = ChatTabStore();
    final tab = ChatTab(info: const ChatTabInfo(id: 's1', title: 'T', subtitle: ''));
    store.append(tab);
    final shell = await ConnectedRecordingShell.connect();
    tab.memberShells['s1'] = shell.session;

    final coordination = TabMemberCoordinationFactory(
      tabStore: store,
      globalPresets: () => const [],
      activeTeam: () => null,
      sessionWorking: SessionWorkingResolver(),
    );
    final delivery = TabMemberPtyDelivery(
      tabStore: store,
      shellFactory: ({required String executable, int scrollbackLines = 10000}) =>
          shell.session,
      globalPresets: () => const [],
      activeTeam: () => null,
      isClosed: () => false,
      coordinationFactory: coordination,
    );

    String? endedSession;
    String? endedMember;
    final watch = TabSessionIdleWatch(
      tabStore: store,
      coordinationFactory: coordination,
      delivery: delivery,
      isClosed: () => false,
      onAfterTurnEnded: (sid, mid) {
        endedSession = sid;
        endedMember = mid;
      },
    );

    shell.session.activityTracker.latchBootFrameReadyForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );
    shell.session.markUserTurnStarted();
    shell.simulateQuietGap();
    watch.tick();
    await Future<void>.delayed(Duration.zero);

    expect(endedSession, 's1');
    expect(endedMember, 's1');
    watch.dispose();
  });
}
```

Note: check `ChatTab` / `ChatTabInfo` constructors and `ChatTabStore.append` against the current code and adjust names if they differ (they are used identically in `session_working_resolver_test.dart`).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/chat/tab_session_idle_watch_test.dart -v`
Expected: FAIL — `onAfterTurnEnded` not a constructor param (compile error).

- [ ] **Step 3: Implement threading**

`tab_session_runtime_coordinator.dart`: add `onAfterTurnEnded` param, pass into the `TabSessionIdleWatch(...)` factory call (line ~59-67).

`tab_session_idle_watch.dart`: add field + constructor param; inside the `endTurn` closure (currently `coordination.endTurn();` around line 113-120), after it, add:

```dart
endTurn: () {
  coordination.endTurn();
  _onAfterTurnEnded?.call(tab.info.id, memberId);
},
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/chat/tab_session_idle_watch_test.dart -v`
Expected: PASS.

- [ ] **Step 5: Wire ChatCubit (no behavior yet, just plumbing)**

In `chat_cubit.dart`:

```dart
late final TabSessionRuntimeCoordinator _sessionRuntime =
    TabSessionRuntimeCoordinator(
      ...
      onAfterTurnLatched: _onOperatorTurnLatched,
      onAfterTurnEnded: _onTurnEnded,   // add
      ...
    );
```

Add the private method (body fills in Task 5, but add the no-op so wiring compiles):

```dart
/// PTY-quiet turn end — PTY-quiet fallback clears the attention working
/// seat for CLIs whose done event may be unreliable (requiresPtyFallback).
void _onTurnEnded(String sessionId, String memberId) {
  // Implemented in a later task.
}
```

Also thread the same `onAfterTurnEnded` through the second `TabSessionRuntimeCoordinator` construction site if one exists (search for `onAfterTurnLatched:` — line 301 also wires it; add `onAfterTurnEnded` there too if that site constructs the runtime).

- [ ] **Step 6: Analyze + commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

```bash
git add client/lib/cubits/chat_cubit.dart \
  client/lib/cubits/chat/tab_session_runtime_coordinator.dart \
  client/lib/cubits/chat/tab_session_idle_watch.dart \
  client/test/cubits/chat/tab_session_idle_watch_test.dart
git commit -m "feat(chat): thread onAfterTurnEnded from idle-watch to ChatCubit"
```

---

### Task 4: Implement `ChatCubit._onTurnEnded` fallback + doorbell guard

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart` (fill in `_onTurnEnded`)
- Modify: `client/lib/services/team_bus/team_bus.dart` (add public `hasPendingDoorbell` accessor)
- Create: `client/test/cubits/chat_cubit_turn_end_test.dart`

**Interfaces:**
- Consumes: `TurnCompletionCapability` (Task 1), `AgentAttentionCubit.clearWorkingIfWorking` (Task 2), `ChatCubit._activeTeam`, `ChatCubit.cliRegistry`, `sessionMemberLaunchCli` (from `services/cli/preset_resolver.dart`), `TeamBus` member state.
- Produces:
  - `TeamBus.hasPendingDoorbell(String memberId) → bool` — true when `doorbelled && !inbox.isEmpty`, i.e. same predicate as `shouldDeferPtyIdleEnd` minus the delivery-phase guards. (Keep `shouldDeferPtyIdleEnd` as-is; add this as a focused public predicate.)
  - Behavior of `_onTurnEnded`:
    - resolve the tab, persisted session, team, member
    - resolve launch CLI via `sessionMemberLaunchCli`
    - look up `TurnCompletionCapability`; if `requiresPtyFallback` is false → return
    - if the session has a bus and `bus.hasPendingDoorbell(memberId)` → return
    - `_agentAttentionCubit?.clearWorkingIfWorking(sessionId, memberId)`
    - `_recomputeWorkingSessions()`

- [ ] **Step 1: Add `hasPendingDoorbell` to TeamBus + unit test**

Add to `team_bus.dart` (near `shouldDeferPtyIdleEnd`):

```dart
/// True when a doorbell was rung and unread mail remains — PTY-quiet turn
/// end must be deferred (the agent is expected to consume via read_messages).
bool hasPendingDoorbell(String memberId) {
  final node = _members[memberId];
  if (node == null) return false;
  return node.doorbelled && !node.inbox.isEmpty;
}
```

Test in `client/test/services/team_bus/team_bus_test.dart` (create file if missing, mirroring `FakeMemberLauncher` usage from `member_coordination_test.dart`): declare a running cursor member with `doorbelled=true` and a non-empty inbox, assert `hasPendingDoorbell` true; then `readMessages` with markRead drains → assert false.

- [ ] **Step 2: Run the TeamBus test to verify it passes**

Run: `cd client && flutter test test/services/team_bus/team_bus_test.dart -v`
Expected: PASS.

- [ ] **Step 3: Write the failing ChatCubit fallback test**

```dart
// client/test/cubits/chat_cubit_turn_end_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../integration/support/session_idle_busy_harness.dart';
import '../support/post_frame_test_harness.dart';

void main() {
  test('simple cursor: PTY quiet clears the attention working seat', () async {
    final tmp = await Directory.systemTemp.createTemp('cubit_turn_end_');
    final repo = SessionRepository(rootDir: tmp.path);
    final attention = AgentAttentionCubit(pruneInterval: null);
    final postFrame = PostFrameTestHarness();
    final cubit = ChatCubit(
      executableResolver: () => 'true',
      automationRepository: testAutomationRepository(),
      sessionRepository: repo,
      postFrameScheduler: postFrame.scheduler,
      agentAttentionCubit: attention,
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) =>
              RunningConnectedFakeShell(executable: executable),
    );

    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/tmp')]);
    final session = await repo.createSession(workspace.workspaceId, cli: CliTool.cursor);
    await cubit.loadWorkspaceData(repo);
    await cubit.requestOpenSession(SessionOpenRequest(
      session: session, workspace: workspace, repo: repo, connectImmediately: false,
    ));
    await drainPendingAsyncWork();
    final tab = cubit.activeTab!;
    final shell = tab.memberShells.values.single;
    shell.activityTracker.latchBootFrameReadyForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );

    // Stamp working via the cursor agent-status hook (afterAgentResponse).
    attention.applyEvent(
      sessionId: session.sessionId,
      memberId: session.sessionId,
      event: const AgentStatusEvent(
        state: AgentSeatAttention.working,
        hookEventName: 'afterAgentResponse',
      ),
      skipPermissions: false,
    );
    await drainPendingAsyncWork();
    expect(cubit.state.workingSessionIds, contains(session.sessionId));

    // PTY goes quiet → turn-end fallback should clear the seat.
    shell.simulateQuietGap();
    cubit.debugTickIdleWatch();
    await drainPendingAsyncWork();

    expect(
      attention.state.attentionFor(sessionId: session.sessionId, memberId: session.sessionId),
      isNull,
    );
    expect(cubit.state.workingSessionIds, isEmpty);
  });
}
```

Note: verify `RunningConnectedFakeShell` has `simulateQuietGap` (it does — `connected_recording_shell.dart:70`); if using `RunningConnectedFakeShell` from the harness (which extends `TerminalSession`), call `shell.activityTracker.notePtyBytes(...)` backdated via the harness `simulateFingerprintQuietGap(shell)` instead, matching `session_idle_busy_integration_test.dart:623`. Use whichever shell the cubit factory produces — check whether it's `RunningConnectedFakeShell` or `ConnectedRecordingShell` and adapt.

- [ ] **Step 4: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/chat_cubit_turn_end_test.dart -v`
Expected: FAIL — attention seat still `working` after quiet (bug reproduced) because `_onTurnEnded` is a no-op.

- [ ] **Step 5: Implement `_onTurnEnded`**

```dart
void _onTurnEnded(String sessionId, String memberId) {
  final attention = _agentAttentionCubit;
  if (attention == null || memberId.trim().isEmpty) return;
  final tab = _tabStore.openTabBySessionId(sessionId);
  final session = tab?.persistedSession;
  if (tab == null || session == null) return;
  final team = _teamForTab(session);
  if (team == null) return;
  final member = sessionRosterMembers(session, team)
      .where((m) => m.id == memberId)
      .firstOrNull;
  if (member == null) return;
  final cli = sessionMemberLaunchCli(
    session: session,
    team: team,
    member: member,
    globalPresets: _lifecycle.globalPresets,
  );
  final cap = cliRegistry.capability<TurnCompletionCapability>(cli);
  if (cap == null || !cap.requiresPtyFallback) return;
  final bus = tab.teamBus;
  if (bus != null && bus.hasPendingDoorbell(memberId)) return;
  attention.clearWorkingIfWorking(sessionId: sessionId, memberId: memberId);
  _recomputeWorkingSessions();
}
```

Add a `_teamForTab(AppSession session)` helper if none exists (returns the active team when `_activeTeam?.id == session.sessionTeam`, else null), or reuse the resolver's `_fallbackTeam` pattern. Ensure `firstOrNull` import (`package:collection/collection.dart`) is present in the file.

- [ ] **Step 6: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/chat_cubit_turn_end_test.dart -v`
Expected: PASS.

- [ ] **Step 7: Analyze + commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

```bash
git add client/lib/cubits/chat_cubit.dart \
  client/lib/services/team_bus/team_bus.dart \
  client/test/cubits/chat_cubit_turn_end_test.dart \
  client/test/services/team_bus/team_bus_test.dart
git commit -m "feat(chat): PTY-quiet turn-end fallback clears working seat"
```

---

### Task 5: Fix `/idle` → `notifyIdle` (mixed push turn end)

**Files:**
- Modify: `client/lib/services/team_bus/mcp/teammate_bus_mcp_http_delegate.dart` (`handleIdleRequest`)
- Create: `client/test/services/team_bus/mcp/teammate_bus_idle_turn_end_test.dart`

**Interfaces:**
- Consumes: `TeammateBusMcpHandler.notifyIdle(String memberId)` (exists, currently dead), `TeamBus.onMemberIdle`.
- Produces: behavior — `handleIdleRequest` now calls `handler.notifyIdle(memberId)` after writing the response when `memberId.isNotEmpty`.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/team_bus/mcp/teammate_bus_idle_turn_end_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_http_delegate.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import '../support/fake_member_launcher.dart';

void main() {
  test('idle POST ends the bus turn for a push (cursor) member', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(
      memberId: 'worker',
      cli: 'cursor',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active, // in turn
    ));
    final handler = TeammateBusMcpHandler(bus: bus, forceWaitBeforeStop: false);
    final delegate = TeammateBusMcpHttpDelegate(handler: handler);

    // in-turn before idle
    expect(bus.isMemberInTurn('worker'), isTrue);

    // Simulate the CLI stop-hook POST /idle.
    final request = _IdleRequest();
    await delegate.handleIdleRequest(request, memberId: 'worker');

    // Turn ended → member no longer in turn.
    expect(bus.isMemberInTurn('worker'), isFalse);
  });
}
```

Provide a minimal fake `HttpRequest`/response if the delegate needs one — check whether `handleIdleRequest` requires a real `dart:io HttpRequest`; if so, refactor to extract a testable method `Future<String> idleDecisionForMember(String memberId)` + a `void endTurnForIdle(String memberId)` and test the latter directly. Prefer extracting:

```dart
/// Ends the bus turn for an idle push CLI. No-op for forceWait CLIs
/// (parked → onMemberIdle returns early).
void endTurnForIdle(String memberId) {
  if (memberId.isNotEmpty) handler.notifyIdle(memberId);
}
```

and call it from `handleIdleRequest` after closing the response.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/team_bus/mcp/teammate_bus_idle_turn_end_test.dart -v`
Expected: FAIL — `isMemberInTurn` still true.

- [ ] **Step 3: Implement**

```dart
// inside handleIdleRequest, after `await request.response.close();`
endTurnForIdle(memberId);
```

with

```dart
void endTurnForIdle(String memberId) {
  if (memberId.isNotEmpty) handler.notifyIdle(memberId);
}
```

`TeammateBusMcpHandler.notifyIdle` already calls `_bus.onMemberIdle(memberId)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/team_bus/mcp/teammate_bus_idle_turn_end_test.dart -v`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

```bash
git add client/lib/services/team_bus/mcp/teammate_bus_mcp_http_delegate.dart \
  client/test/services/team_bus/mcp/teammate_bus_idle_turn_end_test.dart
git commit -m "fix(team-bus): /idle POST ends bus turn for push CLIs (notifyIdle)"
```

---

### Task 6: Integration harness — bind attention in simple mode + turn_completion harness

**Files:**
- Modify: `client/test/integration/session_idle_busy_integration_test.dart` (simple group binds `AgentAttentionCubit`)
- Create: `client/test/integration/turn_completion/turn_completion_harness.dart`

**Interfaces:**
- Produces:
  - `Future<({String sessionId, TerminalSession shell, ChatCubit cubit, AgentAttentionCubit attention})> openSimpleTurnSession({required CliTool cli, ...})` helper in the harness.
  - `void stampWorking(AgentAttentionCubit attention, String sessionId, String memberId, {String hookEventName = 'afterAgentResponse'})`
  - `void stampDone(AgentAttentionCubit attention, String sessionId, String memberId, {required String doneEventName})`
  - Re-exports `simulateFingerprintQuietGap` from the existing harness.

- [ ] **Step 1: Bind `AgentAttentionCubit` in the simple idle/busy group**

In `session_idle_busy_integration_test.dart`, the first group (`mixed team session idle/busy`) already constructs `ChatCubit` at line 51. Add a new simple group (or extend the existing simple test at line 593) that passes `agentAttentionCubit: attention` and `attention` in setUp, mirroring the mixed attention group at line 336. Run the existing simple test (`send lights working; quiet screen clears it`) and confirm it still passes with attention bound (it should — the seat was never stamped in that test).

- [ ] **Step 2: Write `turn_completion_harness.dart`**

```dart
// client/test/integration/turn_completion/turn_completion_harness.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../../support/post_frame_test_harness.dart';
import '../support/session_idle_busy_harness.dart';

typedef OpenSimpleTurnResult = ({
  String sessionId,
  TerminalSession shell,
  ChatCubit cubit,
  AgentAttentionCubit attention,
});

Future<OpenSimpleTurnResult> openSimpleTurnSession({
  required CliTool cli,
  required SessionRepository repo,
  required PostFrameTestHarness postFrame,
}) async {
  final attention = AgentAttentionCubit(pruneInterval: null);
  final cubit = ChatCubit(
    executableResolver: () => 'true',
    automationRepository: testAutomationRepository(),
    sessionRepository: repo,
    postFrameScheduler: postFrame.scheduler,
    agentAttentionCubit: attention,
    terminalSessionFactory:
        ({required String executable, int scrollbackLines = 10000}) =>
            RunningConnectedFakeShell(executable: executable),
  );
  final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/tmp')]);
  final session = await repo.createSession(workspace.workspaceId, cli: cli);
  await cubit.loadWorkspaceData(repo);
  await cubit.requestOpenSession(SessionOpenRequest(
    session: session,
    workspace: workspace,
    repo: repo,
    connectImmediately: false,
  ));
  await drainPendingAsyncWork();
  await postFrame.flush();
  final tab = cubit.activeTab!;
  final shell = tab.memberShells.values.single;
  shell.activityTracker.latchBootFrameReadyForTest(
    DateTime.now().subtract(const Duration(seconds: 5)),
  );
  return (sessionId: session.sessionId, shell: shell, cubit: cubit, attention: attention);
}

void stampWorking(AgentAttentionCubit attention, String sessionId, String memberId) {
  attention.applyEvent(
    sessionId: sessionId,
    memberId: memberId,
    event: const AgentStatusEvent(
      state: AgentSeatAttention.working,
      hookEventName: 'afterAgentResponse',
    ),
    skipPermissions: false,
  );
}

void stampDone(AgentAttentionCubit attention, String sessionId, String memberId, {required String doneEventName}) {
  attention.applyEvent(
    sessionId: sessionId,
    memberId: memberId,
    event: AgentStatusEvent(state: AgentSeatAttention.done, hookEventName: doneEventName),
    skipPermissions: false,
  );
}
```

Check `repo.createSession` signature accepts `cli:` — verify against `session_repository.dart`; if it does not, set `cli` on the session object or use the team-profile path. Adjust to the real signature.

- [ ] **Step 3: Analyze + commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

```bash
git add client/test/integration/session_idle_busy_integration_test.dart \
  client/test/integration/turn_completion/turn_completion_harness.dart
git commit -m "test(integration): bind attention in simple mode + turn_completion harness"
```

---

### Task 7: Simple-mode matrix — done event clears + PTY fallback clears + waiting not mis-cleared

**Files:**
- Create: `client/test/integration/turn_completion/turn_completion_simple_test.dart`

**Interfaces:**
- Consumes: harness from Task 6, `TurnCompletionCapability` from Task 1, `clearWorkingIfWorking` from Task 2, `_onTurnEnded` from Task 4.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/integration/turn_completion/turn_completion_simple_test.dart
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';

import '../../support/post_frame_test_harness.dart';
import '../support/integration_test_setup.dart';
import 'turn_completion_harness.dart';

void main() {
  setUp(setUpIntegrationAppStorage);
  tearDown(tearDownIntegrationAppStorage);

  const allCli = [
    CliTool.claude,
    CliTool.flashskyai,
    CliTool.codex,
    CliTool.opencode,
    CliTool.cursor,
  ];

  final doneEvent = {
    CliTool.claude: 'Stop',
    CliTool.flashskyai: 'Stop',
    CliTool.codex: 'Stop',
    CliTool.opencode: 'session.idle',
    CliTool.cursor: 'stop',
  };

  for (final cli in allCli) {
    test('$cli: done event clears working', () async {
      final repo = SessionRepository(rootDir: (await Directory.systemTemp.createTemp('tc_simple_')).path);
      final postFrame = PostFrameTestHarness();
      final opened = await openSimpleTurnSession(cli: cli, repo: repo, postFrame: postFrame);
      stampWorking(opened.attention, opened.sessionId, opened.sessionId);
      await drainPendingAsyncWork();
      expect(opened.cubit.state.workingSessionIds, contains(opened.sessionId));

      stampDone(opened.attention, opened.sessionId, opened.sessionId, doneEventName: doneEvent[cli]!);
      await drainPendingAsyncWork();
      expect(opened.cubit.state.workingSessionIds, isEmpty);
      await opened.cubit.close();
      await opened.attention.close();
      await deleteTempDirBestEffort(tmpDir(repo));
    });

    test('$cli: PTY-quiet fallback clears working only for fallback CLIs', () async {
      final repo = SessionRepository(rootDir: (await Directory.systemTemp.createTemp('tc_simple_')).path);
      final postFrame = PostFrameTestHarness();
      final opened = await openSimpleTurnSession(cli: cli, repo: repo, postFrame: postFrame);
      stampWorking(opened.attention, opened.sessionId, opened.sessionId);
      await drainPendingAsyncWork();
      expect(opened.cubit.state.workingSessionIds, contains(opened.sessionId));

      simulateFingerprintQuietGap(opened.shell);
      opened.cubit.debugTickIdleWatch();
      await drainPendingAsyncWork();

      final shouldClear = {
        CliTool.claude: false,
        CliTool.flashskyai: false,
        CliTool.codex: false,
        CliTool.opencode: false,
        CliTool.cursor: true,
      }[cli]!;
      expect(
        opened.cubit.state.workingSessionIds.isEmpty,
        shouldClear,
        reason: '$cli requiresPtyFallback=$shouldClear',
      );
      await opened.cubit.close();
      await opened.attention.close();
      await deleteTempDirBestEffort(tmpDir(repo));
    });
  }

  test('PTY-quiet fallback never clears a waiting seat', () async {
    final repo = SessionRepository(rootDir: (await Directory.systemTemp.createTemp('tc_wait_')).path);
    final postFrame = PostFrameTestHarness();
    final opened = await openSimpleTurnSession(cli: CliTool.cursor, repo: repo, postFrame: postFrame);
    // waiting (permission) seat
    opened.attention.applyEvent(
      sessionId: opened.sessionId,
      memberId: opened.sessionId,
      event: const AgentStatusEvent(state: AgentSeatAttention.waiting, hookEventName: 'PermissionRequest'),
      skipPermissions: false,
    );
    await drainPendingAsyncWork();
    simulateFingerprintQuietGap(opened.shell);
    opened.cubit.debugTickIdleWatch();
    await drainPendingAsyncWork();
    expect(
      opened.attention.state.attentionFor(sessionId: opened.sessionId, memberId: opened.sessionId),
      AgentSeatAttention.waiting,
    );
    await opened.cubit.close();
    await opened.attention.close();
    await deleteTempDirBestEffort(tmpDir(repo));
  });
}
```

Note: `deleteTempDirBestEffort` and `tmpDir(repo)` are helpers in `integration_test_setup.dart` / the harness — check their exact names and use them, or inline `Directory.systemTemp.createTemp` + delete. Ensure `dart:io` import for `Directory`.

- [ ] **Step 2: Run the matrix, verify cursor fallback test fails first**

Run: `cd client && flutter test test/integration/turn_completion/turn_completion_simple_test.dart -v`
Expected: the `cursor: PTY-quiet fallback` test FAILS (session still working — the bug), others pass. (If `_onTurnEnded` from Task 4 is already merged, this should now pass — order tasks so this is the first run after Task 4.)

- [ ] **Step 3: If the cursor fallback case still fails, fix per Task 4 wiring and re-run**

Expected: PASS for all.

- [ ] **Step 4: Analyze + commit**

```bash
git add client/test/integration/turn_completion/turn_completion_simple_test.dart
git commit -m "test(integration): simple-mode turn completion matrix (5 CLI)"
```

---

### Task 8: Mixed-mode matrix — `/idle`→bus turn end + done-event clears

**Files:**
- Create: `client/test/integration/turn_completion/turn_completion_mixed_test.dart`

**Interfaces:**
- Consumes: harness `openMixedSessionWithShells` / `postMemberIdle` from `session_idle_busy_harness.dart` (already present), `bus.markMemberRunning`, `bus.noteMailDeliverySubmitted`, `CliToolRegistry`.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/integration/turn_completion/turn_completion_mixed_test.dart
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';

import '../../support/post_frame_test_harness.dart';
import '../support/integration_test_setup.dart';
import '../support/session_idle_busy_harness.dart';

void main() {
  setUp(setUpIntegrationAppStorage);
  tearDown(tearDownIntegrationAppStorage);

  test('mixed cursor: /idle ends bus turn and clears working', () async {
    final tmp = await Directory.systemTemp.createTemp('tc_mixed_');
    final repo = SessionRepository(rootDir: tmp.path);
    final postFrame = PostFrameTestHarness();
    final attention = AgentAttentionCubit(pruneInterval: null);
    final cubit = ChatCubit(
      executableResolver: () => 'true',
      automationRepository: testAutomationRepository(),
      sessionRepository: repo,
      postFrameScheduler: postFrame.scheduler,
      agentAttentionCubit: attention,
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) =>
              RunningConnectedFakeShell(executable: executable),
    );

    final opened = await openMixedSessionWithShells(cubit: cubit, repo: repo, postFrame: postFrame);
    final bus = cubit.activeTab!.teamBus!;
    bus.markMemberRunning('worker-1');
    bus.noteMailDeliverySubmitted('worker-1'); // doorbell submitted → in turn
    await drainPendingAsyncWork();
    expect(cubit.state.workingSessionIds, contains(opened.sessionId));

    // Cursor stop hook POSTs /idle → bus turn must end.
    await postMemberIdle(idleEndpointFromMcp(cubit.agentStatusSeatLookup!.endpoint), 'worker-1',
        sessionId: opened.sessionId);

    await drainPendingAsyncWork();
    cubit.debugTickIdleWatch();
    await drainPendingAsyncWork();
    expect(bus.isMemberInTurn('worker-1'), isFalse);
    expect(cubit.state.workingSessionIds, isEmpty);

    await cubit.close();
    await attention.close();
    await deleteTempDirBestEffort(tmp);
  });

  test('mixed claude: /idle no-op while parked (no double TurnEnded)', () async {
    // reuse openMixedSessionWithShells with team cli = claude; park via
    // bus.receive('team-lead'); assert isMemberInTurn false after /idle and
    // no exception / no crash.
  });
}
```

Verify helper names (`idleEndpointFromMcp`, `postMemberIdle`, `markMemberRunning`) against `session_idle_busy_harness.dart` and use the real ones; if `agentStatusSeatLookup` isn't reachable from cubit, compute the `/idle` URI from `cubit.agentStatusSeatLookup` or the harness helper directly.

- [ ] **Step 2: Run and verify cursor mixed case fails first**

Run: `cd client && flutter test test/integration/turn_completion/turn_completion_mixed_test.dart -v`
Expected: the cursor `/idle` case FAILS (`isMemberInTurn` still true) before Task 5 fix; PASS after.

- [ ] **Step 3: Analyze + commit**

```bash
git add client/test/integration/turn_completion/turn_completion_mixed_test.dart
git commit -m "test(integration): mixed-mode turn completion (idle→bus + done)"
```

---

### Task 9: Full-matrix completion + Cursor stop-hook simple-delivery investigation

**Files:**
- Modify: `client/test/integration/turn_completion/turn_completion_simple_test.dart` (extend to full 5×2 with all scenarios if not already)
- Modify: `client/test/integration/turn_completion/turn_completion_mixed_test.dart` (extend done-event cases for all CLIs)
- Create: `client/test/integration/turn_completion/cursor_stop_hook_investigation_test.dart` (investigative, tagged integration or unit)

**Interfaces:**
- Consumes: everything from Tasks 1-8.

- [ ] **Step 1: Complete the full matrix**

Ensure the simple matrix covers: A submit→working, B done→clears, C PTY-fallback→clears (cursor only) for all 5 CLIs; and mixed matrix covers A + B for all 5 CLIs (claude/flashskyai/codex/opencode use `openMixedSessionWithShells` with the respective team cli; cursor uses doorbell). Add any missing cases.

- [ ] **Step 2: Investigate cursor `stop` hook simple-mode delivery**

Write `cursor_stop_hook_investigation_test.dart` that:
- builds a fake cursor HOME via `CursorHomeProvisioner.provision` (unit path, no PTY), with an `agentStatus` endpoint,
- asserts `hooks.json` contains a `stop` entry and the script path exists,
- asserts the script POSTs to a URL with `event=stop`,
- records findings (whether interactive composer emits `stop`, payload `hook_event_name` casing) as comments in the test file or in a short `## Investigation findings` section appended to the spec.
This is investigative — the fallback in Task 4 does not depend on its result.

- [ ] **Step 3: Run the full integration matrix**

Run: `cd client && flutter test test/integration/turn_completion/ -v`
Expected: all PASS.

- [ ] **Step 4: Analyze + full test suite + commit**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
```

```bash
git add client/test/integration/turn_completion/
git commit -m "test(integration): full 5-CLI x 2-mode turn completion matrix + cursor stop-hook investigation"
```

---

## Self-Review

**Spec coverage:**
- TurnCompletionCapability → Task 1 ✓
- clearWorkingIfWorking → Task 2 ✓
- PTY-quiet fallback + doorbell guard → Tasks 3-4 ✓
- /idle→notifyIdle → Task 5 ✓
- Harness binds attention in simple mode → Task 6 ✓
- 5 CLI × simple/mixed × A/B/C matrix + waiting-safe → Tasks 7-9 ✓
- Cursor stop-hook simple-delivery investigation → Task 9 ✓
- Edge cases (waiting not cleared, doorbell defer, race) → Task 2 method + Task 4 guard + Task 7 waiting test ✓
- 30-min TTL unchanged → no task (intentional non-change) ✓

**Placeholder scan:** No TBD/TODO/"implement later" — every step has concrete code or an exact verification command. The two notes ("check `repo.createSession` signature", "verify helper names") are explicit instructions to confirm against existing code, not placeholders for behavior.

**Type consistency:** `TurnCompletionCapability` fields (`doneEventNames`, `requiresPtyFallback`, `usesDoorbellPush`) identical across Task 1, 4, 7. `clearWorkingIfWorking({required String sessionId, required String memberId})` identical in Task 2, 4, 7. `onAfterTurnEnded(String, String)` consistent in Task 3. `notifyIdle` / `endTurnForIdle` consistent in Task 5.
