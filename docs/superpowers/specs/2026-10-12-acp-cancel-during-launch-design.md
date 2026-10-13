# Cancel ACP Turn Before Handshake Completes

## Goal

Compose Stop must cancel the current ACP turn even when the agent is still
spawning or handshaking. Today Stop can appear after an early send, but
`cancelTurn` talks to a session that does not exist yet, and the queued
prompt still flushes after `start` succeeds.

Stop remains **cancel this turn**, not **kill the ACP process**. Closing the
tab already terminates the agent.

## Decisions locked with the user (2026-10-12)

- Stop drops a queued prompt and must not send `session/prompt` after
  handshake.
- Handshake / spawn continues. Do not SIGTERM the agent from Stop.
- A later `sendPrompt` while still launching may queue a **new** turn.
- No Stop while launching unless a turn is already queued (`inTurn`).
- Hung launch without a queued turn: close the tab. Not this change.
- Mid-turn cancel after the session is open stays `session/cancel` and
  still waits for the cancelled stop (trailing tool-call updates).

## Current behavior

Landing and compose may call `AcpChatRuntimeCubit.sendPrompt` as soon as
the cubit is attached, before `AcpSessionRuntime.start` finishes:

```
launching + sendPrompt → _queuedPrompt, inTurn=true, user bubble
compose Stop shown (acpRuntime != null && inTurn)
cancelTurn → _runtime.cancel() → _session!.cancel()   // null if not started
start() success → flush _queuedPrompt via _dispatchPrompt anyway
```

`AcpSessionRuntime.cancel` is `_session!.cancel()`. A Stop during
`launching` either throws or no-ops after a crash, then the first prompt
still goes out.

`_endTurn` always sets `phase: idle`. Using it during `launching` would
lie that handshake finished.

## Design

### 1. Turn serial

Add a monotonic `_turnSerial` on `AcpChatRuntimeCubit`.

| Event | Serial |
|-------|--------|
| `sendPrompt` accepted (queue or dispatch) | increment, capture on that turn |
| `cancelTurn` | increment (invalidates queue and a not-yet-RPC prompt) |

`_queuedPrompt` stores `{text, serial}` (or equivalent). `start` flushes
only when `queued.serial == _turnSerial`. `_recordAndPrompt` captures the
serial and, after persist and **before** `_runtime.prompt`, returns without
prompting if the serial is stale.

A stale skip after handshake has already moved to `ready` must `_endTurn`
(no `AcpStop` will arrive). A stale skip during `launching` must **not**
call `_endTurn`.

### 2. `cancelTurn`

```
increment serial
clear _queuedPrompt
clear pendingClient
if (!_runtime.isStarted):
  clear inTurn + activity (keep phase, including launching)
  persist transcript (user bubble stays)
  return
_runtime.cancel()   // existing in-flight path; wait for cancelled stop
```

Do not set `phase` to `idle` while still `launching`. Do not apply a
system message (same silent cancel as `AcpStopKind.cancelled`).

The user bubble from the cancelled send stays in `messages`. Stop is not
unsend.

### 3. Runtime `cancel` is null-safe

`AcpSessionRuntime.cancel` becomes `_session?.cancel()`. Calling it with
no open session is a no-op, not a `Null check` throw.

The cubit still must not call `_runtime.cancel()` until `isStarted`, so
fakes can assert `cancelled == false` for the launching path. The `?.` is
defense in depth.

### 4. UI

No new chrome. `showAcpStop` stays `acpRuntime != null && inTurn`.

After a launching cancel, `inTurn` is false immediately, so Stop becomes
Send. Handshake continues in the background. The next non-empty submit
queues again (`sendPrompt` already allows that once `inTurn` and
`_queuedPrompt` are clear).

### 5. Landing overlap

`queueAcpLandingPromptDuringConnect` only re-calls `sendPrompt` when the
first attempt returned false. A successful queue (`true`) then
`cancelTurn` must **not** be re-queued when `connect` completes. No change
to that helper if the cubit contract above holds.

Do not wire landing's route `cancelled` flag to compose Stop. Those are
different cancels (leave the page vs stop the turn).

## Failure policy

| Case | Result |
|------|--------|
| Stop while queued, handshake later succeeds | No `session/prompt`. Phase `ready`. User bubble kept. |
| Stop while queued, handshake later fails | Existing launch-failure system message + `ended`. Queued text is not sent. |
| Stop after session open, prompt RPC in flight | `session/cancel` + cancelled stop, unchanged. |
| Stop after session open, persist started but `prompt()` not yet called | Stale serial skips `prompt`; `_endTurn`. |
| Stop with no `inTurn` | Compose does not show Stop. `cancelTurn` is still safe (no-op / clear empty queue). |
| `cancel()` before `start` on the runtime | No-op. |

## Tests

| Layer | Cases |
|-------|--------|
| `acp_chat_runtime_cubit_test.dart` | Queue during launching, `cancelTurn`, `start` succeeds → `runtime.prompts` empty, `runtime.cancelled` false, `inTurn` false, phase never jumped to `idle` while launching, user bubble remains. After that cancel, a second `sendPrompt` queues and flushes. |
| same | `cancelTurn` before `start` does not throw. |
| same | After `start`, in-flight `cancelTurn` still sets `runtime.cancelled`. Existing ask-pending cancel test stays. |
| `acp_session_runtime_test.dart` | `cancel()` before `start` does not throw. After `start`, `cancel` still notifies `session/cancel`. |
Compose already routes Stop to `cancelTurn` (`session_chat_view_acp_test`
in-flight case). Do not add a launching widget test unless a fake with
`isStarted == false` is already cheap; cubit tests own this behavior.

Existing `sendPrompt during launching is flushed after start` stays; it is
the path without Stop.

## Out of scope

- Abort spawn / handshake from Stop (`session/close`, SIGTERM).
- Stop while launching with no queued turn.
- Mixed-team workbench binding of `tab.acpRuntime` (separate spec).
- New l10n; cancel stays silent.
- Changing landing connect cancellation / route leave.
