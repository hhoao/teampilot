# Multi-Root Workspace Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Search every folder of the current workspace (all targets: local / SSH / WSL / Termux) from both search surfaces, concurrently per folder, with results grouped by directory.

**Architecture:** A new fan-out service (`MultiRootContentSearch`) runs one existing `ContentSearchRunner` per `(fs, root)` slice and merges their streams into tagged events (per-slice error isolation). `ContentSearchCubit` aggregates by `(root, path)` and exposes per-slice errors. The right-tools panel and the search dialog both switch from single `root`/`fs` params to a slice list built from the workspace's resolved `targetSlices`; the dialog's file-name search iterates all workspace folders against the existing per-root cached indexes.

**Tech Stack:** Flutter/Dart, flutter_bloc, `package:teampilot_search` (Rust FFI + Dart fallback engines).

**Spec:** `docs/superpowers/specs/2026-09-09-multi-root-workspace-search-design.md`

## Global Constraints

- **Never invoke `flutter test` directly.** Always: `cd client && dart run tool/run_tests.dart <paths>`. Narrow with `--plain-name <name>`.
- Inner test loop: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`. Full suite (via `dart run tool/run_tests.dart`) only once before claiming done.
- l10n: edit **only** `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb`.
- No `print`; diagnostics via `AppLogger`; user-facing errors via l10n.
- Existing single-root behavior must stay equivalent: a workspace with one folder renders exactly as today (no group headers).
- All commit messages end with:
  `Co-Authored-By: Claude <noreply@anthropic.com>`

## Reference: existing APIs this plan builds on (do not re-implement)

```dart
// client/lib/services/search/content_search_runner.dart
class ContentSearchRunner {
  ContentSearchRunner({required Filesystem fs, required String root, bool forceFallback = false});
  Stream<TpSearchMatch> run(TpSearchOptions options);
  void cancel();                       // stops the Rust walker too
  String get backendLabel;             // 'rust' | 'dart-fallback'
}

// client/lib/services/search/content_replacer.dart
class ContentReplacer {
  ContentReplacer({required Filesystem fs});
  Future<int> replaceAllInFile({required String path, required List<TpSearchMatch> matches, required String replacement});
}

// package:teampilot_search
class TpSearchOptions { String pattern; bool isRegex; bool caseSensitive; bool useGitignore; int? maxResults; List<String> filesToInclude; List<String> filesToExclude; }
class TpSearchMatch { String path; String relativePath; int lineNumber; String lineText; int matchStart; int matchEnd; }

// client/lib/services/search/workspace_search_indexes.dart
class WorkspaceSearchIndexes {
  WorkspaceFileIndex fileIndexFor(String root);   // per-root cached, uses AppStorage.fs
}
// WorkspaceFileIndex: Future<void> ensureFresh(); bool get isReady;
//   List<WorkspaceFileMatch> query(String query, {int? limit});
// WorkspaceFileMatch { String path; String name; String relativePath; }

// client/lib/services/workspace/workspace_tools_scope.dart
class WorkspaceTargetSlice { String targetId; WorkspaceToolsContext tools; List<String> roots; }
class WorkspaceToolsScopeState { WorkspaceToolsContext? tools; List<String> roots; List<WorkspaceTargetSlice> targetSlices; /* … */ }
// WorkspaceToolsContext { String targetId; RuntimeContext context; }  →  context.filesystem is the target's Filesystem

// Filesystem (client/lib/services/io/filesystem.dart) exposes pathContext.
```

---

### Task 1: `MultiRootContentSearch` fan-out service

**Files:**
- Create: `client/lib/services/search/multi_root_content_search.dart`
- Test: `client/test/services/search/multi_root_content_search_test.dart`

**Interfaces:**
- Consumes: `ContentSearchRunner` (unchanged), `TpSearchOptions`, `Filesystem`.
- Produces (later tasks rely on these exact names):
  - `class ContentSearchSlice { const ContentSearchSlice({required this.fs, required this.root, required this.label}); final Filesystem fs; final String root; final String label; }`
  - `class MultiRootSearchEvent { ContentSearchSlice slice; TpSearchMatch? match; Object? error; bool get isError; }`
  - `class MultiRootContentSearch { MultiRootContentSearch({required List<ContentSearchSlice> slices, ContentSearchRunner Function(ContentSearchSlice slice)? runnerFactory}); Stream<MultiRootSearchEvent> run(TpSearchOptions options); void cancel(); }`

- [ ] **Step 1: Write the failing tests**

Create `client/test/services/search/multi_root_content_search_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_search/teampilot_search.dart';

import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/search/content_search_runner.dart';
import 'package:teampilot/services/search/multi_root_content_search.dart';

/// Test-double runner, same pattern as content_search_cubit_test.dart.
class _FakeRunner extends ContentSearchRunner {
  _FakeRunner(this.root) : super(fs: LocalFilesystem(), root: root);

  final String root;
  Stream<TpSearchMatch> Function(TpSearchOptions)? handler;
  int cancelCalls = 0;

  @override
  Stream<TpSearchMatch> run(TpSearchOptions options) {
    final h = handler;
    if (h == null) throw StateError('no handler');
    return h(options);
  }

  @override
  void cancel() => cancelCalls++;
}

TpSearchMatch _m(String path, int line) => TpSearchMatch(
  path: path,
  relativePath: path.split('/').last,
  lineNumber: line,
  lineText: 'hello\n',
  matchStart: 0,
  matchEnd: 5,
);

ContentSearchSlice _slice(String root) => ContentSearchSlice(
  fs: LocalFilesystem(),
  root: root,
  label: root.split('/').last,
);

void main() {
  test('merges matches from all slices, each tagged with its slice', () async {
    final a = _FakeRunner('/a');
    final b = _FakeRunner('/b');
    a.handler = (_) => Stream.fromIterable([_m('/a/x.dart', 1)]);
    b.handler = (_) => Stream.fromIterable([_m('/b/y.dart', 2)]);
    final search = MultiRootContentSearch(
      slices: [_slice('/a'), _slice('/b')],
      runnerFactory: (s) => s.root == '/a' ? a : b,
    );
    final events = await search.run(const TpSearchOptions(pattern: 'h')).toList();
    final roots = events.map((e) => e.slice.root).toSet();
    expect(roots, {'/a', '/b'});
    expect(events.where((e) => !e.isError).map((e) => e.match!.path),
        containsAll(['/a/x.dart', '/b/y.dart']));
  });

  test('a failing slice emits one error event; other slices keep streaming',
      () async {
    final a = _FakeRunner('/a');
    final b = _FakeRunner('/b');
    a.handler = (_) => Stream.error(StateError('ssh down'));
    b.handler = (_) => Stream.fromIterable([_m('/b/y.dart', 2)]);
    final search = MultiRootContentSearch(
      slices: [_slice('/a'), _slice('/b')],
      runnerFactory: (s) => s.root == '/a' ? a : b,
    );
    final events = await search.run(const TpSearchOptions(pattern: 'h')).toList();
    final errors = events.where((e) => e.isError).toList();
    expect(errors, hasLength(1));
    expect(errors.single.slice.root, '/a');
    expect(errors.single.error, isA<StateError>());
    // The healthy slice still delivered its match.
    expect(events.where((e) => !e.isError).map((e) => e.match!.path),
        ['/b/y.dart']);
  });

  test('empty slice list completes immediately without events', () async {
    final search = MultiRootContentSearch(slices: []);
    final events = await search.run(const TpSearchOptions(pattern: 'h')).toList();
    expect(events, isEmpty);
  });

  test('cancel cancels every in-flight runner', () async {
    final a = _FakeRunner('/a');
    final b = _FakeRunner('/b');
    final gate = Completer<void>();
    Stream<TpSearchMatch> gated() => Stream<TpSearchMatch>.multi((c) async {
      c.add(_m('/x', 1));
      await gate.future;
      c.close();
    });
    a.handler = (_) => gated();
    b.handler = (_) => gated();
    final search = MultiRootContentSearch(
      slices: [_slice('/a'), _slice('/b')],
      runnerFactory: (s) => s.root == '/a' ? a : b,
    );
    final done = search.run(const TpSearchOptions(pattern: 'h')).toList();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    search.cancel();
    expect(a.cancelCalls, 1);
    expect(b.cancelCalls, 1);
    gate.complete();
    await done; // must not throw
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/search/multi_root_content_search_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'teampilot' ... multi_root_content_search.dart` / "URI does not exist".

- [ ] **Step 3: Implement the service**

Create `client/lib/services/search/multi_root_content_search.dart`:

```dart
import 'dart:async';

import 'package:teampilot_search/teampilot_search.dart';

import '../io/filesystem.dart';
import 'content_search_runner.dart';

/// One search slice: a single root directory on one target.
class ContentSearchSlice {
  const ContentSearchSlice({
    required this.fs,
    required this.root,
    required this.label,
  });

  /// The target filesystem backing this root (local, SFTP, …).
  final Filesystem fs;

  /// Absolute root path searched by the slice's runner.
  final String root;

  /// Group-header display name (folder basename).
  final String label;
}

/// A tagged event from one slice: a [match], or that slice's [error].
/// Errors are data, not stream errors — a failing slice never disturbs the
/// others.
class MultiRootSearchEvent {
  const MultiRootSearchEvent.match(this.slice, this.match) : error = null;
  const MultiRootSearchEvent.error(this.slice, this.error) : match = null;

  final ContentSearchSlice slice;
  final TpSearchMatch? match;
  final Object? error;

  bool get isError => error != null;
}

/// Fan-out content search: one [ContentSearchRunner] per [ContentSearchSlice],
/// all slices searched concurrently; matches stream through as they arrive and
/// a failing slice emits a single error event. [cancel] stops every in-flight
/// runner (including the Rust walker behind each engine handle).
class MultiRootContentSearch {
  MultiRootContentSearch({
    required List<ContentSearchSlice> slices,
    ContentSearchRunner Function(ContentSearchSlice slice)? runnerFactory,
  }) : _slices = List.unmodifiable(slices),
       _runnerFactory =
           runnerFactory ?? (s) => ContentSearchRunner(fs: s.fs, root: s.root);

  final List<ContentSearchSlice> _slices;
  final ContentSearchRunner Function(ContentSearchSlice slice) _runnerFactory;

  final _runners = <ContentSearchRunner>[];
  final _subscriptions = <StreamSubscription<TpSearchMatch>>[];

  /// Runs [options] on every slice concurrently and merges the tagged events.
  Stream<MultiRootSearchEvent> run(TpSearchOptions options) {
    final master = StreamController<MultiRootSearchEvent>();
    var pending = _slices.length;
    if (pending == 0) {
      scheduleMicrotask(master.close);
      return master.stream;
    }
    for (final slice in _slices) {
      final runner = _runnerFactory(slice);
      _runners.add(runner);
      _subscriptions.add(
        runner.run(options).listen(
          (match) => master.add(MultiRootSearchEvent.match(slice, match)),
          onError: (Object e) =>
              master.add(MultiRootSearchEvent.error(slice, e)),
          onDone: () {
            if (--pending == 0) master.close();
          },
        ),
      );
    }
    return master.stream;
  }

  /// Cancels every in-flight runner and subscription.
  void cancel() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    for (final r in _runners) {
      r.cancel();
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/search/multi_root_content_search_test.dart`
Expected: 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/search/multi_root_content_search.dart client/test/services/search/multi_root_content_search_test.dart
git commit -m "feat(search): add MultiRootContentSearch fan-out service

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: `ContentSearchCubit` multi-slice aggregation

**Files:**
- Modify: `client/lib/cubits/content_search/content_search_cubit.dart`
- Test: `client/test/cubits/content_search/content_search_cubit_test.dart`

**Interfaces:**
- Consumes: `MultiRootContentSearch`, `ContentSearchSlice` (Task 1).
- Produces:
  - `ContentSearchCubit({required List<ContentSearchSlice> slices, required ContentSearchRunner Function(ContentSearchSlice slice) runnerFactory, required ContentReplacer Function(ContentSearchSlice slice) replacerFactory})`
  - `ContentSearchFileGroup` gains `final String rootKey;` and `final String rootLabel;`
  - `ContentSearchState` gains `final Map<String, Object> sliceErrors;` (keyed by root path) and `copyWith(..., Map<String, Object>? sliceErrors, bool clearSliceErrors = false, ...)`.

- [ ] **Step 1: Migrate existing tests and add new multi-root tests**

Rewrite `client/test/cubits/content_search/content_search_cubit_test.dart`. Keep every existing test (they migrate mechanically: the cubit now takes `slices` and slice-taking factories), and add the three new tests at the bottom of `main()`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_search/teampilot_search.dart';

import 'package:teampilot/cubits/content_search/content_search_cubit.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/search/content_replacer.dart';
import 'package:teampilot/services/search/content_search_runner.dart';
import 'package:teampilot/services/search/multi_root_content_search.dart';

/// Test-double runner, unchanged from the previous version.
class _FakeRunner extends ContentSearchRunner {
  _FakeRunner(this.root) : super(fs: LocalFilesystem(), root: root);

  final String root;
  Stream<TpSearchMatch> Function(TpSearchOptions)? handler;
  int cancelCalls = 0;

  @override
  Stream<TpSearchMatch> run(TpSearchOptions options) {
    final h = handler;
    if (h == null) throw StateError('no handler');
    return h(options);
  }

  @override
  void cancel() {
    cancelCalls++;
  }
}

ContentSearchSlice _slice(String root) => ContentSearchSlice(
  fs: LocalFilesystem(),
  root: root,
  label: root.split('/').last,
);

void main() {
  late _FakeRunner fake;
  late ContentSearchCubit cubit;

  Stream<TpSearchMatch> _stream(List<TpSearchMatch> ms) async* {
    for (final m in ms) {
      yield m;
      await Future<void>.delayed(Duration.zero);
    }
  }

  TpSearchMatch _m(String rel, int line, {String root = '/root'}) =>
      TpSearchMatch(
        path: '$root/$rel',
        relativePath: rel,
        lineNumber: line,
        lineText: 'hello world\n',
        matchStart: 0,
        matchEnd: 5,
      );

  setUp(() {
    fake = _FakeRunner('/root');
    cubit = ContentSearchCubit(
      slices: [_slice('/root')],
      runnerFactory: (_) => fake,
      replacerFactory: (_) => throw UnimplementedError(),
    );
  });

  // === migrated tests: bodies unchanged from the previous file version ===

  test('aggregates matches by file, file header precedes its lines', () async {
    fake.handler = (_) =>
        _stream([_m('a.dart', 1), _m('b.txt', 2), _m('a.dart', 3)]);
    await cubit.search(const TpSearchOptions(pattern: 'hello'));
    final st = cubit.state;
    expect(st.searching, isFalse);
    expect(st.files.map((f) => f.relativePath), ['a.dart', 'b.txt']);
    expect(st.files.first.lines.map((l) => l.lineNumber), [1, 3]);
    expect(st.files[1].lines.single.lineNumber, 2);
  });

  test('truncated flag propagates', () async {
    fake.handler = (_) => Stream.fromIterable([_m('a.dart', 1)]);
    await cubit.search(const TpSearchOptions(pattern: 'hello'));
    expect(cubit.state.files, hasLength(1));
  });

  test('cancel stops aggregation and clears searching', () async {
    fake.handler = (_) => _stream([_m('a.dart', 1), _m('b.txt', 2)]);
    final fut = cubit.search(const TpSearchOptions(pattern: 'hello'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    cubit.cancel();
    await fut;
    expect(cubit.state.searching, isFalse);
  });

  test('cancel reaches the runner; a new search cancels the previous run',
      () async {
    final gate = Completer<void>();
    fake.handler = (_) => Stream<TpSearchMatch>.multi((controller) async {
      controller.add(_m('a.dart', 1));
      await gate.future;
      controller.add(_m('b.txt', 2));
      controller.close();
    });
    final fut = cubit.search(const TpSearchOptions(pattern: 'hello'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fake.cancelCalls, 0);
    cubit.cancel();
    expect(fake.cancelCalls, 1);
    gate.complete();
    await fut;

    fake.handler = (_) => _stream([_m('a.dart', 1)]);
    final first = cubit.search(const TpSearchOptions(pattern: 'first'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fake.cancelCalls, 1);
    final second = cubit.search(const TpSearchOptions(pattern: 'second'));
    expect(fake.cancelCalls, 2);
    await first;
    await second;
  });

  test('error surfaces in state, not thrown', () async {
    fake.handler = (_) => Stream.error(StateError('boom'));
    await cubit.search(const TpSearchOptions(pattern: 'hello'));
    expect(cubit.state.error, isA<StateError>());
    expect(cubit.state.searching, isFalse);
  });

  test('clear resets results and query fields', () async {
    fake.handler = (_) => _stream([_m('a.dart', 1)]);
    await cubit.search(const TpSearchOptions(pattern: 'hello'));
    cubit.clear();
    expect(cubit.state.files, isEmpty);
    expect(cubit.state.searching, isFalse);
    expect(cubit.state.error, isNull);
    expect(cubit.state.sliceErrors, isEmpty);
  });

  test('replaceAll skips the emit after close without throwing', () async {
    final slow = _SlowReplacer();
    final closed = ContentSearchCubit(
      slices: [_slice('/root')],
      runnerFactory: (_) => fake,
      replacerFactory: (_) => slow,
    );
    fake.handler = (_) => _stream([_m('a.dart', 1)]);
    await closed.search(const TpSearchOptions(pattern: 'hello'));
    final replace = closed.replaceAll('X');
    await closed.close();
    slow.release();
    expect(await replace, 1);
    expect(closed.state.replacedCount, isNull);
  });

  test('replaceSingle skips the emit after close without throwing', () async {
    final slow = _SlowReplacer();
    final closed = ContentSearchCubit(
      slices: [_slice('/root')],
      runnerFactory: (_) => fake,
      replacerFactory: (_) => slow,
    );
    fake.handler = (_) => _stream([_m('a.dart', 1)]);
    await closed.search(const TpSearchOptions(pattern: 'hello'));
    final replace = closed.replaceSingle('/root/a.dart', 'X');
    await closed.close();
    slow.release();
    expect(await replace, 1);
  });

  // === new multi-root tests ===

  test('groups files per root, slice order preserved', () async {
    final a = _FakeRunner('/a');
    final b = _FakeRunner('/b');
    final multi = ContentSearchCubit(
      slices: [_slice('/b'), _slice('/a')], // b first: files order follows slice order
      runnerFactory: (s) => s.root == '/a' ? a : b,
      replacerFactory: (_) => throw UnimplementedError(),
    );
    a.handler = (_) => _stream([_m('x.dart', 1, root: '/a')]);
    b.handler = (_) => _stream([_m('y.dart', 1, root: '/b')]);
    await multi.search(const TpSearchOptions(pattern: 'hello'));
    expect(multi.state.files.map((f) => f.rootKey), ['/b', '/a']);
    expect(multi.state.files.map((f) => f.rootLabel), ['b', 'a']);
    expect(multi.state.files.map((f) => f.path), ['/b/y.dart', '/a/x.dart']);
  });

  test('a failing slice lands in sliceErrors; other results survive', () async {
    final a = _FakeRunner('/a');
    final b = _FakeRunner('/b');
    final multi = ContentSearchCubit(
      slices: [_slice('/a'), _slice('/b')],
      runnerFactory: (s) => s.root == '/a' ? a : b,
      replacerFactory: (_) => throw UnimplementedError(),
    );
    a.handler = (_) => Stream.error(StateError('ssh down'));
    b.handler = (_) => _stream([_m('y.dart', 1, root: '/b')]);
    await multi.search(const TpSearchOptions(pattern: 'hello'));
    expect(multi.state.sliceErrors.keys, ['/a']);
    expect(multi.state.sliceErrors['/a'], isA<StateError>());
    expect(multi.state.files.map((f) => f.path), ['/b/y.dart']);
    // A partial failure is not a global error.
    expect(multi.state.error, isNull);
  });

  test('all slices failing surfaces a global error', () async {
    final a = _FakeRunner('/a');
    final b = _FakeRunner('/b');
    final multi = ContentSearchCubit(
      slices: [_slice('/a'), _slice('/b')],
      runnerFactory: (s) => s.root == '/a' ? a : b,
      replacerFactory: (_) => throw UnimplementedError(),
    );
    a.handler = (_) => Stream.error(StateError('x'));
    b.handler = (_) => Stream.error(StateError('y'));
    await multi.search(const TpSearchOptions(pattern: 'hello'));
    expect(multi.state.error, isNotNull);
    expect(multi.state.files, isEmpty);
  });
}

/// Replacer that blocks until [release] — unchanged from the previous version.
class _SlowReplacer extends ContentReplacer {
  _SlowReplacer() : super(fs: LocalFilesystem());

  final Completer<void> _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<int> replaceAllInFile({
    required String path,
    required List<TpSearchMatch> matches,
    required String replacement,
  }) async {
    await _gate.future;
    return matches.length;
  }
}
```

Note: the two "close mid-replace" tests construct the cubit with a single slice; `_SlowReplacer` is constructed per-replace through the slice-taking factory.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/cubits/content_search/content_search_cubit_test.dart`
Expected: FAIL — compile errors (`slices`, slice-taking factories, `rootKey`, `sliceErrors` don't exist yet).

- [ ] **Step 3: Implement the cubit changes**

In `client/lib/cubits/content_search/content_search_cubit.dart`:

1. Import `multi_root_content_search.dart`.
2. `ContentSearchFileGroup` — add fields (update the constructor accordingly):

```dart
class ContentSearchFileGroup {
  ContentSearchFileGroup({
    required this.rootKey,
    required this.rootLabel,
    required this.path,
    required this.relativePath,
    required this.lines,
  });

  /// Root path of the slice this file was found under.
  final String rootKey;

  /// Display label of that slice (group header).
  final String rootLabel;
  /* existing fields unchanged */
```

3. `ContentSearchState` — add `sliceErrors` and wire it through `copyWith` (same sentinel pattern as `error`):

```dart
const ContentSearchState({
  /* … */
  this.sliceErrors = const {},
});
final Map<String, Object> sliceErrors;

ContentSearchState copyWith({
  /* … */
  Map<String, Object>? sliceErrors,
  bool clearSliceErrors = false,
}) {
  return ContentSearchState(
    /* … */
    sliceErrors: clearSliceErrors ? const {} : (sliceErrors ?? this.sliceErrors),
  );
}
```

4. Replace the cubit constructor and `search()`:

```dart
class ContentSearchCubit extends Cubit<ContentSearchState> {
  ContentSearchCubit({
    required List<ContentSearchSlice> slices,
    required ContentSearchRunner Function(ContentSearchSlice slice)
        runnerFactory,
    required ContentReplacer Function(ContentSearchSlice slice)
        replacerFactory,
  }) : _slices = List.unmodifiable(slices),
       _runnerFactory = runnerFactory,
       _replacerFactory = replacerFactory,
       super(const ContentSearchState());

  final List<ContentSearchSlice> _slices;
  final ContentSearchRunner Function(ContentSearchSlice slice) _runnerFactory;
  final ContentReplacer Function(ContentSearchSlice slice) _replacerFactory;

  MultiRootContentSearch? _engine;
  int _searchSeq = 0;

  Future<void> search(TpSearchOptions options) async {
    final seq = ++_searchSeq;
    _engine?.cancel();
    final engine = MultiRootContentSearch(
      slices: _slices,
      runnerFactory: _runnerFactory,
    );
    _engine = engine;
    emit(state.copyWith(
      query: options.pattern,
      isRegex: options.isRegex,
      caseSensitive: options.caseSensitive,
      useGitignore: options.useGitignore,
      filesToInclude: options.filesToInclude,
      filesToExclude: options.filesToExclude,
      searching: true,
      error: null,
      clearError: true,
      replacedCount: null,
      clearReplacedCount: true,
      sliceErrors: const {},
      clearSliceErrors: true,
    ));
    // Per-root aggregation: root order follows slice order; within a root,
    // files appear in first-match order.
    final groupsByRoot = <String, Map<String, ContentSearchFileGroup>>{};
    final countsByRoot = <String, int>{};
    final sliceErrors = <String, Object>{};
    var anyMatch = false;

    try {
      await for (final event in engine.run(options)) {
        if (seq != _searchSeq || isClosed) return;
        final root = event.slice.root;
        if (event.isError) {
          sliceErrors[root] = event.error!;
          continue;
        }
        final m = event.match!;
        anyMatch = true;
        countsByRoot.update(root, (v) => v + 1, ifAbsent: () => 1);
        final groups = groupsByRoot.putIfAbsent(root, () => {});
        final group = groups[m.path];
        if (group == null) {
          groups[m.path] = ContentSearchFileGroup(
            rootKey: root,
            rootLabel: event.slice.label,
            path: m.path,
            relativePath: m.relativePath,
            lines: [
              ContentSearchLineMatch(
                lineNumber: m.lineNumber,
                lineText: m.lineText,
                matchStart: m.matchStart,
                matchEnd: m.matchEnd,
              ),
            ],
          );
        } else {
          group.lines.add(
            ContentSearchLineMatch(
              lineNumber: m.lineNumber,
              lineText: m.lineText,
              matchStart: m.matchStart,
              matchEnd: m.matchEnd,
            ),
          );
        }
      }
    } on Object catch (e) {
      if (seq != _searchSeq || isClosed) return;
      emit(state.copyWith(searching: false, error: e));
      return;
    }
    if (seq != _searchSeq || isClosed) return;
    final files = <ContentSearchFileGroup>[
      for (final slice in _slices)
        if (groupsByRoot[slice.root] case final groups?)
          for (final path in groups.keys) groups[path]!,
    ];
    // Every slice failed with zero matches anywhere → global error; partial
    // failures stay in sliceErrors.
    final allFailed =
        sliceErrors.length == _slices.length && _slices.isNotEmpty && !anyMatch;
    final truncated = options.maxResults != null &&
        countsByRoot.values.any((c) => c >= options.maxResults!);
    emit(state.copyWith(
      files: files,
      searching: false,
      truncated: truncated,
      error: allFailed ? sliceErrors.values.first : null,
      clearError: !allFailed,
      sliceErrors: sliceErrors,
      clearSliceErrors: sliceErrors.isEmpty,
    ));
  }
```

5. `cancel()` / `clear()` — replace `_runner?.cancel()` with `_engine?.cancel(); _engine = null;` (keep the seq bump and emits; `clear` also passes `clearSliceErrors: true`).
6. `_replaceGroup` — resolve the slice's replacer instead of a global one:

```dart
  Future<int?> _replaceGroup(
    ContentSearchFileGroup group,
    String replacement,
  ) async {
    try {
      final slice = _slices.firstWhere(
        (s) => s.root == group.rootKey,
        orElse: () => throw StateError('no slice for ${group.rootKey}'),
      );
      final replacer = _replacerFactory(slice);
      /* rest of the existing method body unchanged */
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/content_search/content_search_cubit_test.dart`
Expected: 11 PASS. The panel test (`test/widgets/right_tools/search_panel_test.dart`) and views still compile — they will NOT yet (they construct the cubit with the old signature), so also fix the construction sites now: in `client/lib/widgets/right_tools/right_tools_tool_views.dart` the `create:` callback and in `client/lib/widgets/right_tools/search_panel.dart` `_backendLabel()`/`_openResult` reference `widget.root`/`widget.fs`. Those are Task 3 changes — so at this point `flutter analyze` may show errors in those two files. That is expected and resolved by Task 3. Verify with analyze that no OTHER files broke:

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: errors only in `right_tools_tool_views.dart` / `search_panel.dart` (old cubit constructor / panel params).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/content_search/content_search_cubit.dart client/test/cubits/content_search/content_search_cubit_test.dart
git commit -m "feat(search): aggregate content search across workspace slices in cubit

Co-Authored-By: Claude <noreply@anthropic.com>"
```

(Commit even though the two UI files don't compile yet? **No** — instead fold this step into Task 3's commit if analyze errors block it. Preferably make the codebase compile by doing Task 2 and Task 3 in one working session; commit both together at the end of Task 3 with a message covering both. If you can keep every commit green, Task 2's commit may be deferred.)

---

### Task 3: Slice builder + l10n + panel wiring

**Files:**
- Create: `client/lib/services/search/content_search_slices.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/widgets/right_tools/right_tools_tool_views.dart` (search view construction, ~line 620)
- Modify: `client/lib/widgets/right_tools/search_panel.dart`
- Modify: `client/lib/widgets/right_tools/search_panel_results.dart`
- Test: `client/test/services/search/content_search_slices_test.dart`
- Test: `client/test/widgets/right_tools/search_panel_test.dart` (migrate + new)

**Interfaces:**
- Consumes: `ContentSearchSlice` (Task 1), `ContentSearchCubit` new constructor (Task 2), `WorkspaceToolsScopeState`.
- Produces:
  - `List<ContentSearchSlice> contentSearchSlicesForScope({required WorkspaceToolsScopeState scope, required String cwd, required Filesystem fallbackFs})` — one slice per root per target; empty-scope fallback is a single cwd slice on `fallbackFs`.
  - `WorkspaceSearchPanel({required String workspaceId, required List<ContentSearchSlice> slices, required ValueNotifier<int> focusRequest, void Function(String path, int lineNumber)? onOpenResult})`
  - `SearchPanelResults({..., required Map<String, Object> sliceErrors})` (plus existing params; file groups now carry `rootKey`/`rootLabel`).
  - l10n key `workspaceSearchSliceError` with a `{directory}` String placeholder.

- [ ] **Step 1: Add l10n strings**

In `client/lib/l10n/app_en.arb`, after the `workspaceSearchError` entry (~line 683):

```json
  "workspaceSearchSliceError": "Search failed in \"{directory}\"",
  "@workspaceSearchSliceError": {
    "placeholders": {
      "directory": {
        "type": "String"
      }
    }
  },
```

In `client/lib/l10n/app_zh.arb`, in the same relative position (next to its `workspaceSearchError` entry):

```json
  "workspaceSearchSliceError": "「{directory}」目录搜索失败",
  "@workspaceSearchSliceError": {
    "placeholders": {
      "directory": {
        "type": "String"
      }
    }
  },
```

- [ ] **Step 2: Write failing tests for the slice builder**

Create `client/test/services/search/content_search_slices_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/search/content_search_slices.dart';
import 'package:teampilot/services/workspace/workspace_tools_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';

/// Minimal RuntimeContext stand-in is not available; the builder only reads
/// tools.context.filesystem, so wrap a real WorkspaceToolsContext with a
/// LocalFilesystem-backed RuntimeContext resolved through
/// WorkspaceToolsContext's public constructor.
WorkspaceTargetSlice _slice(String targetId, List<String> roots) {
  final tools = WorkspaceToolsContext(
    targetId: targetId,
    context: _localRuntimeContext(),
  );
  return WorkspaceTargetSlice(targetId: targetId, tools: tools, roots: roots);
}

void main() {
  test('one slice per root per target, in scope order', () {
    final scope = WorkspaceToolsScopeState(
      targetSlices: [
        _slice('local', ['/ws/a', '/ws/b']),
        _slice('ssh:one', ['/remote/c']),
      ],
      resolving: false,
    );
    final slices = contentSearchSlicesForScope(
      scope: scope,
      cwd: '/ws/a',
      fallbackFs: LocalFilesystem(),
    );
    expect(slices.map((s) => s.root), ['/ws/a', '/ws/b', '/remote/c']);
    expect(slices.map((s) => s.label), ['a', 'b', 'c']);
  });

  test('falls back to a single cwd slice when no target resolved', () {
    final scope = const WorkspaceToolsScopeState(resolving: true);
    final slices = contentSearchSlicesForScope(
      scope: scope,
      cwd: '/ws/a',
      fallbackFs: LocalFilesystem(),
    );
    expect(slices, hasLength(1));
    expect(slices.single.root, '/ws/a');
    expect(slices.single.label, 'a');
  });
}
```

Note on `_localRuntimeContext()`: check how existing tests construct a `RuntimeContext` with a local filesystem (search `test/` for `RuntimeContext(` — e.g. tests for `workspace_tools_scope`). Use the simplest existing pattern; the requirement is only that `context.filesystem` is a working `Filesystem`. If a lighter public constructor exists, prefer it; the assertion targets are the slice roots/labels, not the context internals.

- [ ] **Step 3: Run to verify failure**

Run: `cd client && dart run tool/run_tests.dart test/services/search/content_search_slices_test.dart`
Expected: FAIL — file `content_search_slices.dart` does not exist.

- [ ] **Step 4: Implement the builder**

Create `client/lib/services/search/content_search_slices.dart`:

```dart
import '../io/filesystem.dart';
import '../workspace/workspace_tools_scope.dart';
import 'multi_root_content_search.dart';

/// Builds one [ContentSearchSlice] per root per resolved target of [scope].
///
/// Falls back to a single cwd slice on [fallbackFs] when nothing resolved yet
/// (scope still resolving), preserving the pre-multi-root behavior of the
/// search panel.
List<ContentSearchSlice> contentSearchSlicesForScope({
  required WorkspaceToolsScopeState scope,
  required String cwd,
  required Filesystem fallbackFs,
}) {
  final slices = <ContentSearchSlice>[];
  for (final target in scope.targetSlices) {
    final fs = target.tools.context.filesystem;
    for (final root in target.roots) {
      if (root.trim().isEmpty) continue;
      slices.add(
        ContentSearchSlice(
          fs: fs,
          root: root,
          label: fs.pathContext.basename(root),
        ),
      );
    }
  }
  if (slices.isEmpty && cwd.trim().isNotEmpty) {
    slices.add(
      ContentSearchSlice(
        fs: fallbackFs,
        root: cwd,
        label: fallbackFs.pathContext.basename(cwd),
      ),
    );
  }
  return slices;
}
```

- [ ] **Step 5: Run slice-builder tests**

Run: `cd client && dart run tool/run_tests.dart test/services/search/content_search_slices_test.dart`
Expected: 2 PASS.

- [ ] **Step 6: Wire the panel**

In `client/lib/widgets/right_tools/right_tools_tool_views.dart` (search view block, ~line 620), replace:

```dart
      final root = widget.scope.roots.firstOrNull ?? widget.cwd;
      final fs = widget.workContext.filesystem;
```

with:

```dart
      final slices = contentSearchSlicesForScope(
        scope: widget.scope,
        cwd: widget.cwd,
        fallbackFs: widget.workContext.filesystem,
      );
```

and the cubit/panel construction:

```dart
            child: BlocProvider(
              lazy: false,
              create: (context) => ContentSearchCubit(
                slices: slices,
                runnerFactory: (slice) =>
                    ContentSearchRunner(fs: slice.fs, root: slice.root),
                replacerFactory: (slice) => ContentReplacer(fs: slice.fs),
              ),
              child: WorkspaceSearchPanel(
                workspaceId: widget.workspaceId,
                slices: slices,
                focusRequest: widget.searchFocusRequest,
              ),
            ),
```

Add the import `import '../../services/search/content_search_slices.dart';` (follow the file's existing relative-import style).

In `client/lib/widgets/right_tools/search_panel.dart`:
- Change the widget params: remove `root` / `fs`, add `final List<ContentSearchSlice> slices;`; import `multi_root_content_search.dart` (drop the now-unused `filesystem.dart`/`content_search_runner.dart` imports if nothing else uses them — `content_search_runner.dart` is still needed for `_backendLabel`).
- `_backendLabel()`:

```dart
  String _backendLabel() {
    final labels = <String>{
      for (final s in widget.slices)
        ContentSearchRunner(fs: s.fs, root: s.root).backendLabel,
    };
    return labels.toList().join(' / ');
  }
```

- `_openResult` — pick the fs of the slice whose root prefixes the path:

```dart
  void _openResult(BuildContext context, String path, int lineNumber) {
    final handler = widget.onOpenResult;
    if (handler != null) {
      handler(path, lineNumber);
      return;
    }
    final editor = context.read<EditorCubit>();
    editor.openFile(widget.workspaceId, path, fs: _fsForPath(path));
    editor.selectLines(widget.workspaceId, path, startLine: lineNumber);
  }

  Filesystem _fsForPath(String path) {
    for (final s in widget.slices) {
      if (path == s.root || path.startsWith('${s.root}/') ||
          path.startsWith('${s.root}\\')) {
        return s.fs;
      }
    }
    return widget.slices.first.fs;
  }
```

- Pass `sliceErrors: state.sliceErrors` to `SearchPanelResults`.

In `client/lib/widgets/right_tools/search_panel_results.dart`:
- Add `final Map<String, Object> sliceErrors;` param.
- Render per-root headers and error rows inside the `ListView.builder`. Build a flat model first (keep the existing `_FileGroupTile` untouched):

```dart
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    if (files.isEmpty) { /* existing empty branch unchanged */ }
    // Flat item list: a root header whenever the root changes (only when the
    // results span more than one root — single-root stays header-less), each
    // file group, a per-slice error row after that root's groups, then the
    // truncation footer.
    final roots = files.map((f) => f.rootKey).toSet();
    final items = <_ResultItem>[];
    String? lastRoot;
    for (final group in files) {
      if (group.rootKey != lastRoot) {
        lastRoot = group.rootKey;
        if (roots.length > 1) {
          items.add(_ResultItem.header(group.rootLabel));
        }
      }
      items.add(_ResultItem.group(group));
    }
    for (final entry in sliceErrors.entries) {
      items.add(_ResultItem.error(entry.key));
    }
    return ListView.builder(
      itemCount: items.length + (truncated ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == items.length) { /* existing truncation footer unchanged */ }
        final item = items[index];
        return switch (item) {
          _ResultHeader(:final label) => Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
            child: Text(
              label,
              style: styles.mutedSm
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          _ResultError(:final rootKey) => Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              l10n.workspaceSearchSliceError(
                files
                    .firstWhere((f) => f.rootKey == rootKey,
                        orElse: () => files.first)
                    .rootLabel,
              ),
              style: styles.mutedSm,
            ),
          ),
          _ResultGroup(:final group) => _FileGroupTile(
            key: ValueKey('search-group-${group.path}'),
            group: group,
            /* existing wiring unchanged */
          ),
        };
      },
    );
  }
```

with a sealed class at the bottom of the file:

```dart
sealed class _ResultItem;

class _ResultHeader extends _ResultItem {
  _ResultHeader(this.label);
  final String label;
}

class _ResultError extends _ResultItem {
  _ResultError(this.rootKey);
  final String rootKey;
}

class _ResultGroup extends _ResultItem {
  _ResultGroup(this.group);
  final ContentSearchFileGroup group;
}
```

Important: the error row needs the slice **label**, but a fully-failed slice has no file groups. Attach the label to the error item instead — change `sliceErrors` rendering to take `Map<String, (Object, String)>`? Simpler: in `search_panel.dart` build the map `sliceErrors` into label-aware pairs before passing:

In `search_panel.dart` where the results widget is constructed:

```dart
              child: SearchPanelResults(
                files: state.files,
                sliceErrors: {
                  for (final e in state.sliceErrors.entries)
                    if (_labelForRoot(e.key) case final label?) e.key: (e.value, label),
                },
```

and adjust `SearchPanelResults.sliceErrors` to `Map<String, (Object, String)>` (error + label), rendering `l10n.workspaceSearchSliceError(entry.value.$2)` with the same error style as the global error row (`styles.smColored(cs.error)` — it needs `cs`; fetch `Theme.of(context).colorScheme`). Add in `search_panel.dart`:

```dart
  String? _labelForRoot(String root) {
    for (final s in widget.slices) {
      if (s.root == root) return s.label;
    }
    return null;
  }
```

(This replaces the `files.firstWhere(...)` fallback shown in the sketch above — a root with only an error and zero groups must still render its label.)

- [ ] **Step 7: Migrate the panel test**

In `client/test/widgets/right_tools/search_panel_test.dart`: every construction of `WorkspaceSearchPanel` / `ContentSearchCubit` migrates from `root:`/`fs:` to:

```dart
slices: [
  ContentSearchSlice(fs: LocalFilesystem(), root: fixtureRoot, label: 'fixture'),
],
```

and the cubit:

```dart
ContentSearchCubit(
  slices: slices,
  runnerFactory: (slice) => fakeRunner,
  replacerFactory: (slice) => fakeReplacer,
),
```

Add one new widget test: two slices (two temp fixture dirs with a match each) → after a search, both group headers render (`expect(find.text('a'), findsOneWidget)` / `find.text('b')`), and rows from both directories are listed. Follow the file's existing helper style for fixtures and pumping.

- [ ] **Step 8: Run tests + analyze**

Run: `cd client && dart run tool/run_tests.dart test/services/search/content_search_slices_test.dart test/widgets/right_tools/search_panel_test.dart`
Expected: PASS.

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors (this also clears the expected Task-2 fallout; the dialog files still compile because the dialog does not use the cubit).

- [ ] **Step 9: Commit (covers Tasks 2+3 if Task 2 was left uncommitted)**

```bash
git add -A client/lib client/test
git commit -m "feat(search): multi-slice content search in right-tools panel

Search every workspace folder concurrently across targets (local/SSH/WSL),
group results by directory, and isolate per-directory failures.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Dialog content section over slices

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_search_content_section.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_search_dialog.dart` (`_buildContentSection`, widget `fs` field, `showWorkspaceSearchDialog` signature)
- Modify: `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart` (`_openSearch`)
- Test: `client/test/pages/home_workspace/workspace/workspace_search_dialog_content_test.dart`

**Interfaces:**
- Consumes: `ContentSearchSlice`, `MultiRootContentSearch` (Task 1), `contentSearchSlicesForScope` (Task 3), l10n `workspaceSearchSliceError`.
- Produces:
  - `WorkspaceSearchContentSection({required List<ContentSearchSlice> slices, required void Function(String path) onOpenFile})` (no more `root`/`fs`)
  - `showWorkspaceSearchDialog(BuildContext context, {required Workspace workspace, required List<ContentSearchSlice> slices, /* unchanged: emptyTitleFallback etc. are read from context */})` — the `fs` param is replaced by `slices`.

- [ ] **Step 1: Migrate + extend the content-section tests**

In `client/test/pages/home_workspace/workspace/workspace_search_dialog_content_test.dart`:
- Replace the section's `root:`/`fs:` params in `wrapSection` with `slices:` built from the fixture dir:

```dart
  Widget wrapSection({
    required void Function(String path) onOpenFile,
    required String root,
  }) {
    final slices = [
      ContentSearchSlice(
        fs: LocalFilesystem(),
        root: root,
        label: 'fixture',
      ),
    ];
    /* same tree as today, with slices: slices instead of root:/fs: */
```

- Add a two-root test (second temp fixture `fixture2` with a distinct file), asserting both directories' rows render **and** a group header per directory appears (`find.text('fixture')`, `find.text('fixture2')` — headers only render when >1 slice).
- Add a failure-isolation test: one slice whose root does not exist on the local fs plus the healthy fixture slice → healthy rows render and the missing directory shows the `workspaceSearchSliceError` text (`find.textContaining('Search failed')` under the en locale).

- [ ] **Step 2: Run to verify failure**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_search_dialog_content_test.dart`
Expected: FAIL — `WorkspaceSearchContentSection` has no `slices` param.

- [ ] **Step 3: Implement the section changes**

In `workspace_search_content_section.dart`:
- Params: `required this.slices` (type `List<ContentSearchSlice>`), drop `root`/`fs`; import `multi_root_content_search.dart` + `l10n` already present.
- `_run()`: replace the single runner with a `MultiRootContentSearch` held in `_search` (rename of `_runner`, cancel on dispose / before each run the same way); aggregate per slice into a flat render list:

```dart
  final _results = <_ContentHit>[];
  bool _searching = false;
  bool _truncated = false;
  bool _error = false; // only when every slice failed
  final _sliceErrors = <String, String>{}; // root → label
  MultiRootContentSearch? _search;

  Future<void> _run() async {
    final seq = ++_seq;
    _search?.cancel();
    final query = _controller.text.trim();
    if (query.isEmpty) { /* existing reset, also clear _sliceErrors */ }
    setState(() { _searching = true; _error = false; });
    final hits = <_ContentHit>[];
    final sliceErrors = <String, String>{};
    final counts = <String, int>{};
    var anyMatch = false;
    final search = MultiRootContentSearch(slices: widget.slices);
    _search = search;
    try {
      await for (final event in search.run(TpSearchOptions(
        pattern: query,
        isRegex: _isRegex,
        caseSensitive: _caseSensitive,
        maxResults: _maxDialogContentResults,
      ))) {
        if (seq != _seq || !mounted) return;
        if (event.isError) {
          sliceErrors[event.slice.root] = event.slice.label;
          continue;
        }
        anyMatch = true;
        counts.update(event.slice.root, (v) => v + 1,
            ifAbsent: () => 1);
        hits.add(_ContentHit(event.slice, event.match!));
      }
    } on Object {
      /* existing global-error branch */
    }
    if (seq != _seq || !mounted) return;
    setState(() {
      _results
        ..clear()
        ..addAll(hits);
      _sliceErrors
        ..clear()
        ..addAll(sliceErrors);
      _truncated = counts.values.any(
        (c) => c >= _maxDialogContentResults,
      );
      _error = !anyMatch && sliceErrors.length == widget.slices.length;
      _searching = false;
    });
  }
```

with a tiny record-based hit type (top of file):

```dart
/// One content hit tagged with the slice it came from.
typedef _ContentHit = (ContentSearchSlice slice, TpSearchMatch match);
```

- Rendering: keep the existing `ListView.builder`, but interleave — a header whenever `slice.root` changes (only when `widget.slices.length > 1`), then the existing `WorkspaceSearchFileRow(name: '${m.relativePath}:${m.lineNumber}', …)` per hit; after the list, one `WorkspaceSearchStatusRow(label: l10n.workspaceSearchSliceError(label))` per entry of `_sliceErrors`; `_error` keeps the existing global `workspaceSearchError` row. Matches are grouped per slice because events arrive per runner — but to be robust, sort `hits` by slice order before rendering:

```dart
    final sliceOrder = [for (final s in widget.slices) s.root];
    hits.sort((a, b) => sliceOrder
        .indexOf(a.$1.root)
        .compareTo(sliceOrder.indexOf(b.$1.root)));
```

- [ ] **Step 4: Update the dialog plumbing**

In `workspace_search_dialog.dart`:
- `showWorkspaceSearchDialog`: replace `required Filesystem fs` with `required List<ContentSearchSlice> slices`; thread it into `WorkspaceSearchDialog(slices: slices, …)` replacing `fs: fs`; drop the `Filesystem` import if now unused.
- `WorkspaceSearchDialog` widget: `final Filesystem fs;` → `final List<ContentSearchSlice> slices;`
- `_buildContentSection()`:

```dart
  Widget _buildContentSection() {
    return WorkspaceSearchContentSection(
      slices: widget.slices,
      onOpenFile: widget.onOpenFile,
    );
  }
```

- Update the class doc comment's last line (it currently says content search "roots the first workspace folder").

In `workspace_split_pane.dart` `_openSearch()`:

```dart
    final scopeState = scopeCubit.state;
    unawaited(
      showWorkspaceSearchDialog(
        context,
        workspace: widget.workspace,
        slices: contentSearchSlicesForScope(
          scope: scopeState,
          cwd: widget.workspace.firstFolderPath,
          fallbackFs: scopeState.tools?.context.filesystem ?? LocalFilesystem(),
        ),
      ),
    );
```

(`cwd` here is the pre-resolution stand-in root: the first folder. Import `content_search_slices.dart`; keep the existing `LocalFilesystem` fallback import.)

- [ ] **Step 5: Run tests + analyze**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_search_dialog_content_test.dart`
Expected: PASS (existing 2 + 3 new).

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: errors only in files still constructing the dialog with `fs:` — `workspace_search_dialog_test.dart` (Task 5 fixes it). If `workspace_search_dialog_test.dart` fails to compile, that blocks the whole test binary; if so, do the minimal `fs:` → `slices:` mechanical fix in its `_host` helper now (the fuller Task 5 changes still apply):

```dart
            body: WorkspaceSearchDialog(
              /* … */
              slices: [
                ContentSearchSlice(
                  fs: LocalFilesystem(),
                  root: workspace.firstFolderPath,
                  label: 'fixture',
                ),
              ],
```

- [ ] **Step 6: Commit**

```bash
git add -A client/lib client/test
git commit -m "feat(search): dialog content filter searches all workspace slices

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Dialog file-name search across all folders

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_search_dialog.dart` (`_warmIndexes`, `_runSearches`, `_buildFilesSection`, `_fileMatches` state)
- Test: `client/test/pages/workspace_search_dialog_test.dart`

**Interfaces:**
- Consumes: `WorkspaceSearchIndexes.fileIndexFor(root)` (existing), `workspace.folders`.
- Produces: no new public API — dialog-internal grouping only.

- [ ] **Step 1: Add a multi-folder test**

In `client/test/pages/workspace_search_dialog_test.dart` (its `_host` now passes `slices:` per Task 4), add a test using a workspace with two folders and files on disk:

```dart
  testWidgets('file search lists matches from every workspace folder',
      (tester) async {
    final dirA = Directory.systemTemp.createTempSync('tp_ws_a_');
    final dirB = Directory.systemTemp.createTempSync('tp_ws_b_');
    addTearDown(() {
      dirA.deleteSync(recursive: true);
      dirB.deleteSync(recursive: true);
    });
    File('${dirA.path}/alpha.dart').writeAsStringSync('');
    File('${dirB.path}/beta.dart').writeAsStringSync('');
    final workspace = Workspace(
      workspaceId: 'ws-1',
      folders: [
        WorkspaceFolder(path: dirA.path),
        WorkspaceFolder(path: dirB.path),
      ],
    );
    await _pumpDialog(
      tester,
      _host(/* existing required args, workspace: workspace */),
    );
    await tester.enterText(find.byType(WorkspaceSearchField).first, 'dart');
    await tester.pumpAndSettle();
    expect(find.text('alpha.dart'), findsOneWidget);
    expect(find.text('beta.dart'), findsOneWidget);
    // Both directory groups carry a header (multi-folder only).
    expect(find.text(dirA.path.split(Platform.pathSeparator).last),
        findsOneWidget);
    expect(find.text(dirB.path.split(Platform.pathSeparator).last),
        findsOneWidget);
  });
```

(Adapt `Workspace`'s constructor and `_host`'s parameters to the file's existing helpers — check how current tests build a `Workspace`; keep the same style. `WorkspaceSearchField` is the dialog's input; reuse whatever finder the existing file-query tests use.)

- [ ] **Step 2: Run to verify failure**

Run: `cd client && dart run tool/run_tests.dart test/pages/workspace_search_dialog_test.dart`
Expected: FAIL — `beta.dart` missing (only the first folder is searched today).

- [ ] **Step 3: Implement multi-folder file search**

In `workspace_search_dialog.dart`:

1. Replace the flat state with per-folder groups:

```dart
/// One folder's file-name matches.
class _FileFolderGroup {
  const _FileFolderGroup({required this.label, required this.matches});
  final String label;
  final List<WorkspaceFileMatch> matches;
}

List<_FileFolderGroup> _fileGroups = const [];
```

2. `_warmIndexes()` — warm every folder's index (fire together, await both):

```dart
    final fileWarms = <Future<void>>[
      for (final folder in widget.workspace.folders)
        if (folder.path.trim().isNotEmpty)
          widget.indexes.fileIndexFor(folder.path).ensureFresh(),
    ];
    try {
      await Future.wait([contentWarm, ...fileWarms]);
      /* existing re-run + finally unchanged */
```

3. `_runSearches()` — replace the single-root block:

```dart
    // Files: cached per-root indexes, synchronous after the first build.
    // Remote folders yield no local matches (the index walks AppStorage.fs);
    // content search covers remote folders via its per-slice filesystems.
    final folders = [
      for (final f in widget.workspace.folders)
        if (f.path.trim().isNotEmpty) f,
    ];
    if (folders.isEmpty) {
      if (!mounted) return;
      setState(() {
        _searchingFiles = false;
        _fileGroups = const [];
      });
      return;
    }
    if (folders.any(
          (f) => !widget.indexes.fileIndexFor(f.path).isReady,
        ) &&
        mounted) {
      setState(() => _searchingFiles = true);
    }
    await Future.wait([
      for (final f in folders) widget.indexes.fileIndexFor(f.path).ensureFresh(),
    ]);
    if (!mounted || seq != _searchSeq) return;
    final groups = <_FileFolderGroup>[
      for (final f in folders)
        _FileFolderGroup(
          label: f.path.split(Platform.pathSeparator).last,
          matches: widget.indexes
              .fileIndexFor(f.path)
              .query(query, limit: _maxFileResultsExpanded),
        ),
    ];
    setState(() {
      _searchingFiles = false;
      _fileGroups = [for (final g in groups) if (g.matches.isNotEmpty) g];
    });
```

(Add `import 'dart:io' show Platform;` if not already imported. If the file targets web too and `Platform` is disallowed, use `p.basename`-style splitting via the existing path utilities — check sibling imports; the codebase is desktop/mobile, `Platform.pathSeparator` is used elsewhere in tests.)

4. `_buildFilesSection()` — render per-folder blocks with headers when `_fileGroups.length > 1`; keep the global `_maxFileResults` cap across groups and the existing "show more" logic on the total count:

```dart
  Widget _buildFilesSection(AppLocalizations l10n) { … }
```

Structure: build a flat children list — `WorkspaceSearchSectionHeader(文件)` first (existing), then for each group (after applying the remaining global cap): a small label header (same style the codebase uses for the content-section group headers — reuse `WorkspaceSearchSectionHeader` with the folder label) followed by `WorkspaceSearchFileRow(name: match.name, query: _query, relativePath: match.relativePath, onTap: () => widget.onOpenFile(match.path))` per match. The global cap walks groups in order, slicing each group's list until `_maxFileResults` is exhausted (or all when `_filesExpanded`); the "show more" link appears when the total across groups exceeds the cap.

5. Total-count guards: any existing `if (_fileMatches.isEmpty)` becomes `_fileGroups.isEmpty`; `_fileMatches.length` totals become `_fileGroups.fold<int>(0, (n, g) => n + g.matches.length)`.

- [ ] **Step 4: Run tests + analyze**

Run: `cd client && dart run tool/run_tests.dart test/pages/workspace_search_dialog_test.dart test/pages/home_workspace/workspace/workspace_search_dialog_content_test.dart test/pages/home_workspace/workspace/workspace_search_host_binding_test.dart`
Expected: PASS (existing single-folder tests unchanged in behavior: one folder → no per-folder headers, same caps).

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add -A client/lib client/test
git commit -m "feat(search): dialog file search covers every workspace folder

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Full verification

**Files:** none new — verification only.

- [ ] **Step 1: Full analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: clean.

- [ ] **Step 2: Full test suite (background, once)**

Run: `cd client && dart run tool/run_tests.dart` (in the background per the test-loop rules; it is slow).
Expected: all PASS. If unrelated pre-existing failures appear, verify they exist on `main` before the first commit of this branch before disregarding them.

- [ ] **Step 3: Report**

Summarize: what changed, test results (paste the tail of the suite output), and any deviations from the plan taken during implementation.

---

## Self-Review Notes

- Spec coverage: fan-out service (Task 1) ✔; cubit grouping + sliceErrors + per-slice replace (Task 2) ✔; panel slices + grouped rendering + mixed backend label (Task 3) ✔; dialog content filter (Task 4) ✔; dialog file-name multi-folder + warm-all (Task 5) ✔; l10n en+zh (Task 3 Step 1) ✔; open-result fs routing (Task 3 `_fsForPath`) ✔; single-root equivalence constraint (Tasks 3–5 render headers only when >1 root/folder) ✔.
- Known deviation from spec, deliberate: per-slice `maxResults` means a multi-root workspace can return up to `N × cap` matches instead of a global cap — spec §"Result caps" chose per-slice caps for engine simplicity; the truncated flag still surfaces.
- Remote folders' file-name search: the per-root index walks `AppStorage.fs` (local), so remote folders return no file-name matches; content search covers them via per-slice fs. This matches the existing behavior for a remote first folder and is documented in Task 5's code comment.
