# Mobile Session History ANR P0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (recommended) or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep mobile session opening interactive by moving page/full transcript CPU and byte transfer off the UI isolate and limiting initial message mounting to the visible window.

**Architecture:** Introduce a reusable transferable-transcript transport for isolate requests. A resident JSONL page worker performs event decoding and page assembly; `AiHistoryLoader` publishes a page or cached/loading state without awaiting a full parse after a page miss. `SessionHistoryThread` disables data-window fill and full turn retention only in mobile mode.

**Tech Stack:** Flutter/Dart isolates, `TransferableTypedData`, `AiHistoryLoader`, `JsonlTranscriptPageReader`, `VirtualThreadViewport`, `dart run tool/run_tests.dart`.

## Global Constraints

- Android always uses SSH-backed history files; do not replace injected `Filesystem` or `SessionHistoryContext` roots.
- Never invoke `flutter test` directly; use `cd client && dart run tool/run_tests.dart ...`.
- Do not synchronously parse a large transcript on the UI isolate when worker startup, transfer, or request fails.
- Preserve the existing non-empty-history protection and identity-preserving incremental paths.
- Mobile means Android or iOS for this performance policy; desktop behavior stays unchanged.
- Do not log raw transcript text, tool output, or message contents.
- Before claiming completion run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.

---

## File map

- Create `client/lib/services/session/history_isolate_transport.dart`: one-shot transferable fragment and bundle transport records plus materialization helpers.
- Modify `client/lib/services/session/history_parse_worker.dart`: send transport records instead of raw `AiTranscriptBundle` objects.
- Create `client/lib/services/session/jsonl_transcript_page_parser.dart`: pure logical page assembly extracted from the page reader, callable in an isolate.
- Create `client/lib/services/session/jsonl_page_worker.dart`: resident worker that receives transferable JSONL lines and returns `AiHistoryPage`.
- Modify `client/lib/services/session/jsonl_transcript_page_reader.dart`: keep filesystem/range logic on the caller and delegate page assembly to the page worker.
- Modify `client/lib/services/session/ai_history_loader.dart`: schedule full indexing after a page miss and publish without awaiting it; add byte/mode diagnostics.
- Modify `client/lib/cubits/ai_history_seat.dart`: consume the registered background full-index future through the existing hydration path when the initial result is incomplete.
- Modify `client/lib/pages/chat/session_history_thread.dart`: add the mobile performance mode and disable full data-window fill/retention there.
- Test `client/test/services/session/history_isolate_transport_test.dart`: transport round-trip.
- Modify `client/test/services/session/history_parse_worker_test.dart`: large parse uses the transport boundary.
- Modify `client/test/services/session/jsonl_decode_worker_test.dart`: large page payload uses the worker path without caller sync fallback.
- Modify `client/test/services/session/jsonl_transcript_page_reader_test.dart`: page parser/worker equivalence and failure behavior.
- Modify `client/test/services/session/ai_history_loader_test.dart`: page miss returns immediately with a registered background full index.
- Modify `client/test/pages/chat/session_history_thread_test.dart`: mobile mode does not fill/retain all turns and desktop mode remains unchanged.

## Task 1: Transfer raw transcript bytes without deep-copying lists

**Files:**

- Create: `client/lib/services/session/history_isolate_transport.dart`
- Modify: `client/lib/services/session/history_parse_worker.dart`
- Create: `client/test/services/session/history_isolate_transport_test.dart`
- Modify: `client/test/services/session/history_parse_worker_test.dart`

**Interfaces:**

- Produce `HistoryTransferBundle.fromBundle(AiTranscriptBundle bundle)` and `HistoryTransferBundle.materialize()`.
- `HistoryTransferBundle` preserves `adapterId`, ordered fragment names/bytes, and `hints`.
- `HistoryParseWorker.parse` keeps its current public signature and only changes its private wire record.

- [ ] **Step 1: Write the failing transport round-trip test.**

Add `client/test/services/session/history_isolate_transport_test.dart` with this test:

```dart
test('transfer bundle materializes ordered fragment bytes and hints', () {
  final source = AiTranscriptBundle(
    adapterId: 'claude',
    hints: const {'path': '/tmp/a.jsonl'},
    fragments: [
      AiTranscriptFragment(name: 'a', bytes: [1, 2]),
      AiTranscriptFragment(name: 'b', bytes: [3, 4, 5]),
    ],
  );

  final restored = HistoryTransferBundle.fromBundle(source).materialize();

  expect(restored.adapterId, 'claude');
  expect(restored.hints, const {'path': '/tmp/a.jsonl'});
  expect(restored.fragments.map((f) => f.name), ['a', 'b']);
  expect(restored.fragments.map((f) => f.bytes), [
    [1, 2],
    [3, 4, 5],
  ]);
});
```

- [ ] **Step 2: Run the focused test and verify it fails for the missing transport type.**

Run:

```text
cd client && dart run tool/run_tests.dart test/services/session/history_isolate_transport_test.dart
```

Expected: compile failure because `HistoryTransferBundle` does not exist yet.

- [ ] **Step 3: Implement the minimal transport.**

Use `TransferableTypedData` and reconstruct `AiTranscriptBundle` only after
`materialize()`:

```dart
final class HistoryTransferBundle {
  HistoryTransferBundle._({
    required this.adapterId,
    required this.fragments,
    required this.hints,
  });

  factory HistoryTransferBundle.fromBundle(AiTranscriptBundle bundle) {
    return HistoryTransferBundle._(
      adapterId: bundle.adapterId,
      fragments: [
        for (final fragment in bundle.fragments)
          HistoryTransferFragment(
            name: fragment.name,
            bytes: TransferableTypedData.fromList([
              Uint8List.fromList(fragment.bytes),
            ]),
          ),
      ],
      hints: Map<String, String>.of(bundle.hints),
    );
  }

  final String adapterId;
  final List<HistoryTransferFragment> fragments;
  final Map<String, String> hints;

  AiTranscriptBundle materialize() => AiTranscriptBundle(
    adapterId: adapterId,
    hints: hints,
    fragments: [
      for (final fragment in fragments) fragment.materialize(),
    ],
  );
}
```

Add `dart:typed_data` and make `HistoryTransferFragment.materialize()` return
an `AiTranscriptFragment` backed by `bytes.materialize().asUint8List()`.

- [ ] **Step 4: Change the parse worker wire request.**

Replace `_HistoryParseRequest.bundle` with `HistoryTransferBundle bundle`.
Construct it immediately before `port.send` and call `.materialize()` in
`_historyParseWorkerEntry` before `parseHistoryBundleInWorker`.

- [ ] **Step 5: Run the transport and worker tests.**

Run:

```text
cd client && dart run tool/run_tests.dart test/services/session/history_isolate_transport_test.dart test/services/session/history_parse_worker_test.dart
```

Expected: all tests pass and the existing worker timeout/exit tests remain
green.

- [ ] **Step 6: Commit the isolated change.**

```text
git add client/lib/services/session/history_isolate_transport.dart client/lib/services/session/history_parse_worker.dart client/test/services/session/history_isolate_transport_test.dart client/test/services/session/history_parse_worker_test.dart
git commit -m "perf: transfer session history bytes between isolates"
```

## Task 2: Move JSONL page decoding and assembly into a resident worker

**Files:**

- Create: `client/lib/services/session/jsonl_transcript_page_parser.dart`
- Create: `client/lib/services/session/jsonl_page_worker.dart`
- Modify: `client/lib/services/session/jsonl_transcript_page_reader.dart`
- Modify: `client/test/services/session/jsonl_decode_worker_test.dart`
- Modify: `client/test/services/session/jsonl_transcript_page_reader_test.dart`

**Interfaces:**

- Produce `JsonlTranscriptPageParser.parse({required List<JsonlTranscriptLine> lines, required int limit, required String sourceToken, required bool rebuilt})` returning `AiHistoryPage?`.
- Produce `JsonlPageWorker.instance.parse({required String adapterId, required List<JsonlTranscriptLine> lines, required int limit, required String sourceToken, required bool rebuilt})` returning `Future<AiHistoryPage?>`.
- `JsonlTranscriptPageReader` retains remote `stat`, range reads, line splitting, source-token checks, and cursor offsets; it delegates `_buildPage` to `JsonlPageWorker`.

- [ ] **Step 1: Add a parser equivalence test before extraction.**

In `jsonl_transcript_page_reader_test.dart`, add a test that reads the
existing Claude fixture with the injected filesystem, splits it into
`JsonlTranscriptLine` values, calls `JsonlPageWorker.instance.parse`, and
asserts the worker page contract.

```dart
test('page worker preserves the reader page contract', () async {
  final page = await JsonlPageWorker.instance.parse(
    adapterId: 'claude',
    lines: lines,
    sourceToken: 'fixture-token',
    rebuilt: true,
    limit: 3,
  );

  expect(page, isNotNull);
  expect(page!.messages, hasLength(3));
  expect(page.hasOlder, isTrue);
  expect(page.nextCursor, isNotNull);
});
```


- [ ] **Step 2: Run the reader test to establish the failing worker contract.**

Run:

```text
cd client && dart run tool/run_tests.dart test/services/session/jsonl_transcript_page_reader_test.dart
```

Expected: the new worker-path test fails because `JsonlPageWorker` and the
extracted parser do not exist.

- [ ] **Step 3: Extract logical page assembly without changing its rules.**

Move the current `_buildPage`, `_parseFrom`, `_containsToolResult`,
`_contentContainsToolResult`, `_unsafeFallback`, `_rawStartIndex`,
`_sameMessages`, `_samePart`, and their data records from
`jsonl_transcript_page_reader.dart` into `jsonl_transcript_page_parser.dart`.
Make line data explicit:

```dart
final class JsonlTranscriptLine {
  const JsonlTranscriptLine({required this.offset, required this.bytes});

  final int offset;
  final List<int> bytes;
}
```

The parser selects the append function through the constructor, so its test
path can inject the existing Claude append function and production worker code
can select the function by adapter id.

- [ ] **Step 4: Add the resident page worker.**

The worker request contains adapter id, transferable line byte records, line
offsets, limit, source token, and rebuilt flag. The worker materializes lines,
decodes them with `decodeJsonlLinesSync`, selects the existing append function
for `claude`, `codex`, `cursor`, and `flashskyai`, then calls the extracted
parser. A worker error completes the caller future with an error; there is no
large caller-isolate decode fallback.

- [ ] **Step 5: Delegate the reader and remove the large sync threshold.**

Change `_buildPage` to call `JsonlPageWorker.parse` with the split lines. Keep
the page reader’s empty-page path local because it has no JSON work. Do not
call `decodeJsonlLinesSync` from the reader for a non-empty page.

- [ ] **Step 6: Add worker-mode diagnostics and test failure behavior.**

Record only line count, byte count, adapter id, and elapsed milliseconds. Add a
test that installs a worker timeout and verifies `readLatest` returns a page
miss (`null`) rather than synchronously invoking the decoder.

- [ ] **Step 7: Run focused page tests.**

```text
cd client && dart run tool/run_tests.dart test/services/session/jsonl_decode_worker_test.dart test/services/session/jsonl_transcript_page_reader_test.dart
```

Expected: all focused tests pass, including existing cursor and unsafe-boundary
cases.

- [ ] **Step 8: Commit the page-worker change.**

```text
git add client/lib/services/session/jsonl_transcript_page_parser.dart client/lib/services/session/jsonl_page_worker.dart client/lib/services/session/jsonl_transcript_page_reader.dart client/test/services/session/jsonl_decode_worker_test.dart client/test/services/session/jsonl_transcript_page_reader_test.dart
git commit -m "perf: move session history page assembly off UI isolate"
```

## Task 3: Make page misses non-blocking and keep full indexing in the background

**Files:**

- Modify: `client/lib/services/session/ai_history_loader.dart`
- Modify: `client/lib/cubits/ai_history_seat.dart`
- Modify: `client/test/services/session/ai_history_loader_test.dart`
- Modify: `client/test/cubits/ai_history_seat_no_blank_test.dart`

**Interfaces:**

- Add private `AiHistoryLoader._scheduleFullIndex(...)` returning `Future<AiHistoryLoadResult>` and registering it in `_fullIndexFutures[cacheKey]`.
- A page miss returns `AiHistoryLoadResult.isComplete == false` with the previous non-empty messages when available, otherwise an empty list.
- The seat’s existing `_hydrateFullIndex` remains the only path that replaces the initial page/loading window after the background future completes.

- [ ] **Step 1: Write the failing non-blocking loader test.**

Add a controllable parse executor whose future completes only when a test
completer is completed. Assert that `loader.load(force: true)` returns before
that completer and that `loader.fullIndex(...)` exposes the pending future.

```dart
test('page miss publishes loading state without awaiting full index', () async {
  final parseGate = Completer<HistoryParseResult>();
  final executor = _GateHistoryParseExecutor(parseGate.future);
  final loader = makeLoader(parseExecutor: executor);

  final result = await loader.load(
    session: session,
    memberId: 'member',
    launchContext: launchContext,
    force: true,
  );

  expect(result.isComplete, isFalse);
  expect(result.messages, isEmpty);
  expect(
    await loader.fullIndex(sessionId: session.sessionId, memberId: 'member'),
    isNotNull,
  );
  expect(executor.parseStarted, isTrue);
});
```

- [ ] **Step 2: Run the loader test and confirm it fails by waiting for parse.**

```text
cd client && dart run tool/run_tests.dart test/services/session/ai_history_loader_test.dart --plain-name "page miss publishes loading state without awaiting full index"
```

Expected: timeout/failure because the current page-miss branch waits for the
full parse before returning.

- [ ] **Step 3: Register a background full-index future at the page miss.**

After `_tryPageFirst` returns `null`, set the cache state to incomplete and
call `_scheduleFullIndex` rather than continuing through the full parse inline:

```dart
_complete[cacheKey] = false;
unawaited(_scheduleFullIndex(
  session: session,
  cli: cli,
  effectiveMemberId: effectiveMemberId,
  ctx: ctx,
  cacheKey: cacheKey,
  token: token,
));
final previous = _messages[cacheKey] ?? const <AiMessage>[];
return _result(
  cacheKey: cacheKey,
  messages: previous,
  cli: cli,
  subagentAttachments: _attachments[cacheKey] ?? const {},
);
```

`_scheduleFullIndex` stores a single `Future` in `_fullIndexFutures`, runs
`_loadOnce(... force: true, skipPaging: true)` asynchronously, and preserves
the existing single-flight behavior. Do not await the scheduled future in the
page-miss branch.

- [ ] **Step 4: Ensure seat hydration can consume the registered future.**

Keep the existing `if (!result.isComplete) unawaited(_hydrateFullIndex(...))`
branch. Add the focused seat test that completes the gate, pumps the cubit,
and verifies the initial empty window is replaced with the non-empty full
messages without an empty-content wipe.

- [ ] **Step 5: Add phase diagnostics.**

Log `bundleBytes`, `pageBytes`, `parseMode`, and phase durations around page
worker, full locate/read, and parse worker calls. Every diagnostic line must
omit message text and raw paths unless the existing logs already use a path
hint for watcher diagnostics.

- [ ] **Step 6: Run loader and seat focused tests.**

```text
cd client && dart run tool/run_tests.dart test/services/session/ai_history_loader_test.dart test/cubits/ai_history_seat_no_blank_test.dart
```

Expected: all focused tests pass, including existing full-index hydration,
empty reload, and identity-preserving tests.

- [ ] **Step 7: Commit the non-blocking loader change.**

```text
git add client/lib/services/session/ai_history_loader.dart client/lib/cubits/ai_history_seat.dart client/test/services/session/ai_history_loader_test.dart client/test/cubits/ai_history_seat_no_blank_test.dart
git commit -m "fix: keep session history page misses off the opening path"
```

## Task 4: Bound initial mobile message mounting

**Files:**

- Modify: `client/lib/pages/chat/session_history_thread.dart`
- Modify: `client/test/pages/chat/session_history_thread_test.dart`

**Interfaces:**

- Add optional `bool? mobilePerformanceMode` to `SessionHistoryThread` for
  deterministic tests; default it to `Platform.isAndroid || Platform.isIOS`.
- Desktop uses `retainMountedTurns: true` and `fillDataWindow: true` exactly as
  before.
- Mobile uses `retainMountedTurns: false` and `fillDataWindow: false`.

- [ ] **Step 1: Add the failing widget tests.**

Add two tests that locate `VirtualThreadViewport` after opening a 40-message
runtime:

```dart
testWidgets('mobile history does not fill the loaded data window', (tester) async {
  await tester.pumpWidget(buildThread(mobilePerformanceMode: true));
  await tester.pumpAndSettle();

  final viewport = tester.widget<VirtualThreadViewport>(
    find.byType(VirtualThreadViewport),
  );
  expect(viewport.fillDataWindow, isFalse);
  expect(viewport.retainMountedTurns, isFalse);
});

testWidgets('desktop history keeps the existing residency policy', (tester) async {
  await tester.pumpWidget(buildThread(mobilePerformanceMode: false));
  final viewport = tester.widget<VirtualThreadViewport>(
    find.byType(VirtualThreadViewport),
  );
  expect(viewport.fillDataWindow, isTrue);
  expect(viewport.retainMountedTurns, isTrue);
});
```

- [ ] **Step 2: Run the widget tests and verify the mobile test fails.**

```text
cd client && dart run tool/run_tests.dart test/pages/chat/session_history_thread_test.dart --plain-name "mobile history does not fill the loaded data window"
```

Expected: failure because the current widget always passes `true` for both
policies.

- [ ] **Step 3: Implement the platform-gated policy.**

Store the resolved mode in the widget and pass these exact values:

```dart
final mobile = widget.mobilePerformanceMode ??
    (Platform.isAndroid || Platform.isIOS);

retainMountedTurns: !mobile,
fillDataWindow: !mobile,
```

Do not change `anchorEnd`, `overscan`, pagination callbacks, scroll-anchor
restore, selection nesting, or message rendering policy in this task.

- [ ] **Step 4: Run the history-thread tests.**

```text
cd client && dart run tool/run_tests.dart test/pages/chat/session_history_thread_test.dart packages/ai_message_ui/test/virtual_thread_viewport_test.dart
```

Expected: both mobile policy tests pass and existing viewport virtualization
tests remain green.

- [ ] **Step 5: Commit the mobile mount bound.**

```text
git add client/lib/pages/chat/session_history_thread.dart client/test/pages/chat/session_history_thread_test.dart
git commit -m "perf: bound initial mobile session history mounts"
```

## Task 5: Full verification and device evidence

**Files:**

- No production files unless a test exposes a concrete regression.
- Review: all files changed by Tasks 1–4.

- [ ] **Step 1: Run analyzer using the repository command.**

```text
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no new errors attributable to this P0. Record any pre-existing
repository error separately rather than hiding it.

- [ ] **Step 2: Run the complete test suite through the wrapper.**

```text
cd client && dart run tool/run_tests.dart
```

Expected: no new failures attributable to this P0. The known pre-existing
failures must be compared against the baseline from before implementation.

- [ ] **Step 3: Build and reinstall the tested Android artifact.**

Use the project’s documented Android build command from `docs/DEVELOPMENT.md`,
then uninstall/reinstall the generated TeamPilot APK so the device is not
running an older pre-P0 artifact.

- [ ] **Step 4: Reproduce with the same session and capture phase evidence.**

Capture logs containing the same session id and verify:

- page decode mode is worker;
- full parse reports transferable mode;
- first publish occurs before full-index completion on a page hit;
- page miss returns a loading/cache result before full-index completion;
- mobile mounted-turn count stays bounded instead of growing to all 93 turns;
- no input-dispatch ANR occurs during a 10-second touch/scroll window.

- [ ] **Step 5: Review the final diff and commit only the P0 changes.**

```text
git diff --check
git status --short
git log --oneline -5
```

Preserve unrelated user changes and package submodule state. If verification
passes, request code review before claiming the ANR is fixed.
