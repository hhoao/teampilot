# Codex Subagent Parent Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep a Codex parent terminal working and reclaim-protected until every concurrently delegated subagent has stopped.

**Architecture:** Extend managed agent-status hooks to receive subagent lifecycle events. `AgentAttentionCubit` will own a per-seat set of active child IDs plus a deferred-parent-stop flag, so only a real parent completion after the child set empties transitions the seat to done. Existing session working and reclaim code already consume `sessionIsAgentActive`, so no reclaim-policy change is required.

**Tech Stack:** Flutter/Dart, `flutter_test`, TeamPilot managed CLI hooks.

## Global Constraints

- Preserve normal no-subagent `Stop` and `StopFailure` completion behavior.
- Identify children by non-empty hook `agent_id`; duplicate lifecycle events must be idempotent.
- A seat with at least one tracked child must not expire through `agentAttentionStaleAfter`.
- Do not alter unrelated dirty worktree files.

---

## File structure

- `client/lib/models/hook_event.dart` — exposes native `SubagentStart` so managed hook assembly can request it.
- `client/lib/services/cli/registry/config_profile/hook_seat_context_completer.dart` — includes both subagent lifecycle hooks in agent-status entries.
- `client/lib/services/cli/registry/capabilities/claude_family_agent_status_normalizer.dart` — normalizes lifecycle payloads instead of dropping them.
- `client/lib/cubits/agent_attention_cubit.dart` — owns the per-seat child set, deferred parent completion, and stale-entry rule.
- `client/test/services/agent_status/agent_status_normalizer_test.dart` — verifies lifecycle payload normalization.
- `client/test/services/cli/codex/codex_hook_writer_test.dart` — verifies Codex writes both lifecycle hook sections.
- `client/test/cubits/agent_attention_cubit_test.dart` — locks the concurrent-child state machine and TTL behavior.

### Task 1: Deliver Codex subagent lifecycle events to agent-status

**Files:**

- Modify: `client/lib/models/hook_event.dart`
- Modify: `client/lib/services/cli/registry/config_profile/hook_seat_context_completer.dart`
- Modify: `client/lib/services/cli/registry/capabilities/claude_family_agent_status_normalizer.dart`
- Modify: `client/test/services/agent_status/agent_status_normalizer_test.dart`
- Modify: `client/test/services/cli/codex/codex_hook_writer_test.dart`

**Interfaces:**

- Produces normalized `AgentStatusEvent` values whose `hookEventName` is `SubagentStart` or `SubagentStop` and whose `toolAgentId` comes from `agent_id`.
- Produces Codex `[[hooks.SubagentStart]]` and `[[hooks.SubagentStop]]` command-hook sections.

- [ ] **Step 1: Write failing normalizer and writer tests**

```dart
test('Codex SubagentStart and SubagentStop retain the child id', () {
  for (final name in ['SubagentStart', 'SubagentStop']) {
    final event = AgentStatusNormalizer.normalize(
      cli: CliTool.codex,
      body: {'hook_event_name': name, 'agent_id': 'child-a'},
    );
    expect(event?.hookEventName, name);
    expect(event?.toolAgentId, 'child-a');
  }
});

expect(toml, contains('[[hooks.SubagentStart]]'));
expect(toml, contains('[[hooks.SubagentStop]]'));
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/agent_status/agent_status_normalizer_test.dart test/services/cli/codex/codex_hook_writer_test.dart`

Expected: FAIL because lifecycle events are discarded and `SubagentStart` is not a managed hook.

- [ ] **Step 3: Add the managed event and normalizer support**

```dart
// HookEvent values and Codex support map
subagentStart,
// CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'SubagentStart')

// HookSeatContextCompleter.agentStatusEvents
HookEvent.subagentStart,
HookEvent.subagentStop,

// ClaudeFamilyAgentStatusNormalizer.normalize
if (eventName == 'SubagentStart' || eventName == 'SubagentStop') {
  return build(AgentSeatAttention.working);
}
```

Keep lifecycle events as `working`; Task 2 interprets their names and must not treat child completion as generic parent completion.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/agent_status/agent_status_normalizer_test.dart test/services/cli/codex/codex_hook_writer_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/hook_event.dart client/lib/services/cli/registry/config_profile/hook_seat_context_completer.dart client/lib/services/cli/registry/capabilities/claude_family_agent_status_normalizer.dart client/test/services/agent_status/agent_status_normalizer_test.dart client/test/services/cli/codex/codex_hook_writer_test.dart
git commit -m "fix: forward codex subagent lifecycle hooks"
```

### Task 2: Keep the parent attention working until all children finish

**Files:**

- Modify: `client/lib/cubits/agent_attention_cubit.dart`
- Modify: `client/test/cubits/agent_attention_cubit_test.dart`

**Interfaces:**

- `AgentSeatAttentionEntry` gains immutable `activeSubagentIds` and `parentStopPending` fields.
- `AgentAttentionCubit.applyEvent` applies the lifecycle transition before generic attention handling.

- [ ] **Step 1: Write failing parent/child state-machine tests**

```dart
void child(AgentAttentionCubit c, String event, String id) => c.applyEvent(
  sessionId: 's1', memberId: 'm1', skipPermissions: false,
  event: AgentStatusEvent(
    state: AgentSeatAttention.working,
    hookEventName: event,
    toolAgentId: id,
  ),
);

test('parent Stop waits for all parallel subagents', () {
  final c = _cubit();
  child(c, 'SubagentStart', 'a');
  child(c, 'SubagentStart', 'b');
  c.applyEvent(sessionId: 's1', memberId: 'm1', skipPermissions: false,
      event: const AgentStatusEvent(state: AgentSeatAttention.done, hookEventName: 'Stop'));
  child(c, 'SubagentStop', 'a');
  expect(c.state.sessionIsAgentActive('s1'), isTrue);
  child(c, 'SubagentStop', 'b');
  expect(c.state.sessionIsAgentActive('s1'), isFalse);
});
```

Also add isolated tests for an ordinary `Stop` with no child, duplicate start/stop, `UserPromptSubmit` cleanup, and child activity past `agentAttentionStaleAfter`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/agent_attention_cubit_test.dart`

Expected: FAIL because the first `Stop` stores `done` and `SubagentStop` does not preserve working state.

- [ ] **Step 3: Implement the immutable child-aware transition**

```dart
class AgentSeatAttentionEntry extends Equatable {
  const AgentSeatAttentionEntry({
    required this.attention, required this.updatedAt,
    this.activeSubagentIds = const {}, this.parentStopPending = false,
    // existing fields...
  });
}

// SubagentStart + nonempty id: add id and store working.
// SubagentStop + nonempty id: remove id; emit done only when empty and
// parentStopPending is true, otherwise retain working.
// Parent Stop/StopFailure: store working + parentStopPending when child ids
// are nonempty; otherwise use the existing done path.
```

Make `_isStale` return false while `activeSubagentIds.isNotEmpty`. `clearSeat`, `clearSession`, and `UserPromptSubmit` must clear child IDs and pending completion so they cannot cross a parent-turn boundary.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/agent_attention_cubit_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/agent_attention_cubit.dart client/test/cubits/agent_attention_cubit_test.dart
git commit -m "fix: retain parent activity for codex subagents"
```

### Task 3: Verify working aggregation and reclaim protection end-to-end

**Files:**

- Modify: `client/test/integration/session_idle_busy_integration_test.dart`

**Interfaces:**

- Consumes `AgentAttentionState.sessionIsAgentActive` from Task 2 through the existing `TabWorkingAggregator` and reclaim guard.
- Produces an integration regression showing a parent terminal remains busy after one of two children stops.

- [ ] **Step 1: Write the failing integration test**

```dart
testWidgets('parallel child activity keeps the parent session working', (tester) async {
  // Open the existing one-seat harness and apply SubagentStart for a and b.
  // Apply parent Stop then SubagentStop for a.
  expect(chat.state.workingSessionIds, contains(session.sessionId));
  // Apply SubagentStop for b and pump the attention subscription.
  expect(chat.state.workingSessionIds, isNot(contains(session.sessionId));
});
```

- [ ] **Step 2: Run test to verify it fails before Task 2 is applied**

Run: `cd client && flutter test test/integration/session_idle_busy_integration_test.dart`

Expected: FAIL on the assertion after the first child stops when run against the pre-Task-2 behavior; after Task 2 it is retained as a regression test and passes.

- [ ] **Step 3: Run the integration test after Tasks 1–2 and verify it passes**

Run: `cd client && flutter test test/integration/session_idle_busy_integration_test.dart`

Expected: PASS; no production change should be needed because `TabWorkingAggregator` and `TabMemberReclaimWatch` already use attention activity.

- [ ] **Step 4: Run required verification**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`

Expected: analyzer exits 0 and the full test runner reports success.

- [ ] **Step 5: Commit**

```bash
git add client/test/integration/session_idle_busy_integration_test.dart docs/superpowers/specs/2026-08-25-codex-subagent-parent-activity-design.md docs/superpowers/plans/2026-08-25-codex-subagent-parent-activity.md
git commit -m "test: cover codex parent activity retention"
```
