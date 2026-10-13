# ACP History Message Document Design

## Goal

ACP session history is a client-owned **message document**, in the same
sense as Zed's thread store: one session, one snapshot of folded chat
bubbles, rewritten when a message commits. Reopen shows the PTY loading
pane, then a windowed thread (latest ~30 turns, `loadOlder` for the rest).

Today the writer appends every ACP `session/update` chunk into
`acp-transcript.jsonl`. Reopen folds that event log on the UI isolate and
`adoptExternalMessages` dumps the full list into the seat (`hasOlder:
false`). Short sessions work; long ones flash empty-history, parse a huge
chunk file, and hang every bubble at once.

ACP is still in development. **No legacy event-log compatibility.** Existing
dev `acp-transcript.jsonl` files are discarded.

## Decisions locked with the user (2026-10-10)

- Align with **Zed's data model**, not Zed's engine: one session = one
  message document, save replaces the document. Do **not** add a global
  `threads.db` + zstd, do **not** split per-turn files, do **not** ship
  `session/load` this phase.
- Keep the path `sessions/<id>/runtime/acp-transcript.jsonl`. Content
  becomes v1 message lines, not protocol chunks.
- Write on committed messages (user, tool status, stop, system). Stream
  chunks stay in cubit memory only. Mid-turn crash loses uncommitted
  streaming text, same as Zed.
- Cold open: cubit loads the whole document; the seat windows it with the
  existing 30-turn / `loadOlder` machinery. Do not plug ACP into
  `AiHistoryLoader` or Gemini's CLI `AiHistoryCapability` stub. Do not
  read the CLI's own transcript.
- No backward compatibility with the chunk JSONL schema.

## Architecture

```
acp-transcript.jsonl          cubit (document owner)           AiHistorySeat (view)
  v1 message snapshot   <--saveMessages--  state.messages
                        --loadMessages-->  hydrate
                                               | first: _applyMessages window
                                               | live:  _applySoftReloadMessages
                                               v
                                         visible slice (~30)
                                         loadOlder grows _visibleCount
```

| Role | Owns |
|---|---|
| `AcpChatTranscriptWriter` | Atomic snapshot I/O. `saveMessages` / `loadMessages` only. |
| `AcpChatRuntimeCubit` | Live fold of `session/update` into `AiMessage`. Persist the current `state.messages` on commit. Hydrate that list on `start`. |
| `AiHistorySeat` | Loading / empty / ready chrome, 30-turn window, in-memory `loadOlder`. |
| `SessionChatView` | Loading until `historyHydrated`; first adopt windows; later adopts are live patches. Never `seat.load()` for ACP. |

Gemini's `AiHistoryCapability` stays a stub (`locate` → null). That
capability is for CLI-native transcripts. ACP history is app-side.

PTY keeps `AiHistoryLoader` (page-first, isolate parse, CLI adapters). ACP
does not join that path: after this change the on-disk document is already
messages, small enough to load whole, then window in the seat like Zed
loads a thread then draws it.

## Storage format

Same file: `<teampilotRoot>/workspace/workspaces/<ws>/sessions/<id>/runtime/acp-transcript.jsonl`.

JSONL, one folded message per line, `"v": 1` required:

```json
{"v":1,"type":"user","id":"acp-u-<uuid>","text":"…","at":"<ISO-8601>"}
{"v":1,"type":"assistant","id":"acp-a-<uuid>","at":"<ISO-8601>","parts":[
  {"kind":"text","text":"…"},
  {"kind":"reasoning","text":"…"},
  {"kind":"tool","toolCallId":"…","title":"…","status":"completed","isError":false}
]}
{"v":1,"type":"system","id":"acp-sys-<uuid>","kind":"launchFailed","message":"…","at":"<ISO-8601>"}
```

Rules:

- `type` is `user` | `assistant` | `system` only. No `chunk`, `tool_call`,
  `stop`.
- Message ids are the cubit's existing `acp-u/a/sys-<uuid>` values so live
  and disk identity match.
- `auth` and `processExited` system rows are never written (live probes /
  intentional close, not history).
- Assistant `parts` are the coalesced in-memory parts (text, reasoning,
  tool cards). Tool `status` is the `AiToolCallStatus` name on the part
  (`running` / `complete` / `incomplete` / `cancelled`) plus `isError`.
  Do not persist ACP wire names (`pending` / `inProgress` / …).
- A line without `"v": 1`, or any unknown `type` / `kind`, is skipped.
  If that leaves zero messages, the session is empty history.

The file is always a complete snapshot of `cubit.state.messages` at the last
successful save, not an append-only event log.

## Read / write timing

Replace `recordUserPrompt` / `recordChunk` / `recordToolCall` / `recordStop`
/ `recordSystem` with:

```dart
Future<void> saveMessages(List<AiMessage> messages);
Future<List<AiMessage>> loadMessages();
```

`saveMessages` serializes the list to v1 JSONL and writes via
`Filesystem.atomicWrite` (tmp + rename). Saves are serialized on the
existing writer queue so overlapping commits cannot interleave two
snapshots.

| Event | Memory | Disk |
|---|---|---|
| `AcpMessageChunk` | Coalesce into the tip assistant bubble | No |
| User prompt committed | Append user `AiMessage` | `saveMessages` |
| `AcpToolCallUpdate` applied | Upsert tool part | `saveMessages` |
| `AcpStop` | End turn; keep current messages | `saveMessages` |
| Non-skipped system message | Append system bubble | `saveMessages` |
| Cubit `close` | — | `saveMessages` once more |
| `processExited` / `auth` | Not in `messages` | Not written |

`start()` hydrates **before** spawn, same as today:

1. `loadMessages()`
2. `historyHydrated: true` (even when empty)
3. `messages` = loaded list, merged with any in-memory landing prompt

A load that returns empty (missing file, unreadable, no valid v1 lines)
still sets `historyHydrated`.

## Seat window

`adoptExternalMessages` must stop publishing the full list with
`hasOlder: false`.

- **First publish** after hydrate (seat loading or empty, no window yet):
  same as `_applyMessages` — `_allMessages` = cubit list, `_visibleCount =
  min(kSessionHistoryInitialTurns, length)`, `_sourceHasOlder = false`,
  `_emitReadyWindow`. `loadOlder` with a null page cursor already grows
  `_visibleCount` from in-memory `_allMessages`; ACP uses that path.
- **Later publishes** (live): same as `_applySoftReloadMessages` — reuse
  message identity, grow the visible tail by `tipDelta`, do not reset the
  window back to 30.
- Skip `_loader.annotate` (ACP has no PTY CLI on the seat).
- Keep `shouldShowAcpHistoryLoading` / `shouldPublishAcpSeatMessages`
  (loading pane until hydrate; do not wipe a landing pending with an empty
  launching cubit).
- ACP still must not call `seat.load()` / `AiHistoryLoader`.

Cold open:

1. `markExternalLoading` → `sessionHistoryLoading` ("正在加载对话历史…")
2. Cubit hydrate → `historyHydrated`
3. First adopt → windowed ready, or empty pane if there are no messages

## Error handling

| Failure | Handling |
|---|---|
| Missing or empty file | Empty history, `historyHydrated` |
| Non-v1 / corrupt JSON / no valid lines | `AppLogger`, treat as empty history. No global dialog. |
| `atomicWrite` fails | `AppLogger`; in-memory turn continues. Next successful save replaces the file. |
| Rename fails after tmp write | Existing `atomicWrite` deletes the tmp; previous snapshot remains. |
| Close save fails | `AppLogger`; process still exits. |

Do not fail a prompt because history I/O failed.

## Testing

- v1 round-trip: user, assistant (text + reasoning + tool), system.
- Chunks do not call `saveMessages`; user / tool / stop / system / close do.
- Close does not persist `processExited`.
- Missing file and garbage file → empty + `historyHydrated`.
- Seat: loading before hydrate; first adopt windows 30 and sets `hasOlder`
  when longer; live adopt grows the tail only.
- Delete or rewrite tests that replay `type: chunk|tool_call|stop` JSONL.

## Out of scope

- `session/load` / `session/resume` (agent-side context restore)
- Global SQLite + zstd (`threads.db`)
- Per-turn files
- Reading Gemini/Claude on-disk CLI transcripts
- Zed-style compaction summaries of old turns
- Isolate parse / JSONL page-first for ACP (YAGNI once the file is messages)
- Filling `GeminiAiHistoryCapability.locate` / `lineAppend` / `pageReader`

## Files

| File | Change |
|---|---|
| `client/lib/services/acp/acp_chat_transcript.dart` | Snapshot writer: `saveMessages` / `loadMessages`, `atomicWrite` |
| `client/lib/services/acp/acp_chat_transcript_replay.dart` | Replace chunk fold with v1 encode/decode |
| `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` | Persist on commit, not per chunk |
| `client/lib/cubits/ai_history_seat.dart` | Windowed first adopt + live soft-reload adopt |
| `client/lib/pages/chat/acp_seat_message_sync.dart` | Unchanged contract (loading / publish guards) |
| Tests next to those files | Snapshot, persist-timing, seat window; drop legacy replay cases |
