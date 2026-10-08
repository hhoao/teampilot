# Incremental-Only AI History Loading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the adapter full-parse fallback from session AI-history loading so the incremental paths (JSONL tail-anchor, opencode SQLite row-level) are the *only* way to read a transcript; any warm decline throws a typed error so developers notice and fix gaps.

**Architecture:** `AiHistoryLoader._loadOnce` no longer contains `_parseAndEnrich` / `_scheduleFullIndex` / worker-executor machinery. Cold start seeds the incremental machinery itself: JSONL cold-starts the tail reader (`_fullReload`, uses `lineAppend`); opencode gets a new `seedCold` on its refresher that reads all rows once. Background full-index and `fullIndex` read the warm incremental state. Enrichers run inside the incremental finish path over changed messages.

**Tech Stack:** Dart, Flutter, `sqlite3`, existing `ai_message_core` package.

## Global Constraints

- Never invoke `flutter test` directly — always `cd client && dart run tool/run_tests.dart <paths>`.
- Inner loop: `flutter analyze --no-fatal-infos --no-fatal-warnings`; verify with one test file via `--plain-name`; full suite only in background at the end.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only.
- Logging: user errors → l10n; diagnostics → `AppLogger`; no `print`.
- No new dependencies.
- Named typed errors live in a new file `client/lib/services/session/history/ai_history_incremental_errors.dart`.
- Keep: mtime token cache, page-first first paint, empty-result/transient no-blank guards, subagent attachment lazy inflate, category annotation.

---

### Task 1: Typed Incremental Errors

**Files:**
- Create: `client/lib/services/session/history/ai_history_incremental_errors.dart`
- Test: `client/test/services/session/ai_history_incremental_errors_test.dart`

**Interfaces:**
- Produces: `class AiHistoryIncrementalUnavailableError implements Exception`, `class AiHistoryAnchorLostError implements Exception`. Both carry `final String message` and `@override String toString() => message`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/history/ai_history_incremental_errors.dart';

void main() {
  test('incremental unavailable error carries a message', () {
    const e = AiHistoryIncrementalUnavailableError('schema unsupported');
    expect(e.message, 'schema unsupported');
    expect(e.toString(), 'schema unsupported');
    expect(e, isA<Exception>());
  });

  test('anchor lost error carries a message', () {
    const e = AiHistoryAnchorLostError('anchor not found after rewrite');
    expect(e.message, 'anchor not found after rewrite');
    expect(e, isA<Exception>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/session/ai_history_incremental_errors_test.dart`
Expected: FAIL with "Target not found" / missing class.

- [ ] **Step 3: Write minimal implementation**

```dart
/// Raised when a warm incremental refresh cannot proceed and the adapter
/// full-parse fallback has been removed. Deliberately loud: surfaces parser
/// gaps instead of silently re-parsing.
final class AiHistoryIncrementalUnavailableError implements Exception {
  const AiHistoryIncrementalUnavailableError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Raised when the JSONL tail anchor cannot be located after warm (file was
/// rewritten/compacted in a way the incremental reader cannot follow).
final class AiHistoryAnchorLostError implements Exception {
  const AiHistoryAnchorLostError(this.message);

  final String message;

  @override
  String toString() => message;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/session/ai_history_incremental_errors_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/session/history/ai_history_incremental_errors.dart client/test/services/session/ai_history_incremental_errors_test.dart
git commit -m "feat(history): add typed incremental-unavailable errors"
```

---

### Task 2: Capability Interface — `seedFromFullParse` → `seedCold`

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/ai_history_capability.dart:57-74` (the `AiTranscriptIncrementalRefresher` interface)
- Modify: `client/test/support/fake_ai_history_registry.dart:65` (expose a settable refresher)
- Test: `client/test/services/session/ai_history_incremental_test.dart` (append a compile/behavior check)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `AiTranscriptIncrementalRefresher`:
    - `AiTranscriptIncrementalState createState();` (unchanged)
    - `Future<AiTranscriptIncrementalResult?> seedCold({required SessionHistoryContext ctx, required AiTranscriptIncrementalState state});` — **replaces** `seedFromFullParse`. Self-seeds by reading the store, returns the merged messages + parent path (same shape as `refresh`).
    - `Future<AiTranscriptIncrementalResult?> refresh({required SessionHistoryContext ctx, required AiTranscriptIncrementalState state, bool force = false});` (unchanged)
  - `FakeAiHistoryCapability` gains `AiTranscriptIncrementalRefresher? incrementalRefresher` (constructor param, default null).

- [ ] **Step 1: Write the failing test**

Append to `client/test/services/session/ai_history_incremental_test.dart`:

```dart
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';

class _TestState extends AiTranscriptIncrementalState {
  @override
  List<dynamic> get messages => _messages;
  final _messages = <dynamic>[];
}

test('refresher interface exposes seedCold instead of seedFromFullParse', () {
  // Compile-time contract: implementers MUST provide seedCold.
  final AiTranscriptIncrementalRefresher refresher = _FakeRefresher();
  expect(refresher, isA<AiTranscriptIncrementalRefresher>());
});

final class _FakeRefresher implements AiTranscriptIncrementalRefresher {
  @override
  AiTranscriptIncrementalState createState() => _TestState();

  @override
  Future<AiTranscriptIncrementalResult?> seedCold({
    required SessionHistoryContext ctx,
    required AiTranscriptIncrementalState state,
  }) async => null;

  @override
  Future<AiTranscriptIncrementalResult?> refresh({
    required SessionHistoryContext ctx,
    required AiTranscriptIncrementalState state,
    bool force = false,
  }) async => null;
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/session/ai_history_incremental_test.dart`
Expected: FAIL — `seedLocalCold` missing is not the point; rather `_FakeRefresher` fails "missing concrete implementation of seedFromFullParse" OR the interface still demands `seedFromFullParse` (fails to compile). If it compiles because `seedFromFullParse` has a default body, rename check: the existing `seedFromFullParse` must be gone.

- [ ] **Step 3: Rewrite the interface**

In `ai_history_capability.dart`, replace the `seedFromFullParse` member (lines ~60-66) with:

```dart
/// 冷启动 seed:增量机制自读存储,构建指纹与完整消息列表(不依赖 adapter
/// 全量 parse)。在首次加载 / invalidate 后由 loader 调用;完成后 [refresh]
/// 必须能纯增量跟进。实现不得从 loader 处接收 adapter 解析结果。
Future<AiTranscriptIncrementalResult?> seedCold({
  required SessionHistoryContext ctx,
  required AiTranscriptIncrementalState state,
});
```

Update the interface doc comment above the class: "刷新器自持锚点与实时列表；loader 在首次加载时调用 `seedCold` 建立基线（不再有 adapter 全量 parse 喂 `seedFromFullParse`），之后每次 load 只走 `refresh`。`refresh` 返回 null 表示无法增量 — loader 会抛出 `AiHistoryIncrementalUnavailableError`（严格模式），不再回退全量。"

- [ ] **Step 4: Update the fake registry**

`client/test/support/fake_ai_history_registry.dart:64-65`: change `incrementalRefresher => null` to a settable field:

```dart
@override
final AiTranscriptIncrementalRefresher? incrementalRefresher;
```

Add `this.incrementalRefresher,` to the constructor, and add the parameter to `fakeAiHistoryRegistry(...)` with default `AiTranscriptIncrementalRefresher? incrementalRefresher,` then pass `incrementalRefresher: incrementalRefresher`.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/session/ai_history_incremental_test.dart test/services/cli/registry/ai_history_capability_wiring_test.dart`
Expected: PASS (wiring test now compiles against the new interface).

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/ai_history_capability.dart client/test/support/fake_ai_history_registry.dart client/test/services/session/ai_history_incremental_test.dart
git commit -m "refactor(history): replace seedFromFullParse with seedCold on incremental refreshers"
```

---

### Task 3: opencode Refresher — `seedCold`, Deletion, Strict Throws

**Files:**
- Modify: `client/lib/services/cli/opencode/capabilities/history/ai_transcript.dart`
- Test: `client/test/services/cli/registry/capabilities/history/opencode_ai_transcript_test.dart`

**Interfaces:**
- Consumes: `AiHistoryIncrementalUnavailableError` (Task 1), `seedCold` interface (Task 2).
- Produces:
  - `OpencodeHistoryIncrementalRefresher.seedCold({required SessionHistoryContext ctx, required AiTranscriptIncrementalState state}) → Future<AiTranscriptIncrementalResult?>` — resolves+fixes the seat session id, reads ALL session fingerprints and message bundles once, merges into `state.messages` in `(createdMs, id)` order, fills `_seen`, returns `(messages, parentPath)`.
  - `refresh` behavior change: deletion is now *expressed* (vanished ids removed from `_messages` and `_seen`), no longer returns null. Count fallback / schema mismatch (`_readFingerprints` null while DB exists, or `_unsupported`) → throws `AiHistoryIncrementalUnavailableError`. `_seen.isEmpty` after a completed seed → throws (flag a seed skip bug).
  - `_mergeInPlace` gains deletion support: new top-level helper `_removeMessagesByIds(List<AiMessage> target, Set<String> ids)` that removes rows by id (used in refresh), plus a `coalesceAdjacentAssistantsInPlace(target)` call after removal.

- [ ] **Step 1: Write the failing tests**

Append to `opencode_ai_transcript_test.dart`:

```dart
test('seedCold builds messages and fingerprints without an adapter parse',
    () async {
  // Real SQLite DB with 2 messages (user+assistant), same layout helpers used
  // by existing tests in this file (see existing `_openDb` / insert helpers).
  final state = OpencodeHistoryIncrementalState();
  final refresher = const OpencodeHistoryIncrementalRefresher();
  final result = await refresher.seedCold(ctx: ctx, state: state);
  expect(result, isNotNull);
  expect(result!.messages, hasLength(2));
  expect(state.sessionId, 'ses_1');
  expect(state.messages, same(result.messages));
  // A following refresh with no changes is a no-op (fingerprints match).
  final delta = await refresher.refresh(ctx: ctx, state: state);
  expect(delta, isNotNull);
  expect(delta!.messages, hasLength(2));
});

test('refresh expresses message deletion instead of falling back', () async {
  final state = OpencodeHistoryIncrementalState();
  final refresher = const OpencodeHistoryIncrementalRefresher();
  await refresher.seedCold(ctx: ctx, state: state);
  // Delete assistant message + its part from the DB.
  deleteMessageAndParts(id: 2);
  final delta = await refresher.refresh(ctx: ctx, state: state);
  expect(delta, isNotNull, reason: 'deletion must be expressed, not declined');
  expect(delta!.messages.map((m) => m.id), ['1']);
  expect(state.messages, hasLength(1));
});

test('refresh throws on count fallback / schema mismatch', () async {
  final state = OpencodeHistoryIncrementalState();
  final refresher = const OpencodeHistoryIncrementalRefresher();
  await refresher.seedCold(ctx: ctx, state: state);
  dropTimeUpdatedColumns(); // legacy schema
  await expectLater(
    refresher.refresh(ctx: ctx, state: state),
    throwsA(isA<AiHistoryIncrementalUnavailableError>()),
  );
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/capabilities/history/opencode_ai_transcript_test.dart --plain-name "seedCold"`
Expected: FAIL — `seedCold` not defined / `seedFromFullParse` legacy behavior.

- [ ] **Step 3: Implement `seedCold` on `OpencodeHistoryIncrementalRefresher`**

Replace the existing `seedFromFullParse` override (lines ~70-108) with:

```dart
@override
Future<AiTranscriptIncrementalResult?> seedCold({
  required SessionHistoryContext ctx,
  required AiTranscriptIncrementalState state,
}) async {
  if (state is! OpencodeHistoryIncrementalState) return null;
  final s = state;
  s._adopt(const []);
  s._seen.clear();
  final dataDir = opencodeDataDirFromEnv(ctx);
  final sessionId =
      dataDir.isEmpty ? null : await _resolveSessionId(ctx, dataDir);
  s.sessionId = sessionId;
  if (sessionId == null) {
    // 尚无会话(新建/未绑定):合法空态,不是错误。
    s._unsupported = false;
    return (messages: s._messages, parentPath: _dbPath(ctx));
  }
  final rows = await _readFingerprints(ctx, sessionId);
  if (rows == null) {
    // DB 存在但指纹查询失败(schema 不兼容)→ 严格模式抛错,不再全量回退。
    final dbPath = _dbPath(ctx);
    var exists = false;
    if (dbPath != null) {
      final st = await ctx.fs.stat(dbPath);
      exists = st.exists;
    }
    if (exists) {
      s._unsupported = true;
      throw AiHistoryIncrementalUnavailableError(
        'opencode sqlite schema unsupported (fingerprint query failed)',
      );
    }
    return (messages: const [], parentPath: dbPath);
  }
  s._unsupported = false;
  final messageIds = rows.map((r) => r.messageId).toList();
  if (messageIds.isEmpty) {
    return (messages: const [], parentPath: _dbPath(ctx));
  }
  final bundles = await _loadMessageBundles(ctx, sessionId, messageIds);
  if (bundles == null) {
    s._unsupported = true;
    throw AiHistoryIncrementalUnavailableError(
      'opencode message bundles unreadable during seedCold',
    );
  }
  final parsed = <AiMessage>[];
  final adapter = const OpencodeAiTranscriptAdapter();
  for (final bundle in bundles) {
    parsed.addAll(await adapter.parse(bundle));
  }
  _mergeInPlace(s._messages, parsed);
  for (final row in rows) {
    s._seen[row.messageId] = _MessageFingerprint(
      row.partCount,
      row.maxPartUpdated,
      row.updated,
    );
  }
  return (messages: s._messages, parentPath: _dbPath(ctx));
}
```

- [ ] **Step 4: Rework `refresh` for deletion + strict throws**

Replace the body of `refresh` (lines ~111-160) so that:

```dart
@override
Future<AiTranscriptIncrementalResult?> refresh({
  required SessionHistoryContext ctx,
  required AiTranscriptIncrementalState state,
  bool force = false,
}) async {
  if (force) {
    throw AiHistoryIncrementalUnavailableError(
      'opencode incremental refresh cannot be forced; seedCold again instead',
    );
  }
  if (state is! OpencodeHistoryIncrementalState) return null;
  final s = state;
  if (s._unsupported) {
    throw AiHistoryIncrementalUnavailableError(
      'opencode sqlite schema unsupported (markUnsupported)',
    );
  }
  if (s._seen.isEmpty) {
    // seedCold 从未来到过(loader 跳过 seed 直接刷新)→ 状态机错误。
    throw AiHistoryIncrementalUnavailableError(
      'opencode incremental state was never seedCold-aligned',
    );
  }
  final sessionId = s.sessionId;
  if (sessionId == null) {
    throw AiHistoryIncrementalUnavailableError(
      'opencode incremental state has no pinned sessionId',
    );
  }
  final rows = await _readFingerprints(ctx, sessionId);
  if (rows == null) {
    throw AiHistoryIncrementalUnavailableError(
      'opencode fingerprint query failed during refresh',
    );
  }
  final rowIds = rows.map((r) => r.messageId).toSet();
  final vanished = s._seen.keys.where((id) => !rowIds.contains(id)).toList();
  if (vanished.isNotEmpty) {
    // 删除/压缩 → 增量表达:移除消失消息并清理指纹。
    _removeMessagesByIds(s._messages, vanished.toSet());
    for (final id in vanished) {
      s._seen.remove(id);
    }
  }
  final changed = <String>[];
  for (final row in rows) {
    final seen = s._seen[row.messageId];
    final fp = _MessageFingerprint(
      row.partCount,
      row.maxPartUpdated,
      row.updated,
    );
    if (seen == null || seen != fp) {
      changed.add(row.messageId);
      s._seen[row.messageId] = fp;
    }
  }

  // 新增消息(此前 unseen)→ 直接按行插入。
  final missingRows =
      rows.where((r) => !s._seen.containsKey(r.messageId)).toList();
  changed.addAll(missingRows.map((r) => r.messageId));

  if (changed.isEmpty) {
    return (messages: s._messages, parentPath: _dbPath(ctx));
  }

  final bundles = await _loadMessageBundles(ctx, sessionId, changed);
  if (bundles == null) {
    throw AiHistoryIncrementalUnavailableError(
      'opencode message bundles unreadable during refresh',
    );
  }
  final parsed = <AiMessage>[];
  final adapter = const OpencodeAiTranscriptAdapter();
  for (final bundle in bundles) {
    parsed.addAll(await adapter.parse(bundle));
  }
  // 修正:loadMessageBundles 只回读 session+id 行;先移除 vanished 已处理。
  _mergeInPlace(s._messages, parsed);
  return (messages: s._messages, parentPath: _dbPath(ctx));
}
```

**Note on `changed` computation:** `_seen` was already updated for each row in the loop above, so `missingRows` (row ids never seen) must be gathered *before* the loop writes `_seen`, or computed as `rowIds.difference(originalSeenKeys)`. Implement exactly this:

```dart
final originalSeenKeys = s._seen.keys.toSet();
// ...after deletion prune recompute:
final changed = <String>[];
for (final row in rows) {
  if (!originalSeenKeys.contains(row.messageId) || s._seen[row.messageId] != fp(row)) {
    changed.add(row.messageId);
  }
  s._seen[row.messageId] = fp(row);
}
```

- [ ] **Step 5: Add deletion helper**

Add at module scope (near `_mergeInPlace`):

```dart
void _removeMessagesByIds(List<AiMessage> target, Set<String> ids) {
  if (ids.isEmpty) return;
  target.removeWhere((m) => ids.contains(m.id));
  coalesceAdjacentAssistantsInPlace(target);
}
```

- [ ] **Step 6: Run the full opencode transcript + refresher suite to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/capabilities/history/opencode_ai_transcript_test.dart`
Expected: PASS (seedCold/refresh/deletion/throw tests green; legacy schema test may need its *expectation* flipped to throw — update the legacy schema test: `await expectLater(refresher.refresh(...), throwsA(isA<AiHistoryIncrementalUnavailableError>()))`).

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/cli/opencode/capabilities/history/ai_transcript.dart client/test/services/cli/registry/capabilities/history/opencode_ai_transcript_test.dart
git commit -m "refactor(history): opencode refresher seeds cold, expresses deletion, throws on schema"
```

---

### Task 4: Tail Reader Strict Mode

**Files:**
- Modify: `client/lib/services/session/history/ai_transcript_tail_reader.dart`
- Test: `client/test/services/session/ai_transcript_tail_reader_test.dart`

**Interfaces:**
- Consumes: `AiHistoryAnchorLostError` (Task 1).
- Produces: unchanged public API (`refresh`, `TailReaderState`, `TailRefreshResult`), but `refresh` now throws `AiHistoryAnchorLostError` when a **warm** refresh cannot find the anchor:
  - head fingerprint changed (prefix rewritten in place) → throw
  - whole-file anchor scan finds nothing (rewrite/compact/truncate) → throw
  - file shrunk below the head fingerprint length while warm → throw
  - **Cold** (`state.anchorHash == null`, first-ever or path-changed) still uses `_fullReload` — unchanged.

- [ ] **Step 1: Write/update the failing tests**

In `ai_transcript_tail_reader_test.dart`, change these tests to expect throws:

```dart
test('warm anchor missing after rewrite throws AnchorLost', () async {
  await fs.writeString(path, '${userLine('u1', 'hi')}\n');
  final reader = _reader();
  final state = TailReaderState();
  await reader.refresh(fs: fs, path: path, state: state); // cold seed

  await fs.writeString(path, '${userLine('u2', 'rewritten')}\n');
  await expectLater(
    reader.refresh(fs: fs, path: path, state: state),
    throwsA(isA<AiHistoryAnchorLostError>()),
  );
});

test('warm prefix rewrite with surviving tail anchor throws AnchorLost', () async {
  await fs.writeString(path, '${userLine('u1', 'hi')}\n${assistantLine('a1', 'ok')}\n');
  final reader = _reader();
  final state = TailReaderState();
  await reader.refresh(fs: fs, path: path, state: state);

  await fs.writeString(path, '${userLine('u1', 'edited')}\n${assistantLine('a1', 'ok')}\n');
  await expectLater(
    reader.refresh(fs: fs, path: path, state: state),
    throwsA(isA<AiHistoryAnchorLostError>()),
  );
});

test('warm file shrink triggers AnchorLost instead of silent rebuild', () async {
  await fs.writeString(path, '${userLine('u1', 'hi')}\n');
  final reader = _reader();
  final state = TailReaderState();
  await reader.refresh(fs: fs, path: path, state: state);

  await fs.writeString(path, '${userLine('u2', 'small')}\n');
  await expectLater(
    reader.refresh(fs: fs, path: path, state: state),
    throwsA(isA<AiHistoryAnchorLostError>()),
  );
});

test('cold start (first load) still does a full reload through lineAppend', () async {
  // Unchanged existing cold-seed test: 'full reload decodes all lines in one batch'.
});
```

- [ ] **Step 2: Implement the strict throws**

In `refresh` (ai_transcript_tail_reader.dart:54-118):
- Keep the cold branch (`if (state.anchorHash == null) return _fullReload(...)`).
- `pathChanged` still resets to cold (keep).
- Replace the head-fingerprint mismatch branch (lines ~89-92) to throw:

```dart
if (size < state.headFingerprintLength ||
    (state.headFingerprint != null && head != state.headFingerprint)) {
  throw AiHistoryAnchorLostError(
    'JSONL transcript head changed while tail anchor was warm '
    '(rewrite/compaction); incremental cannot follow',
  );
}
```

- In the whole-file fallback (line ~117), replace `return _fullReload(fs, path, size, state);` with:

```dart
throw AiHistoryAnchorLostError(
  'JSONL tail anchor not found anywhere in transcript '
  '(rewrite/compaction/truncation); incremental cannot follow',
);
```

Delete the now-unreachable comment about full reload. `_fullReload` stays only for the cold branch.

- [ ] **Step 3: Run the tail reader suite**

Run: `cd client && dart run tool/run_tests.dart test/services/session/ai_transcript_tail_reader_test.dart`
Expected: PASS (cold-seed tests unchanged; warm-loss tests now throw).

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/session/history/ai_transcript_tail_reader.dart client/test/services/session/ai_transcript_tail_reader_test.dart
git commit -m "feat(history): tail reader throws AnchorLost on warm anchor loss"
```

---

### Task 5: Loader — Remove Adapter Full Parse, Incremental-Only

**Files:**
- Modify: `client/lib/services/session/history/ai_history_loader.dart`
- Test: `client/test/services/session/ai_history_loader_test.dart`
- Related: `client/test/services/session/history_parse_worker_test.dart` (deleted in a later task; see Task 8)

**Interfaces:**
- Consumes: `AiHistoryIncrementalUnavailableError`, `AiHistoryAnchorLostError` (Task 1); `seedCold` (Task 2).
- Produces (loader API surface unchanged):
  - `Future<AiHistoryLoadResult> load({...})` — unchanged signature. `force: true` skips the token cache but still only drives incremental cold/refresh (never adapter parse).
  - `Future<AiHistoryLoadResult?> fullIndex({required String sessionId, required String memberId})` — unchanged signature; now resolves from warm incremental state (tail / opencode refresh) instead of a background adapter parse. Returns null when the seat has no warm state.
  - `_loadOnce` internals: the adapter-parse branch (`_parseAndEnrich`, worker-parse `_parseExecutor`, `_scheduleFullIndex`) is **deleted**.

- [ ] **Step 1: Write the failing regression tests**

Add to `ai_history_loader_test.dart`:

```dart
test('warm opencode count-fallback throws instead of full-parse fallback',
    () async {
  // Build a loader with an opencode registry whose refresher declines on
  // second refresh. The seedCold path succeeds; refresh throws.
  // Expected: loader.load(...) throws AiHistoryIncrementalUnavailableError.
});

test('seats that cannot incrementally seed throw on cold load', () async {
  // A capability with no lineAppend / no pageReader / no incrementalRefresher.
  // Expected: loader.load(...) throws AiHistoryIncrementalUnavailableError.
});
```

Concretely (usable fixtures already exist in the test file — `_NullPageReader`, `fakeAiHistoryRegistry`):

```dart
test('cold load with no incremental source throws unavailable', () async {
  final session = simpleSession();
  final loader = buildLoader(
    registry: fakeAiHistoryRegistry(
      cli: CliTool.claude,
      adapter: _EchoAdapter(),
      locate: (_) async => AiTranscriptBundle(
        adapterId: 'claude',
        fragments: const [AiTranscriptFragment(name: 't.jsonl', bytes: [1])],
      ),
      pageReader: _NullPageReader(),
    ),
  );
  await expectLater(
    () => loader.load(
      session: session,
      memberId: '',
      launchContext: launchContextFor(session),
    ),
    throwsA(isA<AiHistoryIncrementalUnavailableError>()),
  );
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/session/ai_history_loader_test.dart --plain-name "throws unavailable"`
Expected: FAIL — loader currently silently returns empty / uses adapter.

- [ ] **Step 3: Restructure `_loadOnce` to be incremental-only**

Changes to `ai_history_loader.dart`:

a) Remove imports/fields for the worker executor — delete `import 'history_parse_worker.dart';` (line 27), the `HistoryParseExecutor? parseExecutor` ctor param + `_parseExecutor` field, and `_isolateParseMinBytes`.

b) Delete `_parseAndEnrich` (lines 1488-1648) and `_enrichMessages` caller (keep `_enrichMessages` itself, it's reused by the enricher task), and delete `_scheduleFullIndex` (lines 1090-1131).

c) Rewrite the adapter-parse block at lines 808-991. The new flow (preserving page-first and token cache):

```dart
// ---- incremental-only turning point ----
// JSONL 尾锚增量(tail)/ 数据库行级增量(DB)是唯一的数据来源。
final refresher = cap.incrementalRefresher;

// 1) DB 行级增量(opencode):未 seed → 先 seedCold。
if (refresher != null) {
  var incrementalState = _incrementalStates[cacheKey];
  if (incrementalState == null) {
    incrementalState = refresher.createState();
    final seeded = await refresher.seedCold(ctx: ctx, state: incrementalState);
    if (_isStaleGeneration(cacheKey, expectedGeneration)) {
      return _incompleteResult(cacheKey: cacheKey, cli: cli);
    }
    _incrementalStates[cacheKey] = incrementalState;
    if (seeded != null) {
      _parentPaths[cacheKey] = seeded.parentPath ?? '';
      return await _finishIncremental(
        cacheKey: cacheKey,
        cli: cli,
        ctx: ctx,
        messages: incrementalState.messages,
        parentPath: seeded.parentPath,
        token: token,
        indexOnly: skipPaging,
        expectedGeneration: expectedGeneration,
      );
    }
    // seedCold 返回 null(空态)→ 空结果保护继续。
    return _result(
      cacheKey: cacheKey,
      messages: const [],
      cli: cli,
      subagentAttachments: const {},
    );
  }
  final dbDelta = await refresher.refresh(ctx: ctx, state: incrementalState);
  if (dbDelta == null) {
    throw AiHistoryIncrementalUnavailableError(
      'incremental refresh declined after warm; adapter full-parse removed: '
      'cli=${cli.name} session=${session.sessionId}',
    );
  }
  if (_parentPaths[cacheKey] == null || _parentPaths[cacheKey]!.isEmpty) {
    _parentPaths[cacheKey] = dbDelta.parentPath ?? '';
  }
  return await _finishIncremental(
    cacheKey: cacheKey,
    cli: cli,
    ctx: ctx,
    messages: dbDelta.messages,
    parentPath: dbDelta.parentPath,
    token: token,
    indexOnly: skipPaging,
    expectedGeneration: expectedGeneration,
  );
}

// 2) JSONL 尾锚增量:冷启动或温刷新。
final tailParentPath = _parentPaths[cacheKey];
if (tailParentPath == null || tailParentPath.isEmpty) {
  throw AiHistoryIncrementalUnavailableError(
    'no parent transcript path to drive the incremental tail reader: '
    'cli=${cli.name} session=${session.sessionId}',
  );
}
final tail = await _tryIncrementalLoad(
  cacheKey: cacheKey,
  cli: cli,
  ctx: ctx,
  parentPath: tailParentPath,
);
return await _finishIncremental(
  cacheKey: cacheKey,
  cli: cli,
  ctx: ctx,
  messages: tail,
  parentPath: tailParentPath,
  token: token,
  indexOnly: skipPaging,
  expectedGeneration: expectedGeneration,
);
```

d) Keep the `page-first` block (lines 715-752) entirely unchanged — it returns the recent page and calls `_scheduleFullIndex`. Since `_scheduleFullIndex` is deleted, change the two call sites to a new `_scheduleWarmSeed(…)` method (Step 6) so page-first still warms the tail/DB seed in the background without an adapter parse.

e) Keep the empty-result/transient guard block (messages empty + prior-content → keep prior) — it sits before `_finishIncremental` returns. Apply it around the seeded/tail results: after computing `messages` from `_finishIncremental` is not needed since seedCold/refresh already return non-empty; seedCold empty result is handled by the `_result(const [])` branch. Retain the existing guard logic that protected a loaded transcript from a transient empty locate — re-home it to wrap the seed path:

```dart
// 空结果保护(locate/seed 瞬时失败)绝不覆盖已加载内容。
final priorFull = _fullIndexes[cacheKey];
final priorMessages = _messages[cacheKey] ?? const <AiMessage>[];
if (messages.isEmpty && (priorFull?.messages.isNotEmpty ?? false || priorMessages.isNotEmpty)) {
  return _result(cacheKey: cacheKey, messages: priorMessages, cli: cli,
    subagentAttachments: priorFull?.subagentAttachments.isNotEmpty == true
        ? priorFull!.subagentAttachments : (_attachments[cacheKey] ?? const {}));
}
```

f) `fullIndex` (line 1037): re-implement to read warm state:

```dart
Future<AiHistoryLoadResult?> fullIndex({
  required String sessionId,
  required String memberId,
}) async {
  final complete = _fullIndexes[cacheKey];
  if (complete != null) return complete;
  final tail = _tailStates[cacheKey];
  if (tail != null && tail.messages.isNotEmpty) {
    return _result(cacheKey: cacheKey, messages: tail.messages, cli: _pageClis[cacheKey] ?? CliTool.claude, subagentAttachments: _attachments[cacheKey] ?? const {});
  }
  final incr = _incrementalStates[cacheKey];
  if (incr != null && incr.messages.isNotEmpty) {
    return _result(cacheKey: cacheKey, messages: incr.messages, cli: _pageClis[cacheKey] ?? CliTool.claude, subagentAttachments: _attachments[cacheKey] ?? const {});
  }
  return null;
}
```

(The `cacheKey` variable must be defined inside the method — same `_cacheKey(sessionId, memberId)` helper used by `messagesIfCached`.)

g) `messagesIfCached` (line 346) keeps returning `_fullIndexes[key]?.messages` but after warm-seed that map is populated by `_scheduleWarmSeed`/`_finishIncremental` (already stores `_fullIndexes[cacheKey] = complete`).

- [ ] **Step 4: Remove `_tryIncrementalRefresh` decline→null; make it throw**

`_tryIncrementalRefresh` (lines 392-405) currently returns null when `refresher == null` or state null. Under strict:

```dart
Future<AiTranscriptIncrementalResult?> _tryIncrementalRefresh({
  required String cacheKey,
  required CliTool cli,
  required SessionHistoryContext ctx,
}) async {
  final cap = _registry.capability<AiHistoryCapability>(cli);
  final refresher = cap?.incrementalRefresher;
  if (refresher == null) return null; // JSONL CLI → tail path
  final state = _incrementalStates[cacheKey];
  if (state == null) return null; // not seeded yet → caller seeds
  final result = await refresher.refresh(ctx: ctx, state: state, force: false);
  if (result == null) {
    throw AiHistoryIncrementalUnavailableError(
      'incremental refresh declined for cli=${cli.name} cacheKey=$cacheKey',
    );
  }
  return result;
}
```

This method is then called from the refactored `_loadOnce` (it already is, at line 757) — it throws on decline instead of returning null.

- [ ] **Step 5: Run the incremental-only loader tests**

Run: `cd client && dart run tool/run_tests.dart test/services/session/ai_history_loader_test.dart --plain-name "throws unavailable"`
Expected: PASS. Then run the **full** loader test file and fix the tests that asserted the old adapter/fallback behavior (they now throw instead). Use this mapping:
- Tests named `large bundle…`, `background full bootstrap…`, `worker executor`, `index snapshot`, `reusable bundle-only cache` → **delete** (worker/adapter machinery is gone).
- Tests that used `parseExecutor:` / `_largeBundle` / `_ThrowingParseAdapter` → convert to page-first + tail/DB fixtures or delete.
- `transient empty full parse never overwrites…` → keep (no-blank guard).
- `missing transcript returns empty` → keep; `locate` returns null so token miss → `_tryPageFirst` returns null → page-first `_scheduleWarmSeed` (background) then return previous (empty). Full-suite run will surface the crux assertions — fix each to the new contract (empty instead of parsed, or throw).

- [ ] **Step 6: Add `_scheduleWarmSeed` (replaces `_scheduleFullIndex`)**

```dart
/// 后台预热增量 seed:page-first 空格命中后,把尾锚/DB 增量 seed 起来,
/// 让下一次 load 走纯增量。不做任何 adapter 全量 parse。
Future<AiHistoryLoadResult> _scheduleWarmSeed({
  required AppSession session,
  required CliTool cli,
  required String effectiveMemberId,
  required SessionHistoryContext ctx,
  required String cacheKey,
}) {
  final existing = _fullIndexFutures[cacheKey];
  if (existing != null && _fullIndexes[cacheKey] == null) return existing;
  final generation = _cacheGeneration(cacheKey);
  late final Future<AiHistoryLoadResult> future;
  future = _loadOnce(
    session: session,
    cli: cli,
    effectiveMemberId: effectiveMemberId,
    ctx: ctx,
    cacheKey: cacheKey,
    force: false,
    skipPaging: false,
    expectedGeneration: generation,
  ).then((result) {
    if (_isStaleGeneration(cacheKey, generation)) {
      return _incompleteResult(cacheKey: cacheKey, cli: cli);
    }
    return result;
  });
  _fullIndexFutures[cacheKey] = future;
  future.then<void>((_) {}, onError: (Object _, StackTrace __) {
    if (identical(_fullIndexFutures[cacheKey], future)) {
      _fullIndexFutures.remove(cacheKey);
    }
  }).ignore();
  return future;
}
```

Replace both `_scheduleFullIndex(...)` calls (lines 731, 1252) with `_scheduleWarmSeed(...)`.

- [ ] **Step 7: Run the loader suite + seat/hydration tests, fix contract drift**

Run: `cd client && dart run tool/run_tests.dart test/services/session/ai_history_loader_test.dart test/cubits/ai_history_cubit_test.dart`
Fix failures by removing adapter-era assertions. Key rewrite: any assertion that `fullIndex` returns a fully-parsed older window now resolves from the warm tail/DB state after `_scheduleWarmSeed` completes — wait for `debugAwaitTailWarm` or the warm future (`await loader.fullIndex(...)`) before asserting content.

- [ ] **Step 8: Commit**

```bash
git add client/lib/services/session/history/ai_history_loader.dart client/test/services/session/ai_history_loader_test.dart client/test/cubits/ai_history_cubit_test.dart
git commit -m "refactor(history): incremental-only loader, no adapter full parse"
```

---

### Task 6: Enricher in Incremental Finish Path

**Files:**
- Modify: `client/lib/services/session/history/ai_history_loader.dart` (`_finishIncremental`)
- Modify: `client/lib/services/cli/opencode/capabilities/history/tool_output_backfill_enricher.dart` (doc update only)
- Test: `client/test/services/cli/registry/capabilities/history/opencode_tool_output_backfill_enricher_test.dart`

**Interfaces:**
- Consumes: `_enrichMessages`, `_needsToolResultEnrichment` (already present in loader).
- Produces: `_finishIncremental` now applies the capability's `toolResultEnricher` over newly added/changed messages before returning.

- [ ] **Step 1: Write the failing test**

```dart
test('truncated part appended during incremental refresh is backfilled',
    () async {
  // DB containing a message with a truncated tool part + hint file on disk.
  // First load + seed; then append a NEW message with `...N bytes truncated...`
  // part + hint path; refresh; expect the part.result to be the file body.
  final result = await loader.load(...);            // after refresh
  final part = result.messages.last.parts.single as AiToolCallPart;
  expect(part.result, 'full webfetch output\n第二行');
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/capabilities/history/opencode_tool_output_backfill_enricher_test.dart`
Expected: FAIL — placeholder still shows (enricher only ran on removed full parse).

- [ ] **Step 3: Apply the enricher in `_finishIncremental`**

Modify `_finishIncremental` (around line 467, after `annotateChangedSuffix` produces `annotated`):

```dart
final capability = _registry.capability<AiHistoryCapability>(cli);
final enricher = capability?.toolResultEnricher;
var finalized = annotated;
if (enricher != null && _needsToolResultEnrichment(finalized, enricher)) {
  finalized = await _enrichMessages(
    enricher: enricher,
    messages: finalized,
    ctx: ctx,
    parentPath: parentPath,
    bundle: null,
    sourceToken: token ?? _tokens[cacheKey],
  );
}
```

Then use `finalized` everywhere `annotated` was used below (signature collection + `_subagentAttachmentsFor` + the final result list): `final result = List<AiMessage>.of(finalized);`

The enricher runs idempotently over the merged list; `_enrichMessages` already guards fs-backed enrichers (ctx is non-null on caller isolate).

- [ ] **Step 4: Run to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/capabilities/history/opencode_tool_output_backfill_enricher_test.dart test/services/session/ai_history_loader_test.dart --plain-name "truncation marker"`
Expected: PASS (both new incremental-refresh backfill test and existing marker-gate loader tests).

- [ ] **Step 5: Update the enricher's doc comment**

In `tool_output_backfill_enricher.dart` lines 33-36, replace "until the next full parse" with "on the next incremental refresh of the changed messages".

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/session/history/ai_history_loader.dart client/lib/services/cli/opencode/capabilities/history/tool_output_backfill_enricher.dart client/test/services/cli/registry/capabilities/history/opencode_tool_output_backfill_enricher_test.dart
git commit -m "feat(history): run tool-result enricher on incremental refresh"
```

---

### Task 7: Seat Error Surfacing

**Files:**
- Modify: `client/lib/cubits/ai_history_seat.dart`
- Modify: `client/lib/pages/chat/session_history_review_messages.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/cubits/ai_history_seat_isolation_test.dart`

**Interfaces:**
- Consumes: `AiHistoryIncrementalUnavailableError` / `AiHistoryAnchorLostError` (Task 1).
- Produces: warm-refresh incremental errors map to `softReloadError` + a l10n string; cold-load errors map to `error`/`errorMessage` (existing behavior), but with a distinct message for incremental-unavailable (so the strip says "transcript changed in a way the incremental parser can't follow").

- [ ] **Step 1: Add l10n keys**

app_en.arb (near `sessionHistorySoftReloadError`, line 736):

```json
"sessionHistoryIncrementalUnavailable": "History changed in a way the incremental reader can't follow (transcript was rewritten/compacted). Choose Retry to reload.",
"sessionHistoryIncrementalUnavailableCold": "Couldn't read an incrementally parseable transcript for this session.",
```

app_zh.arb mirrors:

```json
"sessionHistoryIncrementalUnavailable": "聊天记录以增量解析器无法跟踪的方式发生了变化（转录被重写/压缩）。请选择“重试”重新加载。",
"sessionHistoryIncrementalUnavailableCold": "无法读取该会话可增量解析的转录。",
```

- [ ] **Step 2: Update the seat catch blocks**

In `ai_history_seat.dart`, in `softReload`'s catch (line ~588) and `load`'s catch (line ~420), when `e is AiHistoryIncrementalUnavailableError || e is AiHistoryAnchorLostError`:

```dart
emit(state.copyWith(
  softReloadError: '${e.runtimeType}: ${e.toString()}',
));
```

and for cold load (`errorMessage`):

```dart
emit(AiHistoryState(
  status: AiHistoryViewStatus.error,
  errorMessage: '${e.runtimeType}: ${e.toString()}',
  sessionId: session.sessionId,
  memberId: memberId,
  totalMessageCount: _allMessages.length,
  subagentAttachmentEpoch: _subagentAttachmentEpoch,
));
```

Also add a `bool` helper `static bool isIncrementalError(Object e) => e is AiHistoryIncrementalUnavailableError || e is AiHistoryAnchorLostError;` (public, testable) so the view can render the distinct message.

- [ ] **Step 3: Update the error view strip**

In `session_history_review_messages.dart:83` (softReloadError strip) and `:151` (errorMessage), if `AiHistorySeat.isIncrementalError` is true, use `context.l10n.sessionHistoryIncrementalUnavailable` beside the raw error and keep the existing Retry affordance (`sessionHistoryRetry`).

- [ ] **Step 4: Write the failing test**

In `ai_history_seat_isolation_test.dart`:

```dart
test('incremental unavailable error surfaces as a distinct soft reload error',
    () async {
  // loader whose refresher throws AiHistoryIncrementalUnavailableError on the
  // second load (force) → seat stays ready, softReloadError set.
  await seatInstance.softReload(force: true);
  expect(state.status, AiHistoryViewStatus.ready);
  expect(AiHistorySeat.isIncrementalError(softReloadErrorSource), isTrue);
});
```

- [ ] **Step 5: Run the seat suite**

Run: `cd client && dart run tool/run_tests.dart test/cubits/ai_history_seat_isolation_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/ai_history_seat.dart client/lib/pages/chat/session_history_review_messages.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/cubits/ai_history_seat_isolation_test.dart
git commit -m "feat(history): surface incremental-unavailable errors distinctly in seat"
```

---

### Task 8: Remove Dead Worker-Parse Machinery

**Files:**
- Delete: `client/lib/services/session/history/history_parse_worker.dart`
- Delete: `client/lib/services/session/history/history_parse_worker_adapters.dart`
- Delete tests: `client/test/services/session/history_parse_worker_test.dart`, `client/test/services/session/history_parse_worker_adapters_test.dart`, `client/test/services/session/history_isolate_transport_test.dart`
- Modify: `client/lib/services/session/history/ai_history_loader.dart` (already un-imported in Task 5)
- Modify: `client/test/cubits/ai_history_seat_isolation_test.dart` (drop `_QueuedHistoryParseExecutor` and imports)
- Modify: `client/test/services/session/ai_history_loader_test.dart` (drop `_RecordingHistoryParseExecutor`, `_GateHistoryParseExecutor`, `_CompletingHistoryParseExecutor`, `_ThrowingParseAdapter`, `_largeBundle`)

**Interfaces:**
- Produces: `HistoryParseResult`, `HistoryParseExecutor`, `HistoryParseWorker` no longer exist. Nothing else imports them (verified: only `ai_history_loader.dart` and the deleted tests).

- [ ] **Step 1: Delete the worker files and their tests**
- [ ] **Step 2: Remove references**

In `ai_history_seat_isolation_test.dart`: delete the `_QueuedHistoryParseExecutor` class and its `makeLoader(parseExecutor: ...)` usage (two tests using it — remove/replace them with warm-state hydration tests). Remove `import '...history_parse_worker.dart';`.

In `ai_history_loader_test.dart`: remove `import '...history_parse_worker.dart';` and the executor helper classes listed above, plus any test bodies that still reference `parseExecutor:` / `_largeBundle` (already handled in Task 5, but flush leftovers here; a `grep -rn "HistoryParseExecutor" test/` must return nothing).

- [ ] **Step 3: Run analyze and a broad test sweep**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `cd client && dart run tool/run_tests.dart test/services/session test/services/cli/registry/capabilities/history test/cubits`
Expected: PASS, no references to deleted types.

- [ ] **Step 4: Commit**

```bash
git add -A client/lib/services/session/history/history_parse_worker.dart client/lib/services/session/history/history_parse_worker_adapters.dart client/test/services/session/history_parse_worker_test.dart client/test/services/session/history_parse_worker_adapters_test.dart client/test/services/session/history_isolate_transport_test.dart client/test/cubits/ai_history_seat_isolation_test.dart client/test/services/session/ai_history_loader_test.dart
git commit -m "refactor(history): remove worker parse executor and adapter machinery"
```

---

### Task 9: Integration Real-Store Test (opencode live)

**Files:**
- Modify: `client/test/integration/opencode_history_live_full_vs_incremental_integration_test.dart`
- Modify: `client/test/services/cli/registry/capabilities/history/opencode_history_full_vs_incremental_test.dart`

**Interfaces:**
- Consumes: strict refresh (Task 3), incremental-only loader (Task 5).
- Produces: end-to-end guarantee that the chat live-refresh path never performs a full locate/parse when the store is readable, and that deletion/compaction throws (not silently full-parses).

- [ ] **Step 1: Flip legacy-schema expectation to strict throw**

In `opencode_history_full_vs_incremental_test.dart` group `legacy schema` test `'idle reload is ALWAYS full — the silent degradation repro'`: replace the two-load assertion with:

```dart
final first = await loader.load(...);
expect(locator.calls, 0, reason: 'page-first covers the window');
// Refresh with legacy schema → schema mismatch → strict error, no full parse.
await expectLater(
  loader.load(session: session, memberId: '', launchContext: ctx),
  throwsA(isA<AiHistoryIncrementalUnavailableError>()),
);
expect(locator.calls, 0, reason: 'must not fall back to full locate');
```

Rename the test to `'legacy schema refresh throws incremental-unavailable instead of full parse'`.

- [ ] **Step 2: Flip deletion fallback test to deletion-express**

In the `delta fallback` group `'message deletion (compaction) forces a full reload'`:

```dart
final second = await loader.load(...);
expect(locator.calls, 0, reason: 'deletion is expressed by the row-level refresher');
expect(second.messages.any((m) => m.parts.any((p) => p is AiTextPart && p.text.contains('compact'))), isTrue);
expect(second.messages.any((m) => m.parts.any((p) => p is AiTextPart && p.text == 'hello')), isFalse);
```

Rename to `'message deletion (compaction) is expressed incrementally'`.

- [ ] **Step 3: Update the integration test**

In `opencode_history_live_full_vs_incremental_integration_test.dart`, remove the legacy-schema "silent always-full" path and the "deletion → full reload" expectation; assert that the store changes during an open writer connection are picked up via `seedCold` + row-level refresh with `locator.calls == 0`.

- [ ] **Step 4: Run the integration tests (background)**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/capabilities/history/opencode_history_full_vs_incremental_test.dart`
Run (background): `cd client && dart run tool/run_tests.dart test/integration/opencode_history_live_full_vs_incremental_integration_test.dart --tags integration`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/test/services/cli/registry/capabilities/history/opencode_history_full_vs_incremental_test.dart client/test/integration/opencode_history_live_full_vs_incremental_integration_test.dart
git commit -m "test(history): strict incremental behavior for opencode real store"
```

---

### Task 10: Full Verification

- [ ] **Step 1: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors.

- [ ] **Step 2: Full test suite (background)**

Run: `cd client && dart run tool/run_tests.dart`
Expected: PASS. Fix any residual assertion drift (search for remaining `seedFromFullParse`, `fullIndex` adapter-era assumptions, `workerExecutor` references).

- [ ] **Step 3: Sweep for stale references**

Run (from `client/`):

```bash
grep -rn "seedFromFullParse\|_parseAndEnrich\|_scheduleFullIndex\|HistoryParseExecutor\|history_parse_worker\|_isolateParseMinBytes" lib test
```

Expected: no matches (except the new `seedCold` doc mentions).

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore(history): resolve incremental-only leftovers"
```

---

## Self-Review Notes

- **Spec coverage:** strict incremental-only (Task 5), types (Task 1), seedCold (Tasks 2-3), deletion-express (Task 3/9), anchor-loss throws (Task 4), transient keep-prior + visible error (Task 5 empty-guard + Task 7), enricher on refresh (Task 6), worker cleanup (Task 8), fullIndex from warm state (Task 5).
- **Known ambiguity fixed inline:** opencode `changed` computation in Task 3 Step 3/4 (order-preserving) and `fullIndex` cacheKey definition in Task 5 Step 3f are spelled out.
- **Type consistency:** `seedCold` returns `AiTranscriptIncrementalResult?` everywhere; `AiHistoryIncrementalUnavailableError`/`AiHistoryAnchorLostError` constructed with exactly one `String` argument; `isIncrementalError` is static on `AiHistorySeat`.