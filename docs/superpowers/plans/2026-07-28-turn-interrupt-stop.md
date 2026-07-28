# Turn Interrupt (Compose Stop) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Swap conversation compose Send for Stop while the selected member is `working`, and abort that member’s turn via per-CLI `TurnInterruptCapability` (v1: Ctrl+C) without disconnecting the session.

**Architecture:** New CLI registry capability declares interrupt byte sequences. `MemberTurnInterruptService` cancels in-flight PTY inject then writes the plan to the selected member’s shell. Compose reads seat-level working (not session `workingSessionIds`) and calls `ChatCubit.interruptSelectedMemberTurn`.

**Tech Stack:** Flutter / Dart, `flutter_bloc`, existing `CliToolRegistry` / `TerminalSession.input.writeToPty`, unit + widget tests under `client/test/`.

**Spec:** `docs/superpowers/specs/2026-07-28-turn-interrupt-stop-design.md`

## Global Constraints

- No scattered `if (cli == …)` outside CLI registry capabilities / tool definitions.
- Stop aborts **selected member only**; never disconnect / close tab / delete history.
- Busy chrome uses **selected-member** `working`, not session-level `workingSessionIds` alone.
- v1 interrupt sequence for all built-in CLIs: `['\x03']` (Ctrl+C), declared via capability.
- Unsupported / disconnected → silent no-op + `appLogger.d`; no user toast.
- l10n only via `app_en.arb` / `app_zh.arb`.
- After ARB edits, run `dart run tool/gen_warmup_glyphs.dart` from `client/` if glyphs change (new ASCII Latin strings usually fine; still regenerate if tooling expects it).
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` (or at least the new/changed tests).

---

## File map

| File | Role |
|------|------|
| `client/lib/services/cli/registry/capabilities/turn_interrupt_capability.dart` | **Create** — `TurnInterruptPlan` + `TurnInterruptCapability` + shared `CtrlCTurnInterrupt` |
| `client/lib/services/cli/registry/tools/claude_cli_tool.dart` | Register capability |
| `client/lib/services/cli/registry/tools/flashskyai_cli_tool.dart` | Register capability |
| `client/lib/services/cli/registry/tools/codex_cli_tool.dart` | Register capability |
| `client/lib/services/cli/registry/tools/opencode_cli_tool.dart` | Register capability |
| `client/lib/services/cli/registry/tools/cursor_cli_tool.dart` | Register capability |
| `client/test/services/cli/registry/capabilities/turn_interrupt_capability_test.dart` | **Create** — registry exposes Ctrl+C plan for all launchable tools |
| `client/lib/services/terminal/member_pty_inject_service.dart` | Add `requestAbort` / abort flag checked during deliver |
| `client/lib/cubits/chat/tab_member_pty_delivery.dart` | OR abort flag into `_ptyAckAborted`; expose `abortMemberInject` |
| `client/test/services/terminal/member_pty_inject_service_test.dart` | **Create or extend** — abort cancels in-flight path |
| `client/lib/services/terminal/member_turn_interrupt_service.dart` | **Create** — orchestrate abort inject + capability writes |
| `client/test/services/terminal/member_turn_interrupt_service_test.dart` | **Create** |
| `client/lib/services/team/session_working_resolver.dart` | Add `isMemberWorking(...)` for one seat |
| `client/test/services/team/session_working_resolver_test.dart` | **Create or extend** — selected-seat working |
| `client/lib/cubits/chat_cubit.dart` | `interruptSelectedMemberTurn` + `isMemberWorking` façade |
| `client/lib/pages/chat/compose_stop_visibility.dart` | **Create** — pure `shouldShowComposeStop` |
| `client/test/pages/chat/compose_stop_visibility_test.dart` | **Create** |
| `client/lib/pages/chat/session_review_compose_card.dart` | Send ↔ Stop button |
| `client/lib/pages/chat/session_chat_view.dart` | Wire working + onStop |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | Stop tooltip / a11y |
| `client/test/pages/chat/session_review_compose_stop_test.dart` | **Create** — widget: working shows Stop |

---

### Task 1: `TurnInterruptCapability` + wire built-in CLIs

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/turn_interrupt_capability.dart`
- Modify: each of `client/lib/services/cli/registry/tools/{claude,flashskyai,codex,opencode,cursor}_cli_tool.dart`
- Create: `client/test/services/cli/registry/capabilities/turn_interrupt_capability_test.dart`

**Interfaces:**
- Produces: `TurnInterruptCapability`, `TurnInterruptPlan`, `CtrlCTurnInterrupt` (`supportsTurnInterrupt: true`, `steps: ['\x03']`)
- Consumes: `CliCapability`, `CliToolRegistry.capability<T>`

- [ ] **Step 1: Write the failing registry test**

Create `client/test/services/cli/registry/capabilities/turn_interrupt_capability_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/turn_interrupt_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('all launchable CLIs expose Ctrl+C turn interrupt', () {
    final registry = CliToolRegistry.builtIn();
    for (final tool in registry.launchable) {
      final cap = registry.capability<TurnInterruptCapability>(tool.id);
      expect(cap, isNotNull, reason: tool.id.name);
      expect(cap!.supportsTurnInterrupt, isTrue);
      expect(cap.interruptPlan.steps, ['\x03']);
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/capabilities/turn_interrupt_capability_test.dart`

Expected: FAIL (missing library / null capability)

- [ ] **Step 3: Implement capability + register on all five tools**

Create `turn_interrupt_capability.dart`:

```dart
import '../cli_capability.dart';

final class TurnInterruptPlan {
  const TurnInterruptPlan({
    required this.steps,
    this.gapBetweenSteps = Duration.zero,
  });

  final List<String> steps;
  final Duration gapBetweenSteps;
}

abstract interface class TurnInterruptCapability implements CliCapability {
  bool get supportsTurnInterrupt;
  TurnInterruptPlan get interruptPlan;
}

/// Default v1 plan: Ctrl+C once.
final class CtrlCTurnInterrupt implements TurnInterruptCapability {
  const CtrlCTurnInterrupt();

  @override
  bool get supportsTurnInterrupt => true;

  @override
  TurnInterruptPlan get interruptPlan =>
      const TurnInterruptPlan(steps: ['\x03']);
}
```

On each `*CliTool`:
- Add field `this.turnInterrupt = const CtrlCTurnInterrupt()`
- Include `turnInterrupt` in `capabilities` iterable
- Import `turn_interrupt_capability.dart`

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/cli/registry/capabilities/turn_interrupt_capability_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/turn_interrupt_capability.dart \
  client/lib/services/cli/registry/tools/*.dart \
  client/test/services/cli/registry/capabilities/turn_interrupt_capability_test.dart
git commit -m "$(cat <<'EOF'
feat(cli): add TurnInterruptCapability with Ctrl+C default

EOF
)"
```

---

### Task 2: Abort in-flight member PTY inject

**Files:**
- Modify: `client/lib/services/terminal/member_pty_inject_service.dart`
- Modify: `client/lib/cubits/chat/tab_member_pty_delivery.dart`
- Create: `client/test/services/terminal/member_pty_inject_abort_test.dart`

**Interfaces:**
- Consumes: existing `MemberPtyInjectService.deliver` / `aborted` callback pattern
- Produces:
  - `MemberPtyInjectService.requestAbort(sessionId, memberId)` — sets abort flag + `clearPending`
  - `MemberPtyInjectService.isAbortRequested(sessionId, memberId)`
  - `MemberPtyInjectService.clearAbort(sessionId, memberId)` (call when lock releases after abort observed, or at start of next successful acquire — document in code)
  - `TabMemberPtyDelivery.abortMemberInject(sessionId, memberId)` → forwards to `_ptyInject.requestAbort` and ensures `_ptyAckAborted` returns true when abort requested for that seat

- [ ] **Step 1: Write failing abort test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/member_pty_inject_service.dart';

void main() {
  test('requestAbort marks seat aborted and clears pending', () {
    final service = MemberPtyInjectService();
    service.requestAbort('s1', 'm1');
    expect(service.isAbortRequested('s1', 'm1'), isTrue);
    expect(service.hasPendingRetry('s1', 'm1'), isFalse);
  });
}
```

(If `hasPendingRetry` needs a prior enqueue to prove clear, use the existing retry-queue helpers from `workspace_terminal_run_service_test` / inject tests — keep the assert on `isAbortRequested` as the primary gate.)

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client && flutter test test/services/terminal/member_pty_inject_abort_test.dart`

- [ ] **Step 3: Implement abort flag on `MemberPtyInjectService`**

Add a `Set<String> _abortRequested`. In `requestAbort`:
1. `_abortRequested.add(PtyAutomationSessionLock.key(sessionId, memberId))`
2. `clearPending(sessionId, memberId)`

In `_runLocked` (or wherever `aborted` is polled), combine caller `aborted()` with `isAbortRequested`. On lock release after a run that saw abort, `clearAbort` for that key so the next inject is not permanently aborted.

Update `TabMemberPtyDelivery`:

```dart
void abortMemberInject(String sessionId, String memberId) {
  _ptyInject.requestAbort(sessionId, memberId);
}

bool _ptyAckAborted(TerminalSession shell, {String? sessionId, String? memberId}) {
  if (_isClosed() || !shell.isConnected) return true;
  if (sessionId != null &&
      memberId != null &&
      _ptyInject.isAbortRequested(sessionId, memberId)) {
    return true;
  }
  return false;
}
```

Update all `_ptyAckAborted(shell)` call sites that have session/member in scope to pass ids.

- [ ] **Step 4: Run abort test — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/terminal/member_pty_inject_service.dart \
  client/lib/cubits/chat/tab_member_pty_delivery.dart \
  client/test/services/terminal/member_pty_inject_abort_test.dart
git commit -m "$(cat <<'EOF'
feat(terminal): allow aborting in-flight member PTY inject

EOF
)"
```

---

### Task 3: `MemberTurnInterruptService`

**Files:**
- Create: `client/lib/services/terminal/member_turn_interrupt_service.dart`
- Create: `client/test/services/terminal/member_turn_interrupt_service_test.dart`

**Interfaces:**
- Consumes: `TurnInterruptCapability`, `SessionMemberCliResolver.resolve`, `TerminalSession.input.writeToPty`, abort callback
- Produces:

```dart
final class MemberTurnInterruptService {
  MemberTurnInterruptService({
    required CliToolRegistry cliToolRegistry,
    required void Function(String sessionId, String memberId) abortMemberInject,
    Future<void> Function(Duration delay)? delay, // inject for tests; default Future.delayed
  });

  Future<void> interrupt({
    required String sessionId,
    required String memberId,
    required TerminalSession? shell,
    required CliTool cli,
  });
}
```

Behavior:
1. If `shell == null` or `!shell.isConnected` → `appLogger.d` + return
2. `abortMemberInject(sessionId, memberId)`
3. `cap = registry.capability<TurnInterruptCapability>(cli)`; if null or `!supportsTurnInterrupt` → log + return
4. For each `step` in `cap.interruptPlan.steps`: `shell.input.writeToPty(step)`; if not last and `gapBetweenSteps > 0`, `await delay(gap)`

- [ ] **Step 1: Write failing service tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/terminal/member_turn_interrupt_service.dart';
// Use a fake TerminalSession or a thin WriteCapture double — prefer the
// smallest fake that exposes isConnected + input.writeToPty recording.
// If constructing TerminalSession is heavy, introduce a typedef/callback
// writeToPty in the service constructor for tests:
//   required void Function(String sessionId, String memberId, String bytes) writePty
// Spec prefers writing via shell.input; either inject a FakeShell with that API
// or add an optional writeToPty override used only when non-null in tests.

void main() {
  test('writes Ctrl+C and aborts inject first', () async {
    final aborted = <String>[];
    final writes = <String>[];
    final service = MemberTurnInterruptService(
      cliToolRegistry: CliToolRegistry.builtIn(),
      abortMemberInject: (s, m) => aborted.add('$s:$m'),
      // ... wire fake shell / write capture ...
    );
    await service.interrupt(
      sessionId: 's1',
      memberId: 'm1',
      shell: fakeConnectedShell(onWrite: writes.add),
      cli: CliTool.claude,
    );
    expect(aborted, ['s1:m1']);
    expect(writes, ['\x03']);
  });

  test('no-op when shell disconnected', () async {
    // expect no writes, abort still optional — prefer: still call abort? Spec says
    // resolve shell first; if missing/not connected → no-op (skip abort+write).
  });
}
```

**Implementation note for the fake:** Prefer constructor injection of:

```dart
typedef MemberPtyWriter = void Function(TerminalSession shell, String text);
```

defaulting to `(shell, text) => shell.input.writeToPty(text)`, so tests can pass a recorder without spinning a real PTY. Keep production default as real `writeToPty`.

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement `MemberTurnInterruptService` as above**

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/terminal/member_turn_interrupt_service.dart \
  client/test/services/terminal/member_turn_interrupt_service_test.dart
git commit -m "$(cat <<'EOF'
feat(terminal): orchestrate member turn interrupt via CLI capability

EOF
)"
```

---

### Task 4: Seat working helper + `ChatCubit` API

**Files:**
- Modify: `client/lib/services/team/session_working_resolver.dart`
- Create or modify: `client/test/services/team/session_working_resolver_member_test.dart`
- Modify: `client/lib/cubits/chat_cubit.dart` (and any host the launch/runtime already uses for delivery — wire `abortMemberInject` to `TabMemberPtyDelivery.abortMemberInject`)

**Interfaces:**
- Produces on `SessionWorkingResolver`:

```dart
bool isMemberWorking({
  required ChatTab tab,
  required String memberId,
  required TeamProfile? team,
  required List<CliPreset> globalPresets,
  Map<String, MemberPresence> presence = const {},
  bool usePresenceSnapshot = false,
  Map<String, bool> claudeWorkingByMemberId = const {},
});
```

When `usePresenceSnapshot`: return `presence[memberId]?.isWorking ?? false`.  
Else: same per-member loop body as `tabHasWorkingMember` but only for `memberId`.

- Produces on `ChatCubit`:

```dart
bool isMemberWorking(String sessionId, String memberId);

Future<void> interruptSelectedMemberTurn({
  String? sessionId,
  String? memberId,
});
```

`interruptSelectedMemberTurn`:
1. Resolve `sid` = sessionId ?? active tab session id; if null return
2. Resolve tab; `mid` = memberId ?? `tab.selectedMemberId`; if empty return
3. Resolve `cli` via `SessionMemberCliResolver` (same deps as `TabMemberPtyDelivery._memberCli`)
4. `await _turnInterrupt.interrupt(sessionId: sid, memberId: mid, shell: tab.memberShells[mid], cli: cli)`

Construct `_turnInterrupt` with `abortMemberInject: sessionRuntime.delivery.abortMemberInject` (exact field path: follow how `_sessionRuntime` already exposes `TabMemberPtyDelivery` — if private, add a package-visible getter or pass the callback at coordinator construction).

- [ ] **Step 1: Write failing `isMemberWorking` unit test**

Cover: presence snapshot true for one member; other member idle → false for idle id.

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement resolver method + Cubit façade + wire service**

- [ ] **Step 4: Run resolver tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team/session_working_resolver.dart \
  client/test/services/team/session_working_resolver_member_test.dart \
  client/lib/cubits/chat_cubit.dart \
  # plus any session_runtime / delivery wiring files touched
git commit -m "$(cat <<'EOF'
feat(chat): expose interruptSelectedMemberTurn and seat working check

EOF
)"
```

---

### Task 5: Compose Send ↔ Stop UI + l10n

**Files:**
- Create: `client/lib/pages/chat/compose_stop_visibility.dart`
- Create: `client/test/pages/chat/compose_stop_visibility_test.dart`
- Modify: `client/lib/pages/chat/session_review_compose_card.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Create: `client/test/pages/chat/session_review_compose_stop_test.dart`

**Interfaces:**
- Produces:

```dart
bool shouldShowComposeStop({
  required bool memberWorking,
  required bool supportsTurnInterrupt,
});
// => memberWorking && supportsTurnInterrupt
```

Compose card API additions:
- `bool showStop`
- `VoidCallback? onStop`
- When `showStop`: circular button uses `Icons.stop_rounded` (or `Icons.stop`), tooltip `sessionHistoryComposeStop` / a11y; `onTap` → `onStop`
- When not: existing Send behavior unchanged
- `supportsTurnInterrupt`: resolve via `CliToolRegistry.builtIn().capability<TurnInterruptCapability>(cli)?.supportsTurnInterrupt ?? false` for the continue seat CLI (same resolver path as compose preset chips)

l10n keys:
- EN: `"sessionHistoryComposeStop": "Stop generating"`
- ZH: `"sessionHistoryComposeStop": "停止生成"`

`session_chat_view`:
- `context.select` / watch seat working via `ChatCubit.isMemberWorking(sessionId, selectedMemberId)` **or** for team tabs with presence, prefer `MemberPresenceCubit.memberPresenceFor(selectedMemberId).isWorking` when that cubit is the source of truth for the active session — must match Task 4’s `usePresenceSnapshot` rules (mirror `SessionWorkingResolver.usesPresenceSnapshotForTab`).
- Pass `showStop` + `onStop: () => unawaited(chat.interruptSelectedMemberTurn(sessionId: …, memberId: selectedMemberId))`

- [ ] **Step 1: Write failing visibility + widget tests**

```dart
test('shouldShowComposeStop requires working and support', () {
  expect(shouldShowComposeStop(memberWorking: true, supportsTurnInterrupt: true), isTrue);
  expect(shouldShowComposeStop(memberWorking: false, supportsTurnInterrupt: true), isFalse);
  expect(shouldShowComposeStop(memberWorking: true, supportsTurnInterrupt: false), isFalse);
});
```

Widget test: pump `SessionReviewComposeCard` with `showStop: true` → find stop icon / tooltip; tap calls `onStop`.

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement visibility helper, l10n, compose card, wire `session_chat_view`**

After ARB change, run Flutter gen-l10n as this repo usually does (`flutter gen-l10n` / build triggers) so `AppLocalizations` getters exist.

- [ ] **Step 4: Run new page tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/compose_stop_visibility.dart \
  client/lib/pages/chat/session_review_compose_card.dart \
  client/lib/pages/chat/session_chat_view.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations*.dart \
  client/test/pages/chat/compose_stop_visibility_test.dart \
  client/test/pages/chat/session_review_compose_stop_test.dart
git commit -m "$(cat <<'EOF'
feat(chat): swap compose Send for Stop while member is working

EOF
)"
```

---

### Task 6: Verification gate

**Files:** none new

- [ ] **Step 1: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no new errors from this work

- [ ] **Step 2: Targeted tests**

Run:

```bash
cd client && flutter test \
  test/services/cli/registry/capabilities/turn_interrupt_capability_test.dart \
  test/services/terminal/member_pty_inject_abort_test.dart \
  test/services/terminal/member_turn_interrupt_service_test.dart \
  test/services/team/session_working_resolver_member_test.dart \
  test/pages/chat/compose_stop_visibility_test.dart \
  test/pages/chat/session_review_compose_stop_test.dart
```

Expected: all PASS (adjust paths if a test file was merged into an existing suite)

- [ ] **Step 3: Broader unit suite (recommended)**

Run: `cd client && flutter test --exclude-tags integration`

Expected: PASS (fix any incidental breakages from API signature changes)

- [ ] **Step 4: Manual smoke (human)**

1. Open a Simple Claude session, send a long prompt, confirm Send → Stop while Running / working  
2. Tap Stop → generation stops; shell still connected; can send again  
3. Team session: only selected working member shows Stop; other idle member keeps Send  
4. Disconnect path unchanged (context menu Disconnect still works)

---

## Spec coverage checklist

| Spec item | Task |
|-----------|------|
| `TurnInterruptCapability` + Ctrl+C v1 for all CLIs | 1 |
| Cancel in-flight inject before interrupt writes | 2 + 3 |
| `MemberTurnInterruptService` orchestration | 3 |
| `ChatCubit.interruptSelectedMemberTurn` | 4 |
| Selected-member working (not only `workingSessionIds`) | 4 + 5 |
| Compose Send ↔ Stop | 5 |
| Silent no-op when disconnected / unsupported | 3 |
| Tests listed in spec | 1–5 |
| Non-goals (disconnect, stop-all, Esc) | intentionally omitted |

## Placeholder / consistency self-check

- Capability name `TurnInterruptCapability` / plan `TurnInterruptPlan` / default `CtrlCTurnInterrupt` consistent across tasks.
- Cubit method `interruptSelectedMemberTurn` is `Future<void>` (async gaps).
- Abort API names: `requestAbort` / `abortMemberInject` / `isAbortRequested`.
- No TBD left in steps; fake-shell detail in Task 3 allows writer injection if `TerminalSession` construction is heavy — production still uses `shell.input.writeToPty`.
