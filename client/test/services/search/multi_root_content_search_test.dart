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
