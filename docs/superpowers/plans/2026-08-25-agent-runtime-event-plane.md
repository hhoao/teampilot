# Agent Runtime Event Plane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace direct hook-to-PTY coupling with durable seat events and a prompt-delivery state machine that cannot submit an ACK-confirmed Codex prompt twice.

**Architecture:** A global gateway resolves the seat CLI, normalizes native hook payloads through a CLI capability, appends events to a durable seat journal, then publishes them to projections. A durable delivery coordinator owns every automated PTY input command; the terminal command queue checks its delivery fence immediately before each write.

**Tech Stack:** Flutter/Dart, flutter_bloc, local session-runtime files, existing loopback HTTP gateway, package:test.

## Global Constraints

- Remove `PromptSubmitAckTracker`, `AgentStatusHttpHandler`, and their compatibility constructors.
- Do not switch on `CliTool` outside CLI capability implementations.
- Serialize events and non-terminal prompt deliveries per `(sessionId, memberId)`.
- Persist every delivery transition before its externally-visible PTY write.
- A confirmed delivery can never perform another automatic CR or paste.
- On restart, an unconfirmed submitted delivery becomes `submittedUnknown`; it never re-pastes automatically.
- Use deterministic test fakes and clocks, not a live Codex binary.

---

## File map

| Path | Responsibility |
|---|---|
| `client/lib/services/agent_runtime/runtime_event.dart` | Event envelope, seat key, event kinds, correlation strength. |
| `client/lib/services/agent_runtime/runtime_event_journal.dart` | Durable append/replay by seat. |
| `client/lib/services/agent_runtime/seat_event_stream.dart` | Ordered in-memory publication for one seat. |
| `client/lib/services/agent_runtime/agent_event_gateway.dart` | HTTP ingress: normalize, journal, publish, and respond. |
| `client/lib/services/agent_runtime/runtime_event_projection.dart` | Attention, question, and plan projections. |
| `client/lib/services/prompt_delivery/prompt_delivery.dart` | Delivery model and state transitions. |
| `client/lib/services/prompt_delivery/prompt_delivery_store.dart` | Durable delivery records. |
| `client/lib/services/prompt_delivery/prompt_delivery_coordinator.dart` | Delivery/event state machine. |
| `client/lib/services/terminal/terminal_input_command_queue.dart` | Serialized input commands with execution fences. |
| `client/lib/cubits/chat/tab_member_pty_delivery.dart` | Delegates direct user PTY input to the coordinator. |

### Task 1: Runtime event model, journal, and stream

**Files:**
- Create: `client/lib/services/agent_runtime/runtime_event.dart`
- Create: `client/lib/services/agent_runtime/runtime_event_journal.dart`
- Create: `client/lib/services/agent_runtime/seat_event_stream.dart`
- Test: `client/test/services/agent_runtime/runtime_event_journal_test.dart`
- Test: `client/test/services/agent_runtime/seat_event_stream_test.dart`

**Interfaces:** Produces `RuntimeSeatKey`, `RuntimeEventEnvelope`, `RuntimeEventEnvelopeDraft`, `RuntimeEventJournal.append`, and `SeatEventStream.eventsFor`.

- [ ] **Step 1: Write the failing journal test.**

```dart
test('append assigns sequences per seat and replays in order', () async {
  final journal = MemoryRuntimeEventJournal();
  const seat = RuntimeSeatKey(sessionId: 's', memberId: 'm');
  final one = await journal.append(RuntimeEventEnvelopeDraft.promptSubmitted(
    seat: seat, cli: CliTool.codex, prompt: 'one', occurredAt: DateTime(2026),
  ));
  final two = await journal.append(RuntimeEventEnvelopeDraft.promptSubmitted(
    seat: seat, cli: CliTool.codex, prompt: 'two', occurredAt: DateTime(2026),
  ));
  expect([one.sequence, two.sequence], [1, 2]);
  expect(await journal.replay(seat).toList(), [one, two]);
});
```

- [ ] **Step 2: Verify RED.**

Run: `cd client && flutter test test/services/agent_runtime/runtime_event_journal_test.dart`

Expected: compilation failure naming `MemoryRuntimeEventJournal` or `RuntimeSeatKey`.

- [ ] **Step 3: Implement the minimum journal contract.**

```dart
abstract interface class RuntimeEventJournal {
  Future<RuntimeEventEnvelope> append(RuntimeEventEnvelopeDraft draft);
  Stream<RuntimeEventEnvelope> replay(RuntimeSeatKey seat, {int afterSequence = 0});
}
```

Implement memory and newline-delimited-JSON file journals. Assign each seat sequence during append and write the record before publishing it.

- [ ] **Step 4: Write and run the failing-then-passing stream test.**

```dart
test('stream receives only its seat in sequence order', () async {
  final stream = SeatEventStream();
  final seen = <int>[];
  final sub = stream.eventsFor(const RuntimeSeatKey(sessionId: 's', memberId: 'a'))
      .listen((event) => seen.add(event.sequence));
  stream.publish(eventFor(memberId: 'b', sequence: 1));
  stream.publish(eventFor(memberId: 'a', sequence: 1));
  stream.publish(eventFor(memberId: 'a', sequence: 2));
  await pumpEventQueue();
  expect(seen, [1, 2]);
  await sub.cancel();
});
```

Run: `cd client && flutter test test/services/agent_runtime/runtime_event_journal_test.dart test/services/agent_runtime/seat_event_stream_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add client/lib/services/agent_runtime client/test/services/agent_runtime
git commit -m "feat(runtime): add durable seat event primitives"
```

### Task 2: Capability-owned runtime-event normalization

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/runtime_event_capability.dart`
- Modify: `client/lib/services/cli/*/capabilities/chat_interaction.dart`
- Modify: `client/lib/services/cli/registry/tools/*.dart`
- Delete: `client/lib/services/agent_status/agent_status_normalizer.dart`
- Test: `client/test/services/agent_runtime/runtime_event_adapter_test.dart`

**Interfaces:** Produces `RuntimeEventCapability.normalizeRuntimeEvent(raw, seat, occurredAt)` and `RuntimeCorrelationStrength`.

- [ ] **Step 1: Write the failing Codex adapter test.**

```dart
test('Codex UserPromptSubmit becomes a serialized promptSubmitted event', () {
  final event = registry.capability<RuntimeEventCapability>(CliTool.codex)!
      .normalizeRuntimeEvent(
        {'hook_event_name': 'UserPromptSubmit', 'prompt': 'ship it'},
        seat,
        now,
      );
  expect(event!.kind, RuntimeEventKind.promptSubmitted);
  expect(event.prompt, 'ship it');
  expect(event.correlationStrength, RuntimeCorrelationStrength.serializedPromptEpoch);
});
```

- [ ] **Step 2: Verify RED.**

Run: `cd client && flutter test test/services/agent_runtime/runtime_event_adapter_test.dart`

Expected: compilation failure naming `RuntimeEventCapability`.

- [ ] **Step 3: Implement the new capability and migrate all five CLI definitions.**

```dart
abstract interface class RuntimeEventCapability {
  RuntimeEventEnvelopeDraft? normalizeRuntimeEvent(
    Map<String, Object?> raw,
    RuntimeSeatKey seat,
    DateTime occurredAt,
  );
  RuntimeCorrelationStrength get promptCorrelationStrength;
}
```

Reuse existing per-CLI parsers. Move each legacy `AgentStatusEvent` assertion into the adapter test and delete the legacy normalizer.

- [ ] **Step 4: Verify GREEN and commit.**

Run: `cd client && flutter test test/services/agent_runtime/runtime_event_adapter_test.dart`

```bash
git add client/lib/services/cli client/lib/services/agent_runtime client/test/services
git commit -m "feat(runtime): normalize hooks through CLI capabilities"
```

### Task 3: Global runtime event gateway and projections

**Files:**
- Create: `client/lib/services/agent_runtime/agent_event_gateway.dart`
- Create: `client/lib/services/agent_runtime/runtime_event_projection.dart`
- Modify: `client/lib/services/agent_status/ask_user_question_hook_gate.dart`
- Modify: `client/lib/services/agent_status/exit_plan_mode_hook_gate.dart`
- Delete: `client/lib/services/agent_status/agent_status_http_handler.dart`
- Test: `client/test/services/agent_runtime/agent_event_gateway_test.dart`
- Test: `client/test/services/agent_runtime/runtime_event_projection_test.dart`

**Interfaces:** Produces `AgentEventGateway.handle` and `RuntimeEventProjection.attach`.

- [ ] **Step 1: Write the failing gateway idempotency test.**

```dart
test('gateway journals before publishing and ignores a duplicate native event id', () async {
  await gateway.handleJson(seat, {'id': 'native-1', 'hook_event_name': 'UserPromptSubmit', 'prompt': 'x'});
  await gateway.handleJson(seat, {'id': 'native-1', 'hook_event_name': 'UserPromptSubmit', 'prompt': 'x'});
  expect(await journal.replay(seat).toList(), hasLength(1));
  expect(attention.events.single.kind, RuntimeEventKind.promptSubmitted);
});
```

- [ ] **Step 2: Verify RED.**

Run: `cd client && flutter test test/services/agent_runtime/agent_event_gateway_test.dart`

Expected: compilation failure naming `AgentEventGateway`.

- [ ] **Step 3: Implement journal-before-publish ingress and idempotent projections.**

```dart
Future<void> ingest(RuntimeEventEnvelopeDraft draft) async {
  final event = await journal.append(draft);
  stream.publish(event);
}
```

Attach attention, question, and plan projections to seat streams. Each stores a per-seat sequence cursor and ignores already-applied records.

- [ ] **Step 4: Verify GREEN and commit.**

Run: `cd client && flutter test test/services/agent_runtime/agent_event_gateway_test.dart test/services/agent_runtime/runtime_event_projection_test.dart`

```bash
git add client/lib/services/agent_runtime client/lib/services/agent_status client/test/services
git commit -m "feat(runtime): route agent hooks through event gateway"
```

### Task 4: Durable prompt-delivery state machine

**Files:**
- Create: `client/lib/services/prompt_delivery/prompt_delivery.dart`
- Create: `client/lib/services/prompt_delivery/prompt_delivery_store.dart`
- Create: `client/lib/services/prompt_delivery/prompt_delivery_coordinator.dart`
- Test: `client/test/services/prompt_delivery/prompt_delivery_coordinator_test.dart`
- Test: `client/test/services/prompt_delivery/prompt_delivery_store_test.dart`

**Interfaces:** Produces `PromptDeliveryCoordinator.submit`, `onRuntimeEvent`, and durable delivery records.

- [ ] **Step 1: Write the failing same-text correlation test.**

```dart
test('same text confirms only the active seat epoch', () async {
  final first = await coordinator.submit(request(text: 'same'));
  await coordinator.onRuntimeEvent(promptSubmitted(text: 'same'));
  final second = await coordinator.submit(request(text: 'same'));
  expect((await store.read(first.id)).state, PromptDeliveryState.confirmed);
  expect((await store.read(second.id)).state, PromptDeliveryState.created);
});
```

- [ ] **Step 2: Verify RED.**

Run: `cd client && flutter test test/services/prompt_delivery/prompt_delivery_coordinator_test.dart`

Expected: compilation failure naming `PromptDeliveryCoordinator`.

- [ ] **Step 3: Implement the state machine and durable store.**

```dart
enum PromptDeliveryState {
  created, waitingForInputSurface, staged, submitIssued,
  confirmed, submittedUnknown, failed,
}
```

Persist every state transition. Permit one non-terminal delivery per seat. For adapters without exact IDs, store a monotonically increasing prompt epoch and match only the active epoch's normalized text.

- [ ] **Step 4: Write and verify restart recovery.**

```dart
test('submitIssued restores as submittedUnknown without a new PTY command', () async {
  await store.save(delivery(state: PromptDeliveryState.submitIssued));
  final restored = PromptDeliveryCoordinator(store: store, commands: commands);
  await restored.restoreSeat(seat);
  expect((await store.read('d1')).state, PromptDeliveryState.submittedUnknown);
  expect(commands.writes, isEmpty);
});
```

Run: `cd client && flutter test test/services/prompt_delivery/prompt_delivery_coordinator_test.dart test/services/prompt_delivery/prompt_delivery_store_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add client/lib/services/prompt_delivery client/test/services/prompt_delivery
git commit -m "feat(delivery): add durable prompt state machine"
```

### Task 5: Fence-checked terminal input commands

**Files:**
- Create: `client/lib/services/terminal/terminal_input_command_queue.dart`
- Modify: `client/lib/services/terminal/terminal_input_controller.dart`
- Modify: `client/lib/services/terminal/terminal_fullscreen_input_channel.dart`
- Modify: `client/lib/services/terminal/fullscreen_pty_automation.dart`
- Test: `client/test/services/terminal/terminal_input_command_queue_test.dart`
- Test: `client/test/services/terminal/fullscreen_pty_automation_test.dart`

**Interfaces:** Consumes a `bool Function() canExecute` fence. Produces `TerminalInputCommandQueue.enqueue`.

- [ ] **Step 1: Write the failing queued-CR cancellation test.**

```dart
test('confirmation before queued CR execution drops that CR', () async {
  var confirmed = false;
  final queue = TerminalInputCommandQueue(write: writes.add);
  await queue.enqueue(TerminalInputCommand.bytes('paste', canExecute: () => true));
  final queuedCr = queue.enqueue(TerminalInputCommand.bytes('\r', canExecute: () => !confirmed));
  confirmed = true;
  expect(await queuedCr, TerminalInputCommandResult.dropped);
  expect(writes, ['paste']);
});
```

- [ ] **Step 2: Verify RED.**

Run: `cd client && flutter test test/services/terminal/terminal_input_command_queue_test.dart`

Expected: compilation failure naming `TerminalInputCommandQueue`.

- [ ] **Step 3: Implement command queue and remove terminal-owned retry loops.**

```dart
final class TerminalInputCommand {
  const TerminalInputCommand.bytes(this.bytes, {required this.canExecute});
  final String bytes;
  final bool Function() canExecute;
}
```

Evaluate `canExecute` inside the serial queue immediately before the actual PTY write. Full-screen automation may stage and issue the first CR, but it cannot own retry scheduling or re-paste decisions.

- [ ] **Step 4: Write and verify the delayed-hook regression.**

```dart
test('hook confirmation after first CR prevents all later automated CRs', () async {
  await harness.stageAndSubmit();
  harness.confirmPrompt();
  await harness.flush();
  expect(harness.writes.where((write) => write == '\r'), hasLength(1));
});
```

Run: `cd client && flutter test test/services/terminal/terminal_input_command_queue_test.dart test/services/terminal/fullscreen_pty_automation_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add client/lib/services/terminal client/test/services/terminal
git commit -m "feat(terminal): fence queued input commands"
```

### Task 6: Replace tab PTY delivery and legacy retry ownership

**Files:**
- Modify: `client/lib/cubits/chat/tab_member_pty_delivery.dart`
- Modify: `client/lib/cubits/chat/tab_session_runtime_coordinator.dart`
- Modify: `client/lib/services/terminal/member_pty_inject_service.dart`
- Delete: `client/lib/services/terminal/prompt_submit_ack_tracker.dart`
- Delete: `client/lib/services/terminal/pty_automation_retry_queue.dart`
- Delete: `client/lib/services/terminal/pty_automation_session_lock.dart`
- Test: `client/test/cubits/chat/tab_member_pty_delivery_test.dart`

**Interfaces:** Tab delivery consumes `PromptDeliveryCoordinator.submit`; mailbox doorbells remain TeamBus behavior, while direct user input always returns a durable delivery id.

- [ ] **Step 1: Write the failing landing-send regression test.**

```dart
test('one landing send with delayed Codex confirmation has one submit', () async {
  await harness.delivery.deliverUserCommandToMember('s', 'm', 'inspect this', directToPty: true);
  await harness.publishCodexPromptSubmitted('inspect this');
  await harness.flushQueuedAutomation();
  expect(harness.pty.submittedPrompts, ['inspect this']);
});
```

- [ ] **Step 2: Verify RED.**

Run: `cd client && flutter test test/cubits/chat/tab_member_pty_delivery_test.dart`

Expected: FAIL under the legacy retry path or fail to compile until the coordinator seam exists.

- [ ] **Step 3: Delegate direct PTY input to the coordinator.**

```dart
Future<String?> deliverUserCommandToMember(...) =>
  _promptDeliveries.submit(PromptDeliveryRequest(seat: seat, text: message, cli: cli))
      .then((delivery) => delivery.id);
```

Remove tracker checks, retry ticks, and `MemberPtyInjectService` retry ownership. Keep TeamBus mailbox delivery separate from human prompt delivery.

- [ ] **Step 4: Verify GREEN and commit.**

Run: `cd client && flutter test test/cubits/chat/tab_member_pty_delivery_test.dart test/cubits/chat/tab_member_pty_delivery_abort_test.dart test/services/terminal/member_pty_inject_service_test.dart`

```bash
git add client/lib/cubits/chat client/lib/services/terminal client/test/cubits/chat client/test/services/terminal
git commit -m "refactor(delivery): route tab input through coordinator"
```

### Task 7: Compose per-session runtime and recovery UI

**Files:**
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/services/team_bus/teammate_bus_mcp_gateway.dart`
- Modify: `client/lib/services/launch/session_lifecycle_service.dart`
- Modify: `client/lib/pages/chat/session_chat_compose_section.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Test: `client/test/cubits/chat/session_launch_host_agent_status_test.dart`
- Test: `client/test/pages/chat/prompt_delivery_recovery_test.dart`

**Interfaces:** Produces one app-scoped runtime gateway and per-session journal/store. The compose section consumes `submittedUnknown` and creates a new delivery only after explicit user retry.

- [ ] **Step 1: Write the failing composition and recovery tests.**

```dart
test('hook confirms delivery and updates attention projection', () async {
  await harness.submit(seat, 'hello');
  await harness.postHook(seat, {'hook_event_name': 'UserPromptSubmit', 'prompt': 'hello'});
  expect((await harness.deliveryStore.activeFor(seat)).single.state, PromptDeliveryState.confirmed);
  expect(harness.attention.stateFor(seat).isWorking, isTrue);
});

testWidgets('submittedUnknown offers review and retry without automatic PTY write', (tester) async {
  await tester.pumpWidget(harness(state: PromptDeliveryState.submittedUnknown));
  expect(find.text('Delivery status unknown'), findsOneWidget);
  expect(harness.ptyWrites, isEmpty);
});
```

- [ ] **Step 2: Verify RED.**

Run: `cd client && flutter test test/cubits/chat/session_launch_host_agent_status_test.dart test/pages/chat/prompt_delivery_recovery_test.dart`

Expected: FAIL because app shell still wires the legacy HTTP handler and no recovery UI exists.

- [ ] **Step 3: Compose the event plane and runtime lifecycle.**

```dart
final agentRuntime = AgentRuntime(
  gateway: AgentEventGateway(...),
  projections: [attentionProjection, askProjection, exitPlanProjection],
  promptDeliveries: PromptDeliveryCoordinator(...),
);
```

Open/replay the journal and delivery store before enabling a session's input. Add localized unknown-status and review/retry text. Retry explicitly creates a new delivery id; it never resumes the old one.

- [ ] **Step 4: Run focused and required full verification.**

Run: `cd client && flutter test test/services/agent_runtime test/services/prompt_delivery test/services/terminal test/cubits/chat/tab_member_pty_delivery_test.dart test/pages/chat/prompt_delivery_recovery_test.dart && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`

Expected: all commands exit 0.

- [ ] **Step 5: Verify removal and commit.**

Run: `rg -n 'PromptSubmitAckTracker|AgentStatusHttpHandler|PtyAutomationRetryQueue' client/lib client/test`

Expected: no matches.

```bash
git add client/lib client/test
git commit -m "feat(runtime): complete durable prompt event plane"
```

## Plan self-review

Tasks 1–3 implement durable ingress, ordered streams, adapter boundaries, and projections. Tasks 4–6 implement persistent delivery state, correlation, write fences, and the exact delayed-ACK duplication regression. Task 7 composes lifecycle, persistence, recovery UI, and project-wide verification. Every type referenced by a later task is first produced by an earlier task; no legacy compatibility facade remains.

