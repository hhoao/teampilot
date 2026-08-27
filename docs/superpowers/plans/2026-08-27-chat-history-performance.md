# Chat History Performance Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (recommended for inline execution) or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make large chat histories display quickly through batched decoding, paged initial history, lazy subagent attachments, and identity-preserving timeline updates without changing transcript semantics.

**Architecture:** Keep each CLI's `AiTranscriptAdapter` as the correctness authority. Add an optional page-reader capability for latest/older history, retain the existing full-parse fallback, and make `AiHistorySeat` publish only a display window while a complete index is built in the background. Keep attachment resolution and timeline merging seat-scoped, incremental, and single-flight.

**Tech Stack:** Dart, Flutter, `flutter_bloc`, `ai_message_core`, `ai_message_ui`, injected `Filesystem`, JSONL worker isolate, OpenCode SQLite incremental refresher, Flutter widget tests, `dart test`/Flutter test runner.

## Global Constraints

- Preserve existing five-CLI adapter output, fallback IDs, stream coalescing, tool-result status, mailbox ordering, and subagent recursion semantics.
- Keep `AiTranscriptAdapter.parse` as the full-history correctness fallback.
- Do not use `Directory.current`, raw filesystem access from UI, or `provider` state management.
- Keep all generic UI changes in `client/packages/ai_message_ui` and product wiring in `client/lib/pages/chat`.
- Use constructor injection for filesystem, decoder, page reader, clocks, and side-resolver fakes in tests.
- Every production behavior change starts with a failing test and is verified before the next task.
- Do not commit or modify the pre-existing unrelated worktree changes.

## File Map

- `client/lib/services/cli/registry/capabilities/ai_history_capability.dart`: optional page-reader contract and cursor/page types.
- `client/lib/services/session/ai_history_page.dart`: immutable page, cursor, and page-source result models.
- `client/lib/services/session/jsonl_transcript_page_reader.dart`: byte-window JSONL latest/older page reader.
- `client/lib/services/session/ai_transcript_tail_reader.dart`: batched full rebuild and shared line-boundary behavior.
- `client/lib/services/session/ai_history_loader.dart`: page/full-index orchestration, page cursor cache, attachment single-flight.
- `client/lib/cubits/ai_history_seat.dart`: display-window state, older-page application, lazy attachment API.
- `client/lib/services/session/subagent_attachment_inflater.dart`: one-attachment resolution and bounded recursive loading.
- `client/lib/services/conversation_timeline/timeline_merge.dart`: full merge fallback plus identity-preserving incremental merge helpers.
- `client/lib/services/conversation_timeline/conversation_timeline.dart`: cached timeline state and append/prepend decisions.
- `client/lib/pages/chat/session_chat_message_area.dart`: trigger lazy attachment resolution on subagent open.
- `client/lib/pages/chat/session_history_thread.dart`: connect older-page loading while preserving measured scroll anchoring.
- `client/packages/ai_message_ui/lib/src/`: only change if a widget callback is required for lazy loading; preserve viewport cache behavior.
- `client/test/services/session/`: decoder, paging, loader, attachment, timeline, and fallback tests.
- `client/test/cubits/`: seat/window and refresh behavior tests.
- `client/test/pages/chat/`: widget and scroll tests.
- `client/test/services/cli/registry/capabilities/history/`: per-CLI equivalence tests.

---

### Task 1: Batch JSONL full rebuild decoding

**Files:**
- Modify: `client/lib/services/session/ai_transcript_tail_reader.dart:164-203`
- Test: `client/test/services/session/ai_transcript_tail_reader_test.dart`

**Interfaces:**
- Consumes the existing `EventDecoder` and `AiTranscriptLineAppend` callbacks.
- Produces the same `TailReaderState` and `TailRefreshResult` as the current implementation.

- [ ] **Step 1: Add a failing decoder-call-count test**

Create an injected decoder that records each batch and returns decoded events in order. Write a transcript with three display events plus metadata, run the first `refresh`, and assert the decoder receives exactly one batch containing the three non-empty lines. Run:

```bash
cd client
flutter test test/services/session/ai_transcript_tail_reader_test.dart --plain-name 'full reload decodes all lines in one batch'
```

Expected: FAIL because the current implementation calls the decoder once per line.

- [ ] **Step 2: Implement one batched decode in `_fullReload`**

Collect non-empty lines while scanning bytes, call `_decodeEvents(lines)` once, iterate `events[i]` alongside `lines[i]`, and retain the existing fallback-sequence rollback, anchor update, and `coalesceAdjacentAssistantsInPlace` behavior.

- [ ] **Step 3: Run focused tail-reader tests**

```bash
cd client
flutter test test/services/session/ai_transcript_tail_reader_test.dart
```

Expected: all existing EOF, rewrite, anchor, stream-coalescing, and new batching tests pass.

- [ ] **Step 4: Commit the isolated optimization**

```bash
git add client/lib/services/session/ai_transcript_tail_reader.dart client/test/services/session/ai_transcript_tail_reader_test.dart
git commit -m "perf(history): batch JSONL full reload decoding"
```

### Task 2: Add page/cursor primitives and JSONL page reader

**Files:**
- Create: `client/lib/services/session/ai_history_page.dart`
- Create: `client/lib/services/session/jsonl_transcript_page_reader.dart`
- Modify: `client/lib/services/cli/registry/capabilities/ai_history_capability.dart`
- Test: `client/test/services/session/jsonl_transcript_page_reader_test.dart`

**Interfaces:**
- `AiHistoryCursor` contains an opaque source token, byte offset, and line hash; callers do not interpret a cursor.
- `AiHistoryPage` contains `messages`, `hasOlder`, `nextCursor`, `sourceToken`, and `rebuilt`.
- `AiTranscriptPageReader.readLatest(ctx, limit)` and `readOlder(ctx, cursor, limit)` return `Future<AiHistoryPage?>`.
- JSONL reader consumes `Filesystem`, `AiTranscriptLineAppend`, fallback prefix, and injectable `EventDecoder`.

- [ ] **Step 1: Add model tests for cursor/page immutability and source mismatch**

Test that a cursor from a different path/token is rejected, page messages and cursors are retained exactly, and an empty page reports `hasOlder` correctly.

```bash
cd client
flutter test test/services/session/jsonl_transcript_page_reader_test.dart --plain-name 'cursor rejects a changed source token'
```

Expected: FAIL because the new types and reader do not exist.

- [ ] **Step 2: Implement suffix-window line extraction**

Read from the end of the transcript in complete-line windows, expand the window until at least `limit` logical messages are available, and retain one preceding logical assistant boundary when the first event is a streamed continuation. Use one batch decoder call per window and the shared `lineAppend` callback.

- [ ] **Step 3: Implement older-page cursor reads**

Use the cursor’s byte range to read an earlier complete-line window, parse it with the same append callback, and return a cursor pointing before the earliest consumed line. If the source token, file size, or anchor hash is invalid, return `null` so the loader can use full parsing.

- [ ] **Step 4: Add page/full equivalence fixtures**

For Claude, Codex, Cursor, and flashskyai fixtures, concatenate latest and older pages, normalize by message id/role/parts, and compare with the existing full adapter output. Include fallback-id events and streamed assistant fragments.

- [ ] **Step 5: Run focused page-reader tests and commit**

```bash
cd client
flutter test test/services/session/jsonl_transcript_page_reader_test.dart test/services/session/ai_transcript_tail_reader_test.dart
```

Expected: PASS with equivalent page assembly and correct invalidation behavior.

```bash
git add client/lib/services/session/ai_history_page.dart client/lib/services/session/jsonl_transcript_page_reader.dart client/lib/services/cli/registry/capabilities/ai_history_capability.dart client/test/services/session/jsonl_transcript_page_reader_test.dart
git commit -m "feat(history): add paged transcript source"
```

### Task 3: Wire page readers for all supported CLIs and preserve full fallback

**Files:**
- Modify: `client/lib/services/cli/claude/capabilities/history/ai_transcript.dart`
- Modify: `client/lib/services/cli/codex/capabilities/history/ai_transcript.dart`
- Modify: `client/lib/services/cli/cursor/capabilities/history/ai_transcript.dart`
- Modify: `client/lib/services/cli/flashskyai/capabilities/history/ai_transcript.dart`
- Modify: `client/lib/services/cli/opencode/capabilities/history/ai_transcript.dart`
- Modify: capability definition files under each CLI’s `capabilities/history/`
- Test: `client/test/services/cli/registry/capabilities/history/ai_history_page_equivalence_test.dart`
- Test: existing per-CLI history capability wiring tests

**Interfaces:**
- Each JSONL capability returns a `JsonlTranscriptPageReader` configured with its own `lineAppend`, fallback prefix, and adapter identity.
- OpenCode returns a page reader backed by its existing stable SQLite message/part ordering and returns `null` when its store cannot provide a stable cursor.

- [ ] **Step 1: Add a failing capability-wiring matrix test**

Assert that Claude, Codex, Cursor, flashskyai, and OpenCode expose either a page reader or an explicit full-parse fallback, and that page output can be compared with the adapter for every existing fixture family.

```bash
cd client
flutter test test/services/cli/registry/capabilities/history/ai_history_page_equivalence_test.dart
```

Expected: FAIL because capabilities do not expose the new page source.

- [ ] **Step 2: Wire JSONL readers without duplicating parser semantics**

Pass the existing append functions and fallback prefixes into the shared JSONL reader. Do not add CLI-name conditionals to the loader or UI.

- [ ] **Step 3: Add OpenCode page queries**

Reuse the existing SQLite refresher’s row ordering and conversion helpers. The page reader must return the same `AiMessage` parts as `OpenCodeAiTranscriptAdapter`, and must return `null` for unsupported schema or unstable ordering.

- [ ] **Step 4: Run all history capability tests**

```bash
cd client
flutter test test/services/cli/registry/capabilities/history test/services/cli/registry/session_history_registration_test.dart
```

Expected: PASS with no changes to existing full-parse fixture expectations.

- [ ] **Step 5: Commit the capability wiring**

```bash
git add client/lib/services/cli client/test/services/cli/registry/capabilities/history/ai_history_page_equivalence_test.dart
git commit -m "feat(history): wire paged readers for supported CLIs"
```

### Task 4: Make loader and seat publish a recent window first

**Files:**
- Modify: `client/lib/services/session/ai_history_loader.dart`
- Modify: `client/lib/services/session/ai_history_load_result.dart`
- Modify: `client/lib/cubits/ai_history_seat.dart`
- Modify: `client/lib/services/session/session_history_pagination.dart`
- Test: `client/test/services/session/ai_history_loader_test.dart`
- Test: `client/test/cubits/ai_history_cubit_test.dart`
- Test: `client/test/cubits/ai_history_seat_no_blank_test.dart`

**Interfaces:**
- Add `AiHistoryLoadResult.hasOlder`, `AiHistoryLoadResult.cursor`, and `AiHistoryLoadResult.isComplete`.
- Add `AiHistoryLoader.loadOlder({required sessionId, required memberId})` returning `AiHistoryLoadResult?`.
- Add `AiHistorySeat.loadOlder()` that updates `_allMessages`, `_visibleCount`, cursor, and runtime without clearing current content.
- Keep `AiHistoryLoader.load(..., force: false)` as the public entry point and route unsupported page readers through the existing full path.

- [ ] **Step 1: Add failing loader/seat window tests**

Use a fake page reader returning 30 recent messages and an older page. Assert first load publishes the recent messages, reports `hasOlder`, does not call full adapter parse, and `loadOlder()` prepends the older messages while preserving the recent message instances.

```bash
cd client
flutter test test/services/session/ai_history_loader_test.dart test/cubits/ai_history_cubit_test.dart --plain-name 'publishes recent page before older history'
```

Expected: FAIL because the load result has no page metadata and seat always expects a complete list.

- [ ] **Step 2: Implement page-first loader orchestration**

Resolve the seat and cache token once, ask the capability page reader for the latest page, merge mailbox records for that page, and return immediately. Start one background full-index future per cache key; cache it for search/task consumers and use full parsing to seed/verify the page state.

- [ ] **Step 3: Implement seat older-page application**

Prepend only older messages, dedupe by the existing rules, retain object identity for the existing suffix, increase the visible window, and emit state without calling `runtime.setLoading()` or clearing pending messages.

- [ ] **Step 4: Preserve unsupported/failure fallback**

If a page reader returns `null` or throws, execute the existing full load path. If a later page fails, retain the current runtime and emit the non-blocking error state.

- [ ] **Step 5: Add full-index consistency tests**

Compare concatenated pages with the background full parse for all fixture families. Assert that full index consumers still see old task-create messages and chat find scans the full index rather than only the display window.

- [ ] **Step 6: Run focused seat/loader tests and commit**

```bash
cd client
flutter test test/services/session/ai_history_loader_test.dart test/cubits/ai_history_cubit_test.dart test/cubits/ai_history_seat_no_blank_test.dart
```

Expected: PASS with current no-blank, pending, refresh, and window tests retained.

```bash
git add client/lib/services/session/ai_history_loader.dart client/lib/services/session/ai_history_load_result.dart client/lib/cubits/ai_history_seat.dart client/lib/services/session/session_history_pagination.dart client/test/services/session/ai_history_loader_test.dart client/test/cubits/ai_history_cubit_test.dart client/test/cubits/ai_history_seat_no_blank_test.dart
git commit -m "feat(history): publish recent pages before full index"
```

### Task 5: Add lazy, single-flight subagent attachment loading

**Files:**
- Modify: `client/lib/services/session/ai_history_loader.dart`
- Modify: `client/lib/cubits/ai_history_seat.dart`
- Modify: `client/lib/services/session/subagent_attachment_inflater.dart`
- Modify: `client/lib/pages/chat/session_chat_message_area.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Test: `client/test/services/session/subagent_attachment_inflater_test.dart`
- Test: `client/test/services/session/ai_history_loader_test.dart`
- Test: `client/test/pages/chat/ai_history_multi_seat_widget_test.dart`

**Interfaces:**
- `SubagentAttachmentInflater.inflateOne({required part, required ctx, required capability, required rootTranscriptPath})` returns one attachment and keeps current depth-zero/degraded behavior.
- `AiHistoryLoader.loadSubagentAttachment({required cacheKey, required toolCallId, required ctx, required capability, required messages})` returns `Future<AiSubagentAttachment?>` and shares in-flight work per `(cacheKey, toolCallId)`.
- `AiHistorySeat.loadSubagentAttachment(String toolCallId)` updates the cached attachment map and epoch.

- [ ] **Step 1: Add failing tests for lazy and single-flight behavior**

Assert that initial history load makes zero side-resolver calls, two concurrent requests for one id make one resolver call, a successful request is cached, and a missing side transcript produces the existing tool-result fallback.

```bash
cd client
flutter test test/services/session/subagent_attachment_inflater_test.dart test/services/session/ai_history_loader_test.dart --plain-name 'loads one subagent attachment on demand'
```

Expected: FAIL because initial loader currently inflates all attachments and no per-id API exists.

- [ ] **Step 2: Extract one-attachment resolution from recursive traversal**

Keep recursive workflow child handling in the inflater, but make the root operation able to resolve exactly one requested tool call. Do not change max depth or fallback content.

- [ ] **Step 3: Add cache and in-flight maps**

Remove eager `inflate` from initial load, retain lightweight task signatures, and add per-seat single-flight maps. Invalidate them with the existing session cache invalidation.

- [ ] **Step 4: Connect the UI open action**

When `onOpenSubagent` receives an id, await `historySeat.loadSubagentAttachment(id)`, then push the preview if available. Keep the existing toast for a null result and do not perform state notifications during build.

- [ ] **Step 5: Test automatic running-agent preview**

Ensure auto-follow requests only load the selected running id and do not inflate unrelated historical subagents.

- [ ] **Step 6: Run focused attachment/widget tests and commit**

```bash
cd client
flutter test test/services/session/subagent_attachment_inflater_test.dart test/services/session/ai_history_loader_test.dart test/pages/chat/ai_history_multi_seat_widget_test.dart
```

Expected: PASS with existing workflow, fallback, and multi-seat behavior.

```bash
git add client/lib/services/session/ai_history_loader.dart client/lib/cubits/ai_history_seat.dart client/lib/services/session/subagent_attachment_inflater.dart client/lib/pages/chat/session_chat_message_area.dart client/lib/pages/chat/session_chat_view.dart client/test/services/session/subagent_attachment_inflater_test.dart client/test/services/session/ai_history_loader_test.dart client/test/pages/chat/ai_history_multi_seat_widget_test.dart
git commit -m "perf(history): lazy-load subagent attachments"
```

### Task 6: Reuse timeline and message instances on refresh

**Files:**
- Modify: `client/lib/services/conversation_timeline/timeline_merge.dart`
- Modify: `client/lib/services/conversation_timeline/conversation_timeline.dart`
- Modify: `client/lib/cubits/ai_history_seat.dart`
- Test: `client/test/services/conversation_timeline/timeline_merge_test.dart`
- Test: `client/test/cubits/ai_history_seat_no_blank_test.dart`

**Interfaces:**
- Add a seat-scoped timeline snapshot containing CLI list identity, mailbox fingerprint, and merged list.
- Add `mergeTimelineIncremental(previous, cliDelta, mailboxDelta)` that returns the previous message instances for unchanged events and uses the existing full merge for invalidated order.

- [ ] **Step 1: Add failing identity tests**

Build a timeline, append one CLI event, and assert all previous message objects remain identical. Add one mailbox event and assert only the new/interleaved segment is rebuilt. Add a reorder/delete case that must use full merge.

```bash
cd client
flutter test test/services/conversation_timeline/timeline_merge_test.dart --plain-name 'incremental merge preserves unchanged message instances'
```

Expected: FAIL because current merge always constructs new `AiMessage` objects.

- [ ] **Step 2: Implement incremental merge with correctness fallback**

Use sorted insertion only when the new events are append-only or mailbox-only and preserve the exact existing comparator/dedupe rules. If fingerprints reveal a rewrite, deletion, or order change, call the existing full merge.

- [ ] **Step 3: Integrate seat mailbox and CLI snapshots**

Skip timeline merge when both snapshots are unchanged. Ensure pending overlays are still applied after the cached timeline and do not alter cached CLI message identity.

- [ ] **Step 4: Run timeline and seat tests and commit**

```bash
cd client
flutter test test/services/conversation_timeline test/cubits/ai_history_seat_no_blank_test.dart
```

Expected: PASS with mailbox ordering, dedupe, refresh, and pending tests.

```bash
git add client/lib/services/conversation_timeline client/lib/cubits/ai_history_seat.dart client/test/services/conversation_timeline client/test/cubits/ai_history_seat_no_blank_test.dart
git commit -m "perf(history): preserve timeline message identity"
```

### Task 7: Integrate older-page scrolling and preserve viewport behavior

**Files:**
- Modify: `client/lib/pages/chat/session_history_thread.dart`
- Modify: `client/lib/pages/chat/session_history_review_messages.dart`
- Modify: `client/lib/cubits/ai_history_seat.dart`
- Test: `client/test/pages/chat/session_history_thread_test.dart`
- Test: `client/test/pages/chat/session_history_review_refreshing_test.dart`

**Interfaces:**
- `SessionHistoryThread` continues to use `onLoadOlder`; the callback now awaits seat page loading before measured correction.
- `VirtualThreadViewport` remains the rendering primitive; only add a callback if an existing callback cannot express the page-complete boundary.

- [ ] **Step 1: Add failing scroll/page tests**

Start with a recent page, scroll to the top, load an older page, and assert the old top message remains at the same screen position after prepend. Assert that a page failure leaves current messages mounted.

```bash
cd client
flutter test test/pages/chat/session_history_thread_test.dart --plain-name 'keeps scroll position when loading older history'
```

Expected: FAIL because the test uses the new asynchronous older-page callback.

- [ ] **Step 2: Connect seat `loadOlder` to the existing anchored callback**

Await the seat operation, wait for layout, and apply measured extent correction exactly once. Keep pagination armed/disarmed logic and existing stick-to-end behavior.

- [ ] **Step 3: Verify no first-frame Markdown regression**

Use the existing `mountTurns` and `fillDataWindow` behavior; ensure page-first data does not cause an additional synchronous full list build.

- [ ] **Step 4: Run focused widget tests and commit**

```bash
cd client
flutter test test/pages/chat/session_history_thread_test.dart test/pages/chat/session_history_review_refreshing_test.dart
```

Expected: PASS with scroll, refreshing, loading, error, and no-blank coverage.

```bash
git add client/lib/pages/chat/session_history_thread.dart client/lib/pages/chat/session_history_review_messages.dart client/lib/cubits/ai_history_seat.dart client/test/pages/chat/session_history_thread_test.dart client/test/pages/chat/session_history_review_refreshing_test.dart
git commit -m "feat(history): load older pages from chat scroll"
```

### Task 8: Cache tool-result indexing and add performance evidence

**Files:**
- Modify: `client/lib/services/cli/claude/capabilities/history/compatible_tool_result_enricher.dart`
- Modify: `client/lib/services/session/ai_history_loader.dart`
- Modify: `client/lib/services/session/workspace_session_content_index.dart` to share the history source token/index with chat history when its warm path reads the same transcript
- Test: `client/test/services/cli/registry/capabilities/history/claude_compatible_tool_result_enricher_test.dart`
- Test: `client/test/services/session/ai_history_loader_test.dart`
- Create: `client/test/performance/history_load_perf_test.dart`

**Interfaces:**
- Tool-result index cache is keyed by transcript source token and stores only decoded tool-use result records.
- Appended transcript data updates the index from the append boundary; rewritten data discards it.
- Optional `AiHistoryLoadTimings` records phase durations and decoder/side-IO counts without changing production behavior when disabled.

- [ ] **Step 1: Add failing cache reuse tests**

Call the enricher twice with the same bundle token and assert the transcript decoder/indexer runs once. Append a line and assert only the append portion is decoded. Rewrite the bundle and assert a full index rebuild.

```bash
cd client
flutter test test/services/cli/registry/capabilities/history/claude_compatible_tool_result_enricher_test.dart --plain-name 'reuses tool result index for unchanged transcript'
```

Expected: FAIL because the enricher currently reads and decodes the full transcript every time.

- [ ] **Step 2: Implement token-bound index reuse**

Pass the loader’s source token into the enricher/index cache, preserve current replacement and error semantics, and invalidate the cache with loader session invalidation.

- [ ] **Step 3: Add phase timing hooks**

Use an injectable callback or no-op timing sink around locate/read/decode/parse/enrich/inflate/merge/first publish. Avoid logging every live refresh by default.

- [ ] **Step 4: Add performance scenario assertions**

Use synthetic large JSONL and many subagent records to assert one full decoder batch, zero initial side-transcript reads, identity-preserving unchanged refresh, and page-first publish order. Do not assert a fixed wall-clock threshold.

- [ ] **Step 5: Run focused tests and commit**

```bash
cd client
flutter test test/services/cli/registry/capabilities/history/claude_compatible_tool_result_enricher_test.dart test/services/session/ai_history_loader_test.dart test/performance/history_load_perf_test.dart
```

Expected: PASS with current truncated-tool-result fixture regression tests.

```bash
git add client/lib/services/cli/claude/capabilities/history/compatible_tool_result_enricher.dart client/lib/services/session/ai_history_loader.dart client/lib/services/session/workspace_session_content_index.dart client/test/services/cli/registry/capabilities/history/claude_compatible_tool_result_enricher_test.dart client/test/services/session/ai_history_loader_test.dart client/test/performance/history_load_perf_test.dart
git commit -m "perf(history): cache tool result indexing and timings"
```

### Task 9: Full regression verification and performance comparison

**Files:**
- Test: existing full test suite and all changed tests
- Modify: only the affected Task 1-8 files when a verification failure has a failing regression test

- [ ] **Step 1: Run analyzer**

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: exit code 0 with no fatal diagnostics.

- [ ] **Step 2: Run the repository test runner**

```bash
cd client
dart run tool/run_tests.dart
```

Expected: exit code 0 and no failed tests.

- [ ] **Step 3: Run targeted history and UI tests again**

```bash
cd client
flutter test test/services/session test/services/conversation_timeline test/services/cli/registry/capabilities/history test/cubits/ai_history_cubit_test.dart test/cubits/ai_history_seat_no_blank_test.dart test/pages/chat/session_history_thread_test.dart
```

Expected: exit code 0.

- [ ] **Step 4: Review diff and unrelated changes**

```bash
git diff --check HEAD~8..HEAD
git status --short
git diff --stat HEAD~8..HEAD
```

Expected: only the committed chat-history changes are in the implementation diff; pre-existing unrelated modifications remain uncommitted and untouched.

- [ ] **Step 5: Capture profile evidence when available**

Capture equivalent before/after profile recordings for a large transcript and run:

```bash
cd client
dart run tool/analyze_performance_json.dart /path/to/history-after.json --format summary
```

Expected: the first publish occurs before older-page/full-index work and no large full-reload decoder fan-out appears.
