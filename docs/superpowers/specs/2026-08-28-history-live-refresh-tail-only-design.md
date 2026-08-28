# History live refresh: tail-only hot path — Design

**Date:** 2026-08-28
**Status:** Approved (design A)

## Problem

JSONL live refresh no longer re-parses the whole transcript on the hot
path. Conversation hitching can still come from **per-tick whole-list
work on the UI isolate**:

1. `_finishIncremental` annotates every message, rebuilds every task-call
   signature, and always `List.of`s the full list.
2. Pure CLI append still runs a second `mergeTimeline` (full sort + new
   `AiMessage` for every event) as a checksum.
3. Same tick “last assistant grew **and** a new message appeared”
   becomes `CliTimelineInvalidated` and rebuilds the whole timeline.
4. `LastReplaced` plus mailbox append also falls back to full merge.
5. `computeCliTimelineDelta` and `reuseHistoryMessageIdentity` call
   `messageContentIdentity`, which concatenates every tool result into a
   `StringBuffer`.

Prefix messages are already the same instances. The hot path should not
walk or rebuild them.

## Goals

1. Incremental ticks only annotate, re-sign, and fingerprint the
   **changed suffix** (first non-`identical` index through the end).
2. Append-only and last-replaced merges keep prefix `AiMessage`
   instances and do **not** call `mergeTimeline` on the hot path.
3. Same-tick last-replace + append stays incremental.
4. Cheap content equality never concatenates a full tool result or a
   growing assistant body.
5. Compact / path change / prefix rewrite still take the existing
   cold-start or `Invalidated` paths.

## Non-goals

- Last-bubble markdown relayout (separate slice).
- Windowed display / background full index (`2026-08-27` spec).
- Changing JSONL tailer replace detection or `force` semantics.
- Skipping mailbox IO on each `softReload`.
- Changing `messageContentIdentity` for UI widget keys.
- Fixed-millisecond CI budgets.

## Design decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Suffix start | First index `i` where `!identical(prev[i], next[i])`, or `prev.length` when next is a pure append | Prefix is already annotated; tailer only mutates the suffix |
| Annotate | Run `annotateToolCallCategories` on `next.sublist(suffixStart)` and concatenate with the prefix | Annotator stays idempotent; no new category rules |
| Task signatures | Copy previous map; drop ids that appeared only in the old suffix; add/overwrite ids from the new suffix | Matches current prune semantics without scanning prefix parts |
| `List.of` | Keep wrapping the concatenated list | Seat uses list **instance** identity to detect CLI growth |
| Append checksum | Remove hot-path `mergeTimeline` after incremental insert | Duplicate O(n log n) tax; tests compare against full merge |
| Same-tick grow | New `CliTimelineLastReplacedAndAppended` | Today this is `Invalidated` |
| LastReplaced + mailbox append | Replace last, then insert mailbox events with the existing insert helper | Same as CLI append; no full rebuild |
| `allEvents` allocation | Only when a side is `Invalidated` | LastReplaced already skips this; extend to all incremental deltas |
| Cheap equality | `identical` / scalar fields / per-part; strings use length + head 64 + tail 64 (full `==` only when `length <= 128`) | Same length+head idea as `_taskCallSignature`; no full payload buffer |
| `messageContentIdentity` | Unchanged; hot path stops calling it | Widget keys and existing tests keep the full fingerprint |

## Design

### 1. Suffix index

Shared helper (timeline and loader can each inline the same rule, or
share a one-liner):

```
suffixStart(prev, next):
  n = min(prev.length, next.length)
  for i in 0 .. n-1:
    if !identical(prev[i], next[i]) return i
  return n
```

- First incremental tick after a full parse: `prev` is the list stored
  in `_messages[cacheKey]` (already annotated). `next` is the tailer’s
  in-place list: prefix instances match, suffix is new or replaced.
- No previous list (cold start): treat `suffixStart = 0` and annotate
  the whole list (today’s `_finishIncremental` behavior).

If `next.length < prev.length`, do not take the suffix path: keep
today’s full annotate + full signature rebuild (truncate / compact
already rebuilds the tailer list).

### 2. Loader `_finishIncremental`

Files: `client/lib/services/session/ai_history_loader.dart`,
`client/lib/services/ai_history/tool_call_category_annotator.dart`.

Current order stays: annotate → attachment signatures / side token →
`List.of` → cache.

Changes:

1. Read `previous = _messages[cacheKey]`.
2. If `previous == null` or `next.length < previous.length`, annotate
   all messages and rebuild `_taskCallSignatures` from scratch (same
   as today).
3. Otherwise `start = suffixStart(previous, next)`.
4. `prefix = next.sublist(0, start)` (same instances as `previous`).
5. `annotatedSuffix = annotateToolCallCategories(next.sublist(start),
   resolver: …)`.
6. `annotated = [...prefix, ...annotatedSuffix]`.
7. Update signatures:

```
updateTaskCallSignatures(
  previousSigs, previousMessages, annotated,
  suffixStart: start, capability,
):
  out = Map.of(previousSigs)
  for each tool-call id in previousMessages[start…]:
    out.remove(id)
  for each tool-call id/signature in annotated[start…]:
    out[id] = signature
  return out
```

   Signature string format is unchanged (`_taskCallSignature`:
   normalized status, error flag, result length + head 64, subagent
   id). Prefix tool calls are not visited.

8. Side-transcript fingerprint and prune-on-change stay as they are,
   using the updated map.
9. `result = List<AiMessage>.of(annotated)` still, so the seat’s
   `identical(messages, _cliMessages)` is false when the suffix moved,
   while prefix message instances stay the same.

`annotateToolCallCategories` itself may keep scanning only the list it
is given. Callers pass the suffix, so the annotator does not need a
`fromIndex` parameter.

### 3. Timeline deltas

Files: `client/lib/services/conversation_timeline/conversation_timeline.dart`,
`client/lib/services/conversation_timeline/timeline_merge.dart`.

`computeCliTimelineDelta`:

- Unchanged prefix instances skipped with `identical` (already).
- Prefix id mismatch, or a **non-last** index whose cheap content
  differs → `CliTimelineInvalidated`.
- Last index content differs and `next.length == previous.length` →
  `CliTimelineLastReplaced(message: next.last)`.
- Last index content differs **and** `next.length > previous.length` →
  **new** `CliTimelineLastReplacedAndAppended`:
  - `message`: `next[previous.length - 1]`
  - `events`: CLI events for `next[previous.length …]`
- Else if only longer → `CliTimelineAppended` (today).

Replace `messageContentIdentity` in this function with cheap equality
(section 4).

`mergeTimelineIncremental`:

| Delta | Hot path |
|-------|----------|
| `Invalidated` (CLI or mailbox) | `mergeTimeline(events: allEvents, …)` as today |
| `LastReplaced` + mailbox unchanged | In-place replace by id (today) |
| `LastReplaced` + mailbox appended | Replace last, then insert mailbox events via `_insertIndexForEvent` |
| `LastReplacedAndAppended` | Replace last, then insert CLI (and mailbox if appended) events |
| `Appended` only | Insert new events; **do not** call `mergeTimeline` to checksum |
| Duplicate id in appended events | `mergeTimeline` fallback (today) |
| Last-replaced id missing in display list | `mergeTimeline` fallback (today) |

`buildConversationTimelineIncremental` builds `allEvents` **only** when
CLI or mailbox delta is `Invalidated` (or an incremental path hits a
fallback that needs it). Last-replaced-only already skips this;
append and combined deltas must skip it too.

`cliOrder` remains the index in `nextCliMessages`. Insert order remains
`(createdAt ?? epoch, cliOrder, id)`.

### 4. Cheap message equality

File: `client/packages/ai_message_core/lib/src/message_content_identity.dart`
(new function beside the existing fingerprint; do not change
`messageContentIdentity`).

```
bool messagesCheapEqual(AiMessage a, AiMessage b)
```

1. `identical(a, b)` → true.
2. `a.id`, `a.role`, `a.status`, `a.deliveryChannel` must match `b`.
3. Same `parts.length`; each pair:
   - Different runtime types → false.
   - `AiTextPart` / `AiReasoningPart`: `cheapStringEqual(text)`.
   - `AiToolCallPart`: `toolCallId`, `toolName`, `status`, `isError`,
     and `subagentAgentIdFromPart` (already in `ai_message_core`).
     Args: `identical(args, other.args)` or `cheapStringEqual` on
     both `argsText` values when either side has `argsText`; if both
     `argsText` are null/empty, compare `args?.length` only — do not
     `jsonEncode` maps on the hot path. Result: `cheapStringEqual` on
     `result is String ? result : result?.toString() ?? ''` (same
     conversion as `_taskCallSignature`). Category is ignored
     (annotation-only; not in `messageContentIdentity`).

`cheapStringEqual(a, b)`:

- `identical` → true.
- different `length` → false.
- `length <= 128` → `a == b`.
- else head 64 and tail 64 equal → true (do **not** scan or
  concatenate the middle).

Call sites that drop `messageContentIdentity` on the hot path:

- `computeCliTimelineDelta`
- `reuseHistoryMessageIdentity` / `_reuseUnchangedMessage`

UI / `sameMessageListContent` keep `messageContentIdentity`.

False negatives (cheap equal says different) keep the new instance;
content stays correct. False positives (same length, same head/tail,
different middle) are accepted for live refresh; the next length
change publishes the new instance. This matches the existing
task-call signature truncation.

### 5. Error and consistency

Still full rebuild / cold start (unchanged policy):

- Message list shrinks.
- Prefix id mismatch or non-last content change.
- Tailer compact / path change / head fingerprint change (new file
  first parse).
- Mailbox prefix `seq` mismatch, or read → unread.
- Duplicate appended ids; last-replaced id not in the display list.

Mailbox read failure stays CLI-only and does not block refresh.

Incremental append **must not** silently diverge from
`(createdAt, cliOrder, id)` order. Tests compare incremental results
to `mergeTimeline` on fixtures; production does not pay that cost
every tick.

### 6. Testing

Do not use wall-clock thresholds.

**Loader / annotator / signatures**

- Suffix annotate: prefix messages `identical` to previous; new and
  last messages annotated; already-categorized suffix parts stay the
  same instance.
- Signature update: prefix tool-call ids untouched without visiting
  those parts; new task call appears; last-message result growth
  updates that id; a tool call that existed only on the replaced last
  message is removed.
- Truncate (`next.length < previous.length`) still full-rebuilds
  signatures.

**Timeline**

- Pure append: prefix instances preserved; **no** requirement that
  production calls `mergeTimeline`; test compares ids/order to a
  separately computed `mergeTimeline` result.
- `LastReplacedAndAppended`: prefix identical; last content updated;
  new message inserted in order.
- `LastReplaced` + mailbox append: prefix identical; mailbox event
  inserted; last CLI message replaced.
- Prefix rewrite / shorter list: still `Invalidated` / full merge.
- Same-tick last grow + new message via
  `buildConversationTimelineIncremental` (not only the sealed delta
  type).

**Cheap equality**

- Large tool result, same head/tail/length → equal, and the test
  constructs a multi-kilobyte `result` so a regression that
  concatenates the full payload would be obvious in the comparison
  helper (assert the helper does not use `messageContentIdentity`).
- Length change or head/tail change → not equal.
- Streaming text append (length change) → not equal.
- Two tiny strings that differ in the middle (`length <= 128`) → not
  equal.

**Regression**

- Existing last-replaced, append identity, pagination reuse, and
  turn-end settle tests stay green.

## Acceptance criteria

- Live incremental refresh does not annotate or signature-scan prefix
  messages.
- Live append / last-replace / last-replace-plus-append do not allocate
  a full `allEvents` list or rebuild every `AiMessage` via
  `mergeTimeline`.
- Hot path does not call `messageContentIdentity`.
- Compact, truncate, and prefix rewrite still rebuild.
- `flutter analyze --no-fatal-infos --no-fatal-warnings` and the
  touched unit tests pass.

## Relationship to earlier specs

- Extends `2026-08-10` incremental tail and `2026-08-27` incremental
  timeline, **without** the “verify incremental insert against full
  merge on every tick” tax that 08-27 section 6 described.
- Does not reopen tailer `force` / compact heuristics from the
  2026-08-28 live incremental-only change.
- Markdown streaming layout remains out of scope.
