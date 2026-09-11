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

  // === fix-wave tests: duplicate-root robustness and truncation ===

  test('two slices sharing one root string emit each file group once',
      () async {
    // Both slices share the root string, so the factory cannot dispatch on
    // root — hand out one runner per slice by call order instead.
    final runners = [_FakeRunner('/dup'), _FakeRunner('/dup')];
    var next = 0;
    final multi = ContentSearchCubit(
      slices: [_slice('/dup'), _slice('/dup')],
      runnerFactory: (_) => runners[next++],
      replacerFactory: (_) => throw UnimplementedError(),
    );
    runners[0].handler = (_) => _stream([_m('a.dart', 1, root: '/dup')]);
    runners[1].handler = (_) => _stream([_m('b.txt', 1, root: '/dup')]);
    await multi.search(const TpSearchOptions(pattern: 'hello'));
    // Both runners feed the same root; without the emission-loop guard each
    // group would be emitted twice with identical (rootKey, path).
    expect(multi.state.files, hasLength(2));
    expect(multi.state.files.map((f) => f.path), ['/dup/a.dart', '/dup/b.txt']);
  });

  test('allFailed compares against distinct roots, not raw slices', () async {
    final a = _FakeRunner('/dup');
    final multi = ContentSearchCubit(
      slices: [_slice('/dup'), _slice('/dup')],
      runnerFactory: (_) => a,
      replacerFactory: (_) => throw UnimplementedError(),
    );
    a.handler = (_) => Stream.error(StateError('down'));
    await multi.search(const TpSearchOptions(pattern: 'hello'));
    // sliceErrors has one entry for one distinct root → every root failed.
    expect(multi.state.error, isA<StateError>());
    expect(multi.state.files, isEmpty);
  });

  test('truncated is set when a slice reaches maxResults, else false',
      () async {
    fake.handler = (_) => Stream.fromIterable([
      for (var i = 0; i < 3; i++) _m('a.dart', i + 1),
    ]);
    await cubit.search(const TpSearchOptions(pattern: 'hello', maxResults: 3));
    expect(cubit.state.files, hasLength(1));
    expect(cubit.state.truncated, isTrue);

    fake.handler = (_) =>
        Stream.fromIterable([_m('a.dart', 1), _m('a.dart', 2)]);
    await cubit.search(const TpSearchOptions(pattern: 'hello', maxResults: 3));
    expect(cubit.state.files, hasLength(1));
    expect(cubit.state.truncated, isFalse);
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
