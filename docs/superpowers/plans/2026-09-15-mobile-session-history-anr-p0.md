# Mobile Session History ANR P0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move large transcript full parsing and bundle-only enrichment off the Flutter UI isolate in every build mode, so a `page-first miss` cannot freeze Android input handling.

**Architecture:** Add a resident `HistoryParseWorker` with a typed request/response protocol and a built-in adapter dispatcher. `AiHistoryLoader` will send bundles at or above the existing 256 KB threshold to that worker, never falling back to synchronous UI parsing after a worker failure. Existing seat generation checks remain the final guard that prevents late results from reaching a changed session/member seat.

**Tech Stack:** Dart isolates and `SendPort`/`ReceivePort`, Flutter `kDebugMode`, `ai_message_core` transcript adapters, existing `ToolResultIndexCache`, `flutter_test`, and the repository test runner.

## Global Constraints

- Do not invoke `flutter test` directly; run tests through `cd client && dart run tool/run_tests.dart <paths/options>`.
- Before claiming completion, run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Large transcript parsing must not fall back to synchronous work on the UI isolate in Debug, Profile, or Release.
- Keep `session.json`, `sessions-index.json`, manifest scanning, SSH batching, and other P1/P2 work out of this plan.
- Preserve existing user changes in the dirty worktree; commit only files belonging to the current task.
- Use constructor injection for worker/test seams; do not use `Directory.current` for application or workspace data.
- Keep `AppLogger` for diagnostics and do not add `print` calls.
- Do not alter history message de-duplication, member placement, or CLI-specific behavior outside the history parser worker boundary.
- New integration tests must use `@Tags(['integration'])` from `package:test`.

## File Map

- Create `client/lib/services/session/history_parse_worker.dart`: public executor/result types, resident worker lifecycle, request/response protocol, timeout and disposal behavior.
- Create `client/lib/services/session/history_parse_worker_adapters.dart`: pure built-in adapter and bundle-only enricher dispatch used inside the worker isolate.
- Modify `client/lib/services/cli/registry/capabilities/history/tool_result_enricher.dart`: optional stable worker enricher identifier with a null default for filesystem-backed or unknown enrichers.
- Modify `client/lib/services/cli/claude/capabilities/history/compatible_tool_result_enricher.dart`: identify the Claude-compatible bundle-only enricher for worker execution.
- Modify `client/lib/services/session/ai_history_loader.dart`: inject the parse executor, select worker parsing by bundle size in every build mode, import worker indexes, record worker timings, and remove large-file synchronous fallback.
- Do not modify `client/lib/cubits/ai_history_seat.dart`: its existing generation and no-blank guards are the behavior under test.
- Create `client/test/services/session/history_parse_worker_adapters_test.dart`: dispatcher parity and unsupported-ID tests.
- Create `client/test/services/session/history_parse_worker_test.dart`: resident worker round-trip, timeout, stale/disposal, and respawn tests.
- Modify `client/test/services/session/ai_history_loader_test.dart`: loader worker selection, no synchronous fallback, bundle-only enrichment, and timing assertions.
- Modify `client/test/cubits/ai_history_seat_isolation_test.dart`: add a manually controlled large-bundle late-result regression test.

---

### Task 1: Define worker-safe parser dispatch and result protocol

**Files:**
- Create: `client/lib/services/session/history_parse_worker.dart`
- Create: `client/lib/services/session/history_parse_worker_adapters.dart`
- Modify: `client/lib/services/cli/registry/capabilities/history/tool_result_enricher.dart`
- Modify: `client/lib/services/cli/claude/capabilities/history/compatible_tool_result_enricher.dart`
- Test: `client/test/services/session/history_parse_worker_adapters_test.dart`

**Interfaces:**
- Produces `HistoryParseResult`, `HistoryParseExecutor`, and `HistoryParseWorker.parse` signatures for Tasks 2 and 3.
- `HistoryParseResult` contains `List<AiMessage> messages`, nullable `Object indexSnapshot`, `Duration parseTime`, and `Duration enrichTime`.
- `HistoryParseExecutor.parse` accepts `adapterId`, `AiTranscriptBundle bundle`, nullable `workerEnricherId`, nullable `sourceToken`, and nullable `rootTranscriptPath`.
- `ToolResultEnricher.workerId` defaults to `null`; the Claude-compatible bundle-only enricher returns `'claude-compatible'`.

- [ ] **Step 1: Write the failing dispatcher tests**

Add tests that use the existing Claude fixture and a minimal Codex JSONL bundle. The tests must prove that the worker dispatcher produces the same message IDs, roles, and visible text as the corresponding production adapters, and that an unknown adapter is rejected.

```dart
test('dispatches Claude bundle through the canonical adapter', () async {
  final result = await parseHistoryBundleInWorker(
    adapterId: 'claude',
    bundle: AiTranscriptBundle(
      adapterId: 'claude',
      fragments: [
        AiTranscriptFragment(
          name: 'session.jsonl',
          bytes: utf8.encode(
            '{"type":"user","message":{"id":"u1","content":"hi"}}\n'
            '{"type":"assistant","message":{"id":"a1","content":"hello"}}',
          ),
        ),
      ],
    ),
  );

  expect(result.messages.map((m) => m.id), ['u1', 'a1']);
  expect(result.messages.last.parts.single, isA<AiTextPart>());
});

test('unknown adapter IDs fail without a UI fallback', () async {
  await expectLater(
    () => parseHistoryBundleInWorker(
      adapterId: 'unknown-cli',
      bundle: const AiTranscriptBundle(
        adapterId: 'unknown-cli',
        fragments: [],
      ),
    ),
    throwsA(isA<UnsupportedError>()),
  );
});

test('Claude-compatible enricher exposes its stable worker ID', () {
  expect(ClaudeCompatibleToolResultEnricher().workerId, 'claude-compatible');
});
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
cd client && dart run tool/run_tests.dart test/services/session/history_parse_worker_adapters_test.dart
```

Expected: FAIL because the dispatcher entry point, result type, and `workerId` getter do not yet exist.

- [ ] **Step 3: Add the worker-facing types and optional enricher ID**

Define the stable protocol types in `history_parse_worker.dart` without capturing a `CliToolRegistry`, `Filesystem`, `SessionHistoryContext`, or runtime capability object in the worker request:

```dart
final class HistoryParseResult {
  const HistoryParseResult({
    required this.messages,
    this.indexSnapshot,
    this.parseTime = Duration.zero,
    this.enrichTime = Duration.zero,
  });

  final List<AiMessage> messages;
  final Object? indexSnapshot;
  final Duration parseTime;
  final Duration enrichTime;
}

abstract interface class HistoryParseExecutor {
  Future<HistoryParseResult> parse({
    required String adapterId,
    required AiTranscriptBundle bundle,
    String? workerEnricherId,
    String? sourceToken,
    String? rootTranscriptPath,
  });

  Future<void> dispose();
}
```

Add this defaulted getter to `ToolResultEnricher` so existing enrichers remain source-compatible:

```dart
/// Stable ID for a pure bundle-only enricher that can run in HistoryParseWorker.
/// Null means the enricher must remain on the caller isolate.
String? get workerId => null;
```

Override it in `ClaudeCompatibleToolResultEnricher` with `'claude-compatible'`. Do not add a filesystem-backed worker ID.

- [ ] **Step 4: Implement the pure built-in dispatcher**

In `history_parse_worker_adapters.dart`, add a top-level function that switches only on stable adapter IDs and constructs the same canonical adapters used by production:

```dart
Future<HistoryParseResult> parseHistoryBundleInWorker({
  required String adapterId,
  required AiTranscriptBundle bundle,
  String? workerEnricherId,
  String? sourceToken,
  String? rootTranscriptPath,
}) async {
  final adapter = switch (adapterId) {
    'claude' => const ClaudeAiTranscriptAdapter(),
    'codex' => const CodexAiTranscriptAdapter(),
    'cursor' => const CursorAiTranscriptAdapter(),
    'flashskyai' => const FlashskyaiAiTranscriptAdapter(),
    'opencode' => const OpencodeAiTranscriptAdapter(),
    _ => throw UnsupportedError('No history worker adapter for "$adapterId"'),
  };

  final parseSw = Stopwatch()..start();
  final messages = await adapter.parse(bundle);
  parseSw.stop();

  Object? indexSnapshot;
  var enrichTime = Duration.zero;
  if (workerEnricherId == 'claude-compatible') {
    final enrichSw = Stopwatch()..start();
    final enricher = ClaudeCompatibleToolResultEnricher();
    final enriched = await enricher.enrich(
      messages: messages,
      ctx: null,
      rootTranscriptPath: rootTranscriptPath,
      bundle: bundle,
      sourceToken: sourceToken,
    );
    enrichSw.stop();
    indexSnapshot = enricher.exportIndex();
    return HistoryParseResult(
      messages: enriched,
      indexSnapshot: indexSnapshot,
      parseTime: parseSw.elapsed,
      enrichTime: enrichSw.elapsed,
    );
  }

  return HistoryParseResult(
    messages: messages,
    parseTime: parseSw.elapsed,
    enrichTime: enrichTime,
  );
}
```

Use the exact adapter imports already used by the CLI registry. If a capability's enricher is filesystem-backed, leave `workerEnricherId` null and keep its existing caller-isolate enrichment after the worker parse.

- [ ] **Step 5: Run the focused tests and verify they pass**

Run:

```bash
cd client && dart run tool/run_tests.dart test/services/session/history_parse_worker_adapters_test.dart
```

Expected: PASS for canonical Claude/Codex dispatch, unknown adapter rejection, and the stable Claude-compatible enricher ID.

- [ ] **Step 6: Commit the protocol and dispatcher**

```bash
git add client/lib/services/session/history_parse_worker.dart \
  client/lib/services/session/history_parse_worker_adapters.dart \
  client/lib/services/cli/registry/capabilities/history/tool_result_enricher.dart \
  client/lib/services/cli/claude/capabilities/history/compatible_tool_result_enricher.dart \
  client/lib/services/cli/flashskyai/capabilities/history/ai_history_capability.dart \
  client/test/services/session/history_parse_worker_adapters_test.dart
git commit -m "feat: define history parse worker protocol"
```

### Task 2: Implement the resident worker lifecycle and timeout behavior

**Files:**
- Modify: `client/lib/services/session/history_parse_worker.dart`
- Test: `client/test/services/session/history_parse_worker_test.dart`

**Interfaces:**
- Consumes `parseHistoryBundleInWorker` from Task 1.
- Produces `HistoryParseWorker`, implementing `HistoryParseExecutor`, with static `instance`, `idleTimeout`, `readyTimeout`, `parse`, and `dispose`.
- `parse` must reject on worker startup/request timeout and must never call `parseHistoryBundleInWorker` on the caller isolate as a fallback.

- [ ] **Step 1: Write failing lifecycle tests**

Cover resident reuse, startup timeout, disposal, and respawn. Keep the timeout values short and expose test-only controls using `@visibleForTesting`, following `JsonlDecodeWorker` conventions.

```dart
test('reuses one resident worker for sequential parses', () async {
  final worker = HistoryParseWorker(
    idleTimeout: const Duration(seconds: 1),
    readyTimeout: const Duration(milliseconds: 200),
  );
  addTearDown(worker.dispose);

  final first = await worker.parse(
    adapterId: 'claude',
    bundle: claudeBundle('u1', 'a1'),
  );
  final second = await worker.parse(
    adapterId: 'claude',
    bundle: claudeBundle('u2', 'a2'),
  );

  expect(first.messages.last.id, 'a1');
  expect(second.messages.last.id, 'a2');
  expect(worker.debugSpawnCount, 1);
});

test('worker timeout fails without synchronous parsing', () async {
  final worker = HistoryParseWorker(
    readyTimeout: const Duration(milliseconds: 20),
  )..debugInstallZombieWorker();
  addTearDown(worker.dispose);

  await expectLater(
    worker.parse(adapterId: 'claude', bundle: claudeBundle('u1', 'a1')),
    throwsA(isA<TimeoutException>()),
  );
});

test('disposed worker can be created and used again', () async {
  final worker = HistoryParseWorker(
    readyTimeout: const Duration(milliseconds: 200),
  );
  await worker.parse(adapterId: 'claude', bundle: claudeBundle('u1', 'a1'));
  await worker.dispose();
  await expectLater(
    worker.parse(adapterId: 'claude', bundle: claudeBundle('u2', 'a2')),
    completion(isA<HistoryParseResult>()),
  );
  await worker.dispose();
});
```

The test file must define `claudeBundle` as a local fixture helper returning a valid `AiTranscriptBundle`; do not read repository files or use `Directory.current` in the worker unit test.

- [ ] **Step 2: Run the lifecycle tests and verify they fail**

Run:

```bash
cd client && dart run tool/run_tests.dart test/services/session/history_parse_worker_test.dart
```

Expected: FAIL because `HistoryParseWorker`, its resident protocol, and test controls do not yet exist.

- [ ] **Step 3: Implement the resident request/response protocol**

Mirror the proven structure in `jsonl_decode_worker.dart`, but use typed private messages carrying:

```dart
class _HistoryParseRequest {
  const _HistoryParseRequest({
    required this.requestId,
    required this.adapterId,
    required this.bundle,
    this.workerEnricherId,
    this.sourceToken,
    this.rootTranscriptPath,
  });

  final int requestId;
  final String adapterId;
  final AiTranscriptBundle bundle;
  final String? workerEnricherId;
  final String? sourceToken;
  final String? rootTranscriptPath;
}

class _HistoryParseResponse {
  const _HistoryParseResponse(this.requestId, this.result);

  final int requestId;
  final HistoryParseResult result;
}
```

The lifecycle must satisfy all of these rules:

- Spawn one isolate lazily and retain it until `idleTimeout` after the last response.
- Establish readiness through a `SendPort` control message.
- Track pending requests by request ID and complete only the matching completer.
- On `readyTimeout`, worker error, response-port closure, or disposal, fail all pending requests and discard the worker.
- On an isolate error, return the error to the caller; never run the parser synchronously on the caller isolate.
- After a failed worker is discarded, the next request may start a fresh worker.
- Keep `debugInstallZombieWorker`, `debugSpawnCount`, and timeout fields `@visibleForTesting`; production code must not depend on them.

- [ ] **Step 4: Add worker-level timing**

Measure parse and enrichment inside the worker with `Stopwatch`, returning durations through `HistoryParseResult`. Do not add a payload-size rejection in this task: the existing 256 KB threshold is the routing threshold, not a transfer limit. Do not log transcript content and do not introduce a synchronous fallback.

- [ ] **Step 5: Run the lifecycle tests and verify they pass**

Run:

```bash
cd client && dart run tool/run_tests.dart test/services/session/history_parse_worker_test.dart
```

Expected: PASS for resident reuse, timeout failure, disposal, and respawn.

- [ ] **Step 6: Commit the resident worker**

```bash
git add client/lib/services/session/history_parse_worker.dart \
  client/test/services/session/history_parse_worker_test.dart
git commit -m "feat: add resident history parse worker"
```

### Task 3: Route large loader parses through the worker in every build mode

**Files:**
- Modify: `client/lib/services/session/ai_history_loader.dart:1319-1450`
- Modify: `client/test/services/session/ai_history_loader_test.dart`

**Interfaces:**
- Consumes `HistoryParseExecutor` from Task 1 and the production `HistoryParseWorker` from Task 2.
- `AiHistoryLoader` gains an optional constructor parameter:

```dart
AiHistoryLoader({
  SessionHistoryContextBuilder contextBuilder =
      const SessionHistoryContextBuilder(),
  required AiHistoryWorkContextResolver resolveWorkContext,
  CliToolRegistry? registry,
  AiHistoryLocator? locator,
  SessionHistoryCacheTokenResolver? resolveCacheToken,
  List<CliPreset> Function()? globalPresets,
  AiHistoryLoadTimings? timings,
  HistoryParseExecutor? parseExecutor,
});
```

- The loader uses `parseExecutor ?? HistoryParseWorker.instance` for bundles at or above 256 KB.
- Small bundles retain the current direct adapter path.
- Large bundles never use `adapter.parse(bundle)` on the caller isolate after worker selection.

- [ ] **Step 1: Add a fake executor and write failing loader tests**

Add a constructor-injected fake executor in `ai_history_loader_test.dart` that records calls and returns a fixed `HistoryParseResult`. Extend the existing `buildLoader` helper with `HistoryParseExecutor? parseExecutor` and pass it to `AiHistoryLoader`:

```dart
AiHistoryLoader buildLoader({
  AiHistoryLocator? locator,
  CliToolRegistry? registry,
  AiHistoryWorkContextResolver? resolveWorkContext,
  bool useCapabilityToken = false,
  AiHistoryLoadTimings? timings,
  HistoryParseExecutor? parseExecutor,
}) {
  final resolvedRegistry = registry ?? CliToolRegistry.builtIn();
  return AiHistoryLoader(
    contextBuilder: const SessionHistoryContextBuilder(),
    resolveWorkContext:
        resolveWorkContext ?? ((_, {String? memberId}) async => fixedRoots()),
    registry: resolvedRegistry,
    locator: locator ?? AiHistoryLocator(registry: resolvedRegistry),
    resolveCacheToken: useCapabilityToken ? null : (_) async => mtimeToken,
    timings: timings,
    parseExecutor: parseExecutor,
  );
}
```

Add tests for large-bundle routing, worker timeout behavior, and bundle-only index import.

```dart
final class _RecordingHistoryParseExecutor
    implements HistoryParseExecutor {
  int calls = 0;
  String? lastAdapterId;
  String? lastWorkerEnricherId;
  Object? indexSnapshot;
  Object? error;

  @override
  Future<HistoryParseResult> parse({
    required String adapterId,
    required AiTranscriptBundle bundle,
    String? workerEnricherId,
    String? sourceToken,
    String? rootTranscriptPath,
  }) async {
    calls++;
    lastAdapterId = adapterId;
    lastWorkerEnricherId = workerEnricherId;
    final failure = error;
    if (failure != null) throw failure;
    return HistoryParseResult(
      messages: const [
        AiMessage(
          id: 'worker-message',
          role: AiRole.assistant,
          parts: [AiTextPart(text: 'worker result')],
        ),
      ],
      indexSnapshot: indexSnapshot,
      parseTime: const Duration(milliseconds: 12),
      enrichTime: const Duration(milliseconds: 8),
    );
  }

  @override
  Future<void> dispose() async {}
}
```

The large bundle test must use an adapter fake whose `parse` throws if called. The expected result must come from `_RecordingHistoryParseExecutor`, proving the loader cannot silently fall back to the caller isolate.

- [ ] **Step 2: Run the focused loader tests and verify they fail**

Run:

```bash
cd client && dart run tool/run_tests.dart test/services/session/ai_history_loader_test.dart --plain-name "large bundle"
```

Expected: FAIL because the loader has no injected executor and still calls the adapter directly in Debug mode.

- [ ] **Step 3: Inject the production executor and change the large-bundle branch**

Add `parseExecutor` to `AiHistoryLoader`, defaulting to `HistoryParseWorker.instance`. Replace the current condition that requires `!kDebugMode` with a size-based worker branch:

```dart
if (totalBytes >= _isolateParseMinBytes) {
  final result = await _parseExecutor.parse(
    adapterId: adapter.id,
    bundle: bundle,
    workerEnricherId: reuse ? null : enricher.workerId,
    sourceToken: sourceToken,
    rootTranscriptPath: parentPath,
  );
  indexCache?.importIndex(result.indexSnapshot);
  _recordTimedPhase(AiHistoryLoadPhase.parse, result.parseTime.inMicroseconds);
  if (result.enrichTime > Duration.zero) {
    _recordTimedPhase(
      AiHistoryLoadPhase.enrich,
      result.enrichTime.inMicroseconds,
    );
  }
  if (enricher.requiresFilesystem &&
      _needsToolResultEnrichment(result.messages, enricher)) {
    return _enrichMessages(
      enricher: enricher,
      messages: result.messages,
      ctx: ctx,
      parentPath: parentPath,
      bundle: bundle,
      sourceToken: sourceToken,
    );
  }
  return result.messages;
}
```

Keep the existing direct `adapter.parse` branch only below the threshold. Remove the `!kDebugMode` guard and remove the large-bundle `Isolate.run` implementation so there is one production path. If the executor throws, let the loader propagate the error to the existing seat error handling; do not catch it and synchronously parse the same bundle.

- [ ] **Step 4: Preserve cache and enrichment semantics**

When `reuse` is true, send no worker enricher ID and retain the caller's existing index. When `reuse` is false and `enricher.workerId == 'claude-compatible'`, import the worker's exported index before returning. Filesystem-backed enrichers remain on the caller isolate, but the worker must still supply parsed messages before they run. Do not change `_tokens`, `_messages`, `_fullIndexes`, or message identity rules beyond importing the worker result at the same point as the old parse result.

On worker failure, preserve the already-loaded result through the existing `AiHistorySeat` refresh path. Initial-load failure may remain an error state, but it must not block the UI isolate.

- [ ] **Step 5: Add phase diagnostics without transcript content**

Extend the existing Debug cold-load summary in `ai_history_seat.dart` to include bundle bytes and recorded `parse`/`enrich` durations. Keep the log format bounded:

```text
[ai-history-timing] worker parse cli=claude bytes=... parseMs=... enrichMs=...
```

Do not print message previews, transcript paths containing secrets, or full JSON payloads.

- [ ] **Step 6: Run loader tests and verify they pass**

Run:

```bash
cd client && dart run tool/run_tests.dart test/services/session/ai_history_loader_test.dart
```

Expected: PASS, including existing cache-token, incremental, page-first, and empty-result protection tests, plus the new large-bundle worker tests.

- [ ] **Step 7: Commit loader integration**

```bash
git add client/lib/services/session/ai_history_loader.dart \
  client/test/services/session/ai_history_loader_test.dart
git commit -m "fix: keep large history parsing off the UI isolate"
```

### Task 4: Verify stale-result protection and the P0 performance contract

**Files:**
- Modify: `client/test/cubits/ai_history_seat_isolation_test.dart`
- No changes to session repository or session index files

**Interfaces:**
- Consumes the worker-backed loader from Task 3.
- Produces regression tests proving that a late worker response cannot replace a changed seat and that a worker failure cannot blank an existing transcript.

- [ ] **Step 1: Write the late-result regression test**

Add `_QueuedHistoryParseExecutor` to `ai_history_seat_isolation_test.dart`:

```dart
final class _QueuedHistoryParseExecutor implements HistoryParseExecutor {
  final requests = <Completer<HistoryParseResult>>[];

  @override
  Future<HistoryParseResult> parse({
    required String adapterId,
    required AiTranscriptBundle bundle,
    String? workerEnricherId,
    String? sourceToken,
    String? rootTranscriptPath,
  }) {
    final request = Completer<HistoryParseResult>();
    requests.add(request);
    return request.future;
  }

  void complete(int index, String id) {
    requests[index].complete(
      HistoryParseResult(
        messages: [
          AiMessage(
            id: id,
            role: AiRole.assistant,
            parts: [AiTextPart(text: id)],
          ),
        ],
      ),
    );
  }

  @override
  Future<void> dispose() async {}
}
```

Change the isolation test setup to inject this executor and make `_ScriptedLocator` return a bundle whose single fragment contains `List<int>.filled(256 * 1024, 32)`. Add this test:

```dart
test('late worker result cannot replace a newer seat generation', () async {
  locator.emitBundle = true;
  final executor = _QueuedHistoryParseExecutor();
  loader = makeLoader(parseExecutor: executor);
  final seat = AiHistorySeat(loader: loader);
  addTearDown(seat.close);
  final sessionA = simpleSession(id: 'sess-a');
  final sessionB = simpleSession(id: 'sess-b');

  final loadA = seat.load(
    session: sessionA,
    memberId: '',
    launchContext: launchCtx(sessionA),
  );
  await pumpEventQueue();
  final loadB = seat.load(
    session: sessionB,
    memberId: '',
    launchContext: launchCtx(sessionB),
  );
  await pumpEventQueue();
  expect(executor.requests, hasLength(2));

  executor.complete(0, 'old-result');
  await pumpEventQueue();
  expect(seat.runtime.messages, isEmpty);

  executor.complete(1, 'new-result');
  await Future.wait([loadA, loadB]);
  expect(seat.state.sessionId, sessionB.sessionId);
  expect(seat.runtime.messages.single.id, 'new-result');
});
```

In `ai_history_seat_isolation_test.dart`, extract the existing `AiHistoryLoader` construction from `setUp` into `makeLoader({HistoryParseExecutor? parseExecutor})`, pass `parseExecutor` to the constructor, and assign `loader = makeLoader(parseExecutor: executor)` in the test. Add `dart:async` to the imports for `Completer`. The large bundle ensures both requests use the worker path; the first completion must be ignored after the second `seat.load` increments `_loadGeneration`.

- [ ] **Step 2: Run the focused regression tests and verify they fail**

Run:

```bash
cd client && dart run tool/run_tests.dart test/cubits/ai_history_seat_isolation_test.dart --plain-name "late worker result"
```

Expected: FAIL until the injected executor and seat-generation assertion are wired to the worker-backed loader.

- [ ] **Step 3: Verify the existing generation/error seam**

Verify that the existing `_loadGeneration`, `isClosed`, `sessionId`, and `memberId` checks in `AiHistorySeat` run immediately after awaiting the loader and before assigning `_cliMessages` or applying the worker result:

```dart
if (gen != _loadGeneration || isClosed) return;
```

Make no production change in this step. Do not add a second cache or a second seat-generation system. Preserve the existing no-blank guard for an empty full index.

- [ ] **Step 4: Run the complete focused P0 test set**

Run:

```bash
cd client && dart run tool/run_tests.dart \
  test/services/session/history_parse_worker_adapters_test.dart \
  test/services/session/history_parse_worker_test.dart \
  test/services/session/ai_history_loader_test.dart \
  test/cubits/ai_history_seat_isolation_test.dart \
  test/cubits/ai_history_seat_no_blank_test.dart \
  test/cubits/ai_history_seat_no_turn_end_force_reload_test.dart
```

Expected: PASS with no direct `flutter test` invocation and no test that depends on a real device.

- [ ] **Step 5: Run analyzer and inspect the diff**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
git diff --check
git status --short
```

Expected: analyzer exits successfully, diff check is clean, and only the intended P0 files are present in the task commits; pre-existing unrelated worktree changes remain untouched.

- [ ] **Step 6: Run the full suite once before claiming completion**

Run:

```bash
cd client && dart run tool/run_tests.dart
```

Expected: PASS for the repository's full test suite. If the suite fails, stop and investigate the specific failure before making any completion claim.

- [ ] **Step 7: Commit the regression coverage**

```bash
git add client/test/cubits/ai_history_seat_isolation_test.dart
git commit -m "test: cover mobile history worker ANR regressions"
```

## Handoff Notes

This plan intentionally leaves the second observed bottleneck (`readManifest` scanning 176 sessions in about 87 seconds) unchanged. It is outside P0 and must not be mixed into the worker commits. After P0 is verified, a separate P1 design/plan can address session indexing and remote metadata batching.
