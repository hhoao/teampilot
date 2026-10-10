# ACP Chat Status Design

## Goal

Make the ACP chat surface report what the agent is actually doing. Today the
in-thread status footer reads **"Starting…" for the whole life of the session**,
including while the agent streams a reply. This spec fixes that, adds a
three-way "running" granularity, and removes an empty-state flash that fires
when the user sends the first message.

Reported by the user (2026-10-10):

- "目前 ACP 对话时，聊天界面的状态体验不好"
- "就是他在生成也还是显示启动中，这不太合理，不应该是运行中/生成中吗"
- "第一次发送消息后，会先显示该成员暂无历史消息，随后才出现用户发送的消息"

## Root cause

The status footer is resolved by `SessionHistoryLiveChromeX.resolve`
(`client/lib/pages/chat/session_history_live_chrome.dart:38`):

```dart
if (!turnInFlight) return none;
if (isInTurn || isAttention) return running;
if (isDelivering || sessionConnecting || !memberRunning) return starting;
return running;
```

For an ACP session every escape from `starting` is false:

| Signal | Source | Why false for ACP |
|---|---|---|
| `memberRunning` | `ChatCubit.isMemberRunning` → PTY member state (`session_chat_message_area.dart:293`) | ACP is terminal-less; no PTY is ever spawned. |
| `isInTurn` | `SessionActivityAggregator` reason `inTurn` (`session_activity_aggregator.dart:59`) | Computed through `MemberCoordination._bootingOr` (`member_coordination.dart:110`), which returns `booting` until `activityTracker.isBootFrameReady` latches. No PTY ⇒ boot frame never latches. |
| `isAttention` | `AgentAttentionState.sessionIsAgentActive` | The ACP cubit only emits attention on `start`→`done` (`acp_chat_runtime_cubit.dart:223`), permission request→`waiting` (`:506`), permission answer→`working` (`:327`), and stop→`done` (`:493`). **A normal prompt turn emits no attention event at all**, so the seat sits at `done`. |

With all three false and `turnInFlight` true (`awaitingAssistant` is mirrored
from `runtime.state.inTurn` at `session_chat_view.dart:309`), the footer is
pinned to `starting` → "启动中…".

Separately, `AcpChatRuntimeCubit.state.phase` (`launching / ready / idle /
ended`) and `state.error` have **no UI consumer** today except
`acp_seat_message_sync.dart:15`, which only decides whether to publish
messages. So "生成中" / "已结束" were never rendered anywhere.

### Empty-state flash

`SessionHistoryReviewMessages._showThread` requires
`runtime.messages.isNotEmpty`, otherwise it falls to `AiHistoryViewStatus.empty`
and paints "该成员暂无历史消息" (`session_history_review_messages.dart:65`,
`:129`).

On submit the ACP branch of `_deliverComposeMessage` awaits
`_discardComposeDraftForSubmit()` **before** calling `sendPrompt`
(`session_chat_view.dart:1180-1183`). That await is a real async gap — it can
span a frame — during which the seat still holds no messages, so the empty
pane is painted once before the user's bubble lands.

## Decisions locked with the user (2026-10-10)

- Approach **C**: fix the shared signal *and* add one ACP-aware branch. Not
  UI-branch-only, not signal-only.
- "Running" is split into three states: 思考中 / 生成中 / 执行工具中.
- Scope is the chat status only. Presence dots and error-recovery entries are
  out (see *Out of scope*).

## Design

### 1. Activity model — the single source of truth

Add to `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` (beside
`AcpChatPhase` / `AcpChatErrorKind`):

```dart
/// What the agent is doing inside the current turn.
enum AcpChatActivity { none, thinking, generating, toolRunning }
```

Carried on `AcpChatRuntimeState` as `activity`, defaulting to `none`.

Transitions, driven from `_onUpdate` / `_dispatchPrompt` / `_endTurn`:

| Activity | Entered when |
|---|---|
| `thinking` | A prompt is dispatched (`_dispatchPrompt`, and the queued flush in `start`). No chunk seen yet this turn. |
| `generating` | The turn's first `AcpMessageChunk` arrives (thought chunks count — the agent has started emitting). |
| `toolRunning` | At least one `AcpToolCallUpdate` is in `pending` / `inProgress`. |
| `none` | `_endTurn` (stop, cancel, error, abort) and `_endWith`. |

`toolRunning` is tracked with a `Set<String> _runningToolCalls`: add on
`pending` / `inProgress`, remove on `completed` / `failed`. Precedence in the
getter:

```
!inTurn                       -> none
_runningToolCalls.isNotEmpty  -> toolRunning
_seenChunkThisTurn            -> generating
otherwise                     -> thinking
```

`_seenChunkThisTurn` resets on each dispatch and on `_endTurn`. Invariant:
`activity != none` ⟺ a turn is in flight.

### 2. Feed the shared attention signal

In `_dispatchPrompt` (and the queued-prompt flush inside `start`), emit
`AgentSeatAttention.working` through the existing `_applyAttention` path.
Everything else is unchanged: `_endTurn` / `_endWith` keep emitting `done`,
`_onPermissionRequest` keeps `waiting`, `answerPermission` keeps `working`.

This makes `SessionActivityAggregator`'s `attention` reason true for the
duration of an ACP turn, so session-busy, tab, and attention-driven
notification surfaces agree with the chat footer.

### 3. Render the status in the chat footer

Extend `SessionHistoryLiveChrome` (`session_history_live_chrome.dart`) with
`thinking`, `generating`, and `toolRunning`, plus a resolver:

```dart
static SessionHistoryLiveChrome resolveAcp({
  required AcpChatPhase phase,
  required AcpChatActivity activity,
}) { ... }
```

| Input | Chrome | Label |
|---|---|---|
| `phase == launching` | `starting` | 启动中… |
| `activity == thinking` | `thinking` | 思考中… |
| `activity == generating` | `generating` | 生成中… |
| `activity == toolRunning` | `toolRunning` | 执行工具中… |
| otherwise (`ready` / `idle` / `ended`) | `none` | (no footer) |

`resolveAcp` mirrors `resolve`'s contract: `turnInFlight == false` returns
`none` first. Phase is checked before activity, so a prompt queued during
launch (`sendPrompt` sets `inTurn` while `phase == launching`) still reads
启动中 — the agent has not started answering yet.

No `ended` value is added. A session that has ended has `inTurn == false`
(cleared by `_endWith`), so `turnInFlight` is already false and the footer is
not rendered at all; the inline system message stays the sole surface for the
end state. An `ended` chrome value would be unreachable.

`session_chat_message_area.dart` picks the resolver by runtime presence —
`acpRuntime != null` uses `resolveAcp`, otherwise the existing `resolve` is
untouched (**the PTY path has zero changes**).

`SessionHistoryThread._buildRunningInMessage` (`session_history_thread.dart:737`)
gains the new switches. All three reuse the existing `TpIndeterminateSpinner`
row; only the label differs.

New l10n keys in `app_en.arb` + `app_zh.arb` only:
`sessionHistoryThinking`, `sessionHistoryGenerating`,
`sessionHistoryToolRunning`.

### 4. Remove the empty-state flash

Two independent layers:

1. **Primary fix.** In the ACP branch of `_deliverComposeMessage`
   (`session_chat_view.dart:1175`), call `acpRuntime.sendPrompt(text)` first —
   it emits synchronously, so the microtask that publishes messages to the seat
   runs before the next frame — then `await _discardComposeDraftForSubmit()`.
   Ordering is safe: `sendPrompt` already rejects a second submit while a turn
   is queued or in flight.
2. **Guard.** `SessionHistoryReviewMessages._showThread` also returns true when
   `liveChrome.isActive`. A turn in flight with no messages yet is not an empty
   history — it is a turn whose footer is the content. This covers any other
   path that publishes messages late, and needs no new constructor parameter
   (the widget already holds `liveChrome`).

## Testing

- **Cubit unit** (`test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`):
  activity walks `none → thinking → generating → toolRunning → generating →
  none`; two overlapping tool calls keep `toolRunning` until both terminate;
  `working` attention is emitted on dispatch and `done` on stop.
- **Resolver unit**: `resolveAcp` maps every phase/activity pair, and returns
  `none` for `phase == ended`.
- **Widget** (`test/pages/chat/session_chat_view_acp_test.dart`): an ACP
  generating turn renders 生成中… and never 启动中….
- **Empty flash**: `_showThread` keeps the thread (no `sessionHistoryEmpty`)
  when the chrome is active and messages are empty; and after a real submit on
  an ACP session the user bubble renders without the empty pane.
- **Regression**: the existing PTY live-chrome tests must pass unmodified —
  that is the behavior-equivalence evidence for the untouched `resolve` path.

## Out of scope

- **Presence dots.** `MemberPresenceIndicator` for an ACP seat still reads
  `booting`, because `MemberCoordination._bootingOr` gates on
  `activityTracker.isBootFrameReady` — a PTY latch, not an attention signal.
  Fixing it means changing the boot predicate and is its own slice.
- **Error recovery entry points.** Retry / reconnect affordances for an ended
  session, and any footer chip for the ended state — the inline system message
  stays the only surface.
- **Launch-phase granularity.** Process spawn vs handshake stays a single
  "启动中"; no sub-phases are introduced.
