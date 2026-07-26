# Virgin Lead Idle-Announce Doorbell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ring the PTY doorbell for at-prompt members even when they have never started a turn and unread mail is only `idle_notification`.

**Architecture:** Delete the virgin-lead suppression gate in `PresenceReducer._onMail` and remove the `hasEverBeenActive` / `unreadIsIdleOnly` plumbing that existed only for that gate. Flip unit tests; update CLI matrix harness comments / ordering so History compose still works after worker park may doorbell the lead.

**Tech Stack:** Dart / Flutter (`flutter_test`), TeamBus presence reducer

**Spec:** `docs/superpowers/specs/2026-07-26-virgin-lead-idle-doorbell-design.md`

---

## File map

| File | Role |
|------|------|
| `client/lib/services/team_bus/state/presence_reducer.dart` | Remove virgin gate + context fields |
| `client/lib/services/team_bus/agent_node.dart` | Remove `hasEverBeenActive` |
| `client/lib/services/team_bus/team_bus.dart` | Stop passing / setting / computing virgin helpers |
| `client/test/services/team_bus/state/presence_reducer_test.dart` | Flip / simplify MailArrived virgin cases |
| `client/test/services/team_bus/team_bus_idle_doorbell_test.dart` | Flip idle→doorbell; drop `hasEverBeenActive` asserts |
| `client/test/services/team_bus/idle_notification_test.dart` | Flip woken empty → woken lead |
| `client/test/integration/support/cli_message_matrix_harness.dart` | Doc + tolerate doorbell after park |
| `client/test/integration/cli_message_matrix_*_test.dart` | Update virgin-suppression comments |

---

### Task 1: Failing reducer test (TDD)

**Files:**
- Modify: `client/test/services/team_bus/state/presence_reducer_test.dart`

- [ ] **Step 1: Flip the virgin idle-only case to expect a doorbell**

Replace:

```dart
    test('virgin at-prompt + idle-only unread → no doorbell', () {
      final t = _run(
        _atPrompt,
        const MailArrived(),
        hasUnread: true,
        hasEverBeenActive: false,
        unreadIsIdleOnly: true,
      );
      expect(t.presence, _atPrompt);
      expect(t.effects, isEmpty);
    });
```

with:

```dart
    test('at-prompt + idle-only unread → doorbell', () {
      final t = _run(
        _atPrompt,
        const MailArrived(),
        hasUnread: true,
        hasEverBeenActive: false,
        unreadIsIdleOnly: true,
      );
      expect(t.presence, _atPrompt);
      expect(t.effects.single, isA<DoorbellEffect>());
    });
```

Keep the sibling `virgin at-prompt + non-idle unread → doorbell` test as-is for now (still passes; removed in Task 3 cleanup).

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd client && flutter test test/services/team_bus/state/presence_reducer_test.dart --name "idle-only"
```

Expected: FAIL — effects empty / no `DoorbellEffect` (gate still present).

- [ ] **Step 3: Commit failing test expectation**

```bash
git add client/test/services/team_bus/state/presence_reducer_test.dart
git commit -m "$(cat <<'EOF'
test(team-bus): expect doorbell for idle-only at-prompt mail

EOF
)"
```

---

### Task 2: Remove virgin gate (make reducer test pass)

**Files:**
- Modify: `client/lib/services/team_bus/state/presence_reducer.dart`

- [ ] **Step 1: Delete the virgin suppression line and its comment**

In `_onMail`, remove:

```dart
    // Virgin seat + idle-announce only: queue without PTY doorbell so operator
    // History compose — not worker park idle — starts the first turn. Ordinary
    // teammate mail (pong / task updates) still rings so L3 collab works.
    if (!ctx.hasEverBeenActive && ctx.unreadIsIdleOnly) return _stay(s);
```

Leave the mid-turn / parked / doorbelled guards and the `DoorbellEffect` return.

- [ ] **Step 2: Re-run reducer test — expect PASS**

```bash
cd client && flutter test test/services/team_bus/state/presence_reducer_test.dart --name "idle-only"
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add client/lib/services/team_bus/state/presence_reducer.dart
git commit -m "$(cat <<'EOF'
fix(team-bus): doorbell at-prompt idle announce for virgin seats

EOF
)"
```

---

### Task 3: Delete virgin plumbing + update unit tests

**Files:**
- Modify: `client/lib/services/team_bus/state/presence_reducer.dart`
- Modify: `client/lib/services/team_bus/agent_node.dart`
- Modify: `client/lib/services/team_bus/team_bus.dart`
- Modify: `client/test/services/team_bus/state/presence_reducer_test.dart`
- Modify: `client/test/services/team_bus/team_bus_idle_doorbell_test.dart`
- Modify: `client/test/services/team_bus/idle_notification_test.dart`

- [ ] **Step 1: Strip `PresenceContext` fields**

Remove `hasEverBeenActive` and `unreadIsIdleOnly` from the constructor, fields, and dartdoc in `presence_reducer.dart`.

- [ ] **Step 2: Strip `AgentNode.hasEverBeenActive`**

In `agent_node.dart`:
- Remove constructor body that sets `hasEverBeenActive = true` when `activity == active`
- Remove the field and its dartdoc

- [ ] **Step 3: Strip `TeamBus` wiring**

In `team_bus.dart` `_reduce`:
- Stop passing `hasEverBeenActive` / `unreadIsIdleOnly` into `PresenceContext`
- Remove the `TurnStarted` → `node.hasEverBeenActive = true` block

Delete `_unreadIsIdleOnly` entirely (keep `IdleNotification` import — still used by `_announceWorkerIdleToLead`).

- [ ] **Step 4: Clean `presence_reducer_test` helpers**

Remove `hasEverBeenActive` / `unreadIsIdleOnly` params from `_run` and `PresenceContext(...)`.

Merge the two virgin cases into one at-prompt doorbell case if redundant, or drop the non-idle virgin sibling once params are gone — keep a single:

```dart
    test('at-prompt + unread → doorbell, presence stays at-prompt', () {
      final t = _run(_atPrompt, const MailArrived(), hasUnread: true);
      expect(t.presence, _atPrompt);
      expect(t.effects.single, isA<DoorbellEffect>());
    });
```

(Delete the old idle-only / non-idle virgin duplicates if they only differed by removed params.)

- [ ] **Step 5: Flip `team_bus_idle_doorbell_test`**

Rename and change:

```dart
  test('worker idle announce doorbells virgin lead at prompt', () {
    fakeAsync((async) {
      // ... same setup with lead turnDoneReady ...
      unawaited(bus.receiveWork('worker'));
      async.flushMicrotasks();

      expect(bus.memberById('lead')!.inbox.unreadCount, 1);
      expect(
        launcher.woken.where((w) => w.memberId == 'lead').single.notice,
        TeamBus.doorbellNotice,
      );
    });
  });
```

Remove **all** `hasEverBeenActive` expects in this file (the renamed idle
test and `non-idle mail still doorbells virgin lead at prompt`).

- [ ] **Step 6: Flip `idle_notification_test`**

In `onMemberIdle delivers idle_notification to team-lead mailbox`, replace the empty woken assert + virgin comment with:

```dart
    expect(
      launcher.woken.where((w) => w.memberId == 'team-lead').single.notice,
      TeamBus.doorbellNotice,
    );
```

Keep the mid-turn test (`does not doorbell team-lead mid-turn`) unchanged.

- [ ] **Step 7: Run unit tests**

```bash
cd client && flutter test \
  test/services/team_bus/state/presence_reducer_test.dart \
  test/services/team_bus/team_bus_idle_doorbell_test.dart \
  test/services/team_bus/idle_notification_test.dart
```

Expected: all PASS. Also:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/services/team_bus/state/presence_reducer.dart \
  lib/services/team_bus/agent_node.dart \
  lib/services/team_bus/team_bus.dart
```

Expected: no errors about undefined `hasEverBeenActive` / `unreadIsIdleOnly`.

- [ ] **Step 8: Commit**

```bash
git add client/lib/services/team_bus/state/presence_reducer.dart \
  client/lib/services/team_bus/agent_node.dart \
  client/lib/services/team_bus/team_bus.dart \
  client/test/services/team_bus/state/presence_reducer_test.dart \
  client/test/services/team_bus/team_bus_idle_doorbell_test.dart \
  client/test/services/team_bus/idle_notification_test.dart
git commit -m "$(cat <<'EOF'
refactor(team-bus): remove virgin-lead idle doorbell plumbing

EOF
)"
```

---

### Task 4: CLI matrix harness + comments

**Files:**
- Modify: `client/test/integration/support/cli_message_matrix_harness.dart`
- Modify: `client/test/integration/cli_message_matrix_claude_test.dart`
- Modify: `client/test/integration/cli_message_matrix_codex_test.dart`
- Modify: `client/test/integration/cli_message_matrix_flashskyai_test.dart`
- Modify: `client/test/integration/cli_message_matrix_opencode_test.dart`

- [ ] **Step 1: Update `parkWorkerAndComposeOnLead` dartdoc**

Replace the virgin-suppression paragraph with:

```dart
  /// Parks the worker, then [submitCompose] on the lead (recipe order).
  ///
  /// Worker idle-announce may PTY-doorbell a lead still at prompt (including
  /// seats that have never turned). [bootComposeSeatToPrompt] waits until the
  /// lead is ready for History compose afterward.
```

- [ ] **Step 2: If compose becomes flaky after doorbell**

Prefer switching mixed cells from `parkWorkerAndComposeOnLead` to
`composeOnLeadThenParkWorker` (already documented as the alternate order).
Only do this if Step 3 shows compose failures; do not change order
speculatively.

- [ ] **Step 3: Update matrix test comments**

In each of the four `cli_message_matrix_*_test.dart` mixed cells, replace:

```dart
        // Park worker first (recipe order); virgin-lead idle mail is queued
        // without PTY doorbell so History compose starts the lead turn.
```

with:

```dart
        // Park worker first (recipe order); idle-announce may doorbell the
        // lead — compose runs after bootComposeSeatToPrompt.
```

- [ ] **Step 4: Commit**

```bash
git add client/test/integration/support/cli_message_matrix_harness.dart \
  client/test/integration/cli_message_matrix_claude_test.dart \
  client/test/integration/cli_message_matrix_codex_test.dart \
  client/test/integration/cli_message_matrix_flashskyai_test.dart \
  client/test/integration/cli_message_matrix_opencode_test.dart
git commit -m "$(cat <<'EOF'
test(matrix): document idle doorbell after worker park

EOF
)"
```

Note: full CLI matrix integration tests are optional here (native CLI + gateway).
Unit coverage in Tasks 1–3 is the required verification gate.

---

### Task 5: Final verification

- [ ] **Step 1: Broader team_bus unit suite**

```bash
cd client && flutter test test/services/team_bus/ --exclude-tags integration
```

Expected: PASS.

- [ ] **Step 2: Grep for leftover virgin plumbing**

```bash
rg 'hasEverBeenActive|unreadIsIdleOnly|_unreadIsIdleOnly' client/
```

Expected: no matches (or only historical mentions in the design/plan docs under `docs/`).

- [ ] **Step 3: Done** — no further commit unless Step 1–2 required fixes.
