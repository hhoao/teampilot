# Cancel ACP Turn Before Handshake Completes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compose Stop cancels a queued ACP turn during spawn/handshake so the prompt is never sent, without killing the agent process.

**Architecture:** `AcpSessionRuntime.cancel()` is a no-op until a session exists. `AcpChatRuntimeCubit` gives each accepted send a `_turnSerial`; Stop increments it, drops `_queuedPrompt`, and only calls `runtime.cancel()` after `isStarted`. `start` flushes the queue only when the serial still matches. `_recordAndPrompt` skips `prompt()` when the serial went stale across the persist await.

**Tech Stack:** Flutter/Dart (`teampilot`), existing `AcpChatRuntimeCubit` / `AcpSessionRuntime` / cubit fakes.

**Spec:** `docs/superpowers/specs/2026-10-12-acp-cancel-during-launch-design.md`

## Global Constraints

- Stop cancels **this turn** only. Do not SIGTERM the agent, send `session/close`, or abort spawn/handshake.
- No Stop chrome change: still `acpRuntime != null && inTurn`.
- No new l10n. Queued cancel stays silent (no system message). User bubble stays.
- Do not set `phase` to `idle` while still `launching` (`start` no-ops if phase is not `launching`).
- Mixed-team workbench `tab.acpRuntime` binding is out of scope.
- Tests: `cd client && dart run tool/run_tests.dart <paths>`. Never `flutter test` directly.
- Inner loop: `flutter analyze --no-fatal-infos --no-fatal-warnings` then one test file. Full suite only before claiming done.

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/acp/acp_session_runtime.dart` | `cancel()` no-op when `_session` is null |
| `client/test/services/acp/acp_session_runtime_test.dart` | cancel before `start` does not throw; existing in-flight cancel stays |
| `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` | turn serial, queued cancel, flush/prompt guards |
| `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart` | launching cancel, re-queue, stale skip after `start` |

The cubit is already over the ~500-line soft limit. Keep this change in it (queue/cancel is cubit orchestration). Do not split the cubit in this plan.

---

### Task 1: Null-safe runtime `cancel`

**Files:**
- Modify: `client/lib/services/acp/acp_session_runtime.dart`
- Test: `client/test/services/acp/acp_session_runtime_test.dart`

**Interfaces:**
- Consumes: `AcpSessionRuntime._session`, `AcpAgentSession.cancel()`
- Produces: `void AcpSessionRuntime.cancel()` — no-op when no session; after `start`, still sends `session/cancel`

- [ ] **Step 1: Write the failing test**

Insert immediately before `test('delegates cancel; close disposes the connection'` in `acp_session_runtime_test.dart`:

```dart
test('cancel before start does not throw', () {
  final runtime = makeRuntime((argv, env) async => conn);
  expect(() => runtime.cancel(), returnsNormally);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd client && dart run tool/run_tests.dart test/services/acp/acp_session_runtime_test.dart --plain-name="cancel before start does not throw"
```

Expected: FAIL — `Null check operator used on a null value` from `_session!.cancel()`.

- [ ] **Step 3: Write minimal implementation**

In `acp_session_runtime.dart`, replace:

```dart
void cancel() => _session!.cancel();
```

with:

```dart
void cancel() => _session?.cancel();
```

Keep the doc comment; add one line that calling it before `start` is a no-op.

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd client && dart run tool/run_tests.dart test/services/acp/acp_session_runtime_test.dart
```

Expected: PASS, including `delegates cancel; close disposes the connection`.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_session_runtime.dart \
  client/test/services/acp/acp_session_runtime_test.dart
git commit -m "$(cat <<'EOF'
fix(acp): make runtime cancel a no-op before session open

EOF
)"
```

---

### Task 2: Cubit serial + queued Stop

**Files:**
- Modify: `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart`
- Test: `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

**Interfaces:**
- Consumes: `AcpSessionRuntimeApi.isStarted`, `cancel()`, `prompt()`; existing `sendPrompt` / `start` / `_endTurn`
- Produces: `_turnSerial` (int, starts at 0). `_queuedPrompt` is `({String text, int serial})?`. `cancelTurn()` increments serial, clears the queue, clears `inTurn` without changing phase when `!isStarted`, calls `_runtime.cancel()` only when `isStarted`. `start` flushes the queue only if `queued.serial == _turnSerial`. `_recordAndPrompt(text, serial)` skips `_runtime.prompt` when `serial != _turnSerial`.

- [ ] **Step 1: Write the failing tests**

Insert after `test('sendPrompt during launching is flushed after start'` in `acp_chat_runtime_cubit_test.dart` (keep that test unchanged):

```dart
test('cancelTurn during launching drops the queue and does not prompt', () async {
  final cubit = bootCubit();
  expect(cubit.sendPrompt('hello'), isTrue);
  expect(cubit.state.inTurn, isTrue);
  expect(cubit.state.phase, AcpChatPhase.launching);

  cubit.cancelTurn();
  expect(cubit.state.inTurn, isFalse);
  expect(cubit.state.phase, AcpChatPhase.launching);
  expect(runtime.cancelled, isFalse);
  expect(cubit.state.messages, hasLength(1));
  expect(cubit.state.messages.single.role, AiRole.user);

  await cubit.start(
    executable: 'gemini',
    sessionToolDir: '/tmp/tool',
    workingDirectory: '/w',
  );
  await pumpEventQueue();
  expect(runtime.prompts, isEmpty);
  expect(runtime.cancelled, isFalse);
  expect(cubit.state.inTurn, isFalse);
  expect(cubit.state.phase, AcpChatPhase.ready);
  expect(cubit.state.messages.single.role, AiRole.user);
  await cubit.close();
});

test('sendPrompt after launching cancel queues a new turn that flushes', () async {
  final cubit = bootCubit();
  expect(cubit.sendPrompt('hello'), isTrue);
  cubit.cancelTurn();
  expect(cubit.sendPrompt('world'), isTrue);
  await cubit.start(
    executable: 'gemini',
    sessionToolDir: '/tmp/tool',
    workingDirectory: '/w',
  );
  await pumpEventQueue();
  expect(runtime.prompts, ['world']);
  expect(
    cubit.state.messages.where((m) => m.role == AiRole.user),
    hasLength(2),
  );
  await cubit.close();
});

test('cancelTurn before start does not throw', () async {
  final cubit = bootCubit();
  expect(() => cubit.cancelTurn(), returnsNormally);
  await cubit.close();
});

test('cancelTurn after start still cancels the runtime', () async {
  final cubit = bootCubit();
  await cubit.start(
    executable: 'gemini',
    sessionToolDir: '/tmp/tool',
    workingDirectory: '/w',
  );
  expect(cubit.sendPrompt('hello'), isTrue);
  cubit.cancelTurn();
  await pumpEventQueue();
  expect(runtime.cancelled, isTrue);
  expect(runtime.prompts, isEmpty);
  expect(cubit.state.inTurn, isFalse);
  await cubit.close();
});
```

The last test relies on `await _persist()` yielding inside `_recordAndPrompt` so `cancelTurn` can run before `_runtime.prompt`. If it fails because `prompt` already ran, do not weaken it by pumping first — keep the serial check before `prompt()`.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart --plain-name="cancelTurn during launching drops the queue and does not prompt"
```

Expected: FAIL — after `start`, `runtime.prompts` is `['hello']` (queue still flushed) and/or `cancelTurn` throws, and/or phase became `idle` so `start` no-ops.

- [ ] **Step 3: Write minimal implementation**

In `acp_chat_runtime_cubit.dart`, next to `_queuedPrompt`:

```dart
String? _queuedPrompt;
int _turnSerial = 0;
```

Replace `_queuedPrompt` with:

```dart
({String text, int serial})? _queuedPrompt;
int _turnSerial = 0;
```

`sendPrompt` — increment serial, store it on the queue / pass it to dispatch:

```dart
bool sendPrompt(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  if (state.inTurn || _queuedPrompt != null) return false;
  if (state.phase == AcpChatPhase.ended) return false;
  _removeAuthNoticeMessage();
  _turnSerial++;
  final serial = _turnSerial;
  if (state.phase == AcpChatPhase.launching || !_runtime.isStarted) {
    _queuedPrompt = (text: trimmed, serial: serial);
    _showUserMessage(trimmed);
    _resetTurnTrackers();
    emit(state.copyWith(inTurn: true, activity: AcpChatActivity.thinking));
    return true;
  }
  _dispatchPrompt(trimmed, serial);
  return true;
}
```

`start` flush (replace the current `_queuedPrompt` string flush):

```dart
emit(state.copyWith(phase: AcpChatPhase.ready));
final queued = _queuedPrompt;
_queuedPrompt = null;
if (queued != null && queued.serial == _turnSerial) {
  _dispatchPrompt(queued.text, queued.serial);
}
```

`cancelTurn`:

```dart
void cancelTurn() {
  _turnSerial++;
  _queuedPrompt = null;
  if (!isClosed) emit(state.copyWith(pendingClient: null));
  if (!_runtime.isStarted) {
    _clearInTurnKeepingPhase();
    unawaited(_persist());
    return;
  }
  _runtime.cancel();
}
```

Add:

```dart
void _clearInTurnKeepingPhase() {
  if (_closing || isClosed) return;
  _resetTurnTrackers();
  _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.done));
  emit(
    state.copyWith(
      inTurn: false,
      pendingClient: null,
      activity: AcpChatActivity.none,
    ),
  );
}
```

Change `_dispatchPrompt` / `_recordAndPrompt` to take `serial`:

```dart
void _dispatchPrompt(String trimmed, int serial) {
  _showUserMessage(trimmed);
  _resetTurnTrackers();
  emit(state.copyWith(inTurn: true, activity: AcpChatActivity.thinking));
  _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.working));
  unawaited(
    _recordAndPrompt(trimmed, serial).catchError((Object error, StackTrace st) {
      appLogger.e(
        '[acp-chat] session $sessionId prompt failed: $error',
        error: error,
        stackTrace: st,
      );
      _endTurn();
    }),
  );
}

Future<void> _recordAndPrompt(String text, int serial) async {
  await _persist();
  if (_closing || isClosed) return;
  if (serial != _turnSerial) {
    if (state.phase != AcpChatPhase.launching && state.inTurn) {
      _endTurn();
    }
    return;
  }
  await _runtime.prompt(text);
}
```

Keep `_endTurn` setting `phase: idle` — it must only run when handshake already left `launching`.

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart
```

Expected: PASS, including `sendPrompt during launching is flushed after start` and `cancelTurn while ask pending clears pendingClient and cancels runtime`.

Then:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no issues in the touched files.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart \
  client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart
git commit -m "$(cat <<'EOF'
fix(acp): drop queued prompt when Stop lands before handshake

EOF
)"
```

---

## Spec coverage

| Spec requirement | Task |
|------------------|------|
| `cancel()` before `start` is a no-op | 1 |
| Stop drops queued prompt; no `session/prompt` after handshake | 2 |
| Handshake continues (no kill) | 2 (`runtime.cancelled` false while launching) |
| Later `sendPrompt` while launching queues a new turn | 2 |
| User bubble kept; silent cancel | 2 |
| Do not set `idle` during `launching` | 2 |
| After session open, persist-then-cancel skips `prompt` | 2 (`cancelTurn after start still cancels the runtime`) |
| In-flight `session/cancel` still works | 2 (existing ask-pending test + `isStarted` branch) |
| Landing helper not re-queued when first `sendPrompt` returned true | cubit contract; no landing code change |
| No new chrome / l10n / mixed-team wiring | out of scope, no task |
