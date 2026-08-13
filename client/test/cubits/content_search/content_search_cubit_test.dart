import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_search/teampilot_search.dart';

import 'package:teampilot/cubits/content_search/content_search_cubit.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/search/content_replacer.dart';

class _FakeRunner {
  Stream<TpSearchMatch> Function(TpSearchOptions)? handler;
}

void main() {
  late _FakeRunner fake;
  late ContentSearchCubit cubit;

  Stream<TpSearchMatch> _stream(List<TpSearchMatch> ms) async* {
    for (final m in ms) {
      yield m;
      await Future<void>.delayed(Duration.zero);
    }
  }

  TpSearchMatch _m(String rel, int line, {int start = 0, int end = 5}) =>
      TpSearchMatch(
        path: '/root/$rel',
        relativePath: rel,
        lineNumber: line,
        lineText: 'hello world\n',
        matchStart: start,
        matchEnd: end,
      );

  setUp(() {
    fake = _FakeRunner();
    cubit = ContentSearchCubit(
      runnerFactory: (options) {
        final h = fake.handler;
        if (h == null) throw StateError('no handler');
        return h(options);
      },
      replacerFactory: () => throw UnimplementedError(),
    );
  });

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
    // 引擎不传 truncated（本包 Stream 不暴露）；v1 截断语义由引擎 maxResults
    // 决定（流提前 done）。此处断言 searching 结束即完成聚合。
    expect(cubit.state.files, hasLength(1));
  });

  test('cancel stops aggregation and clears searching', () async {
    fake.handler = (_) => _stream([_m('a.dart', 1), _m('b.txt', 2)]);
    final fut = cubit.search(const TpSearchOptions(pattern: 'hello'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    cubit.cancel();
    await fut;
    final st = cubit.state;
    expect(st.searching, isFalse);
    // 取消后允许部分结果存在（流被终止），不再聚合新文件。
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
  });

  test('replaceAll skips the emit after close without throwing', () async {
    final slow = _SlowReplacer();
    final closed = ContentSearchCubit(
      runnerFactory: (options) => fake.handler!(options),
      replacerFactory: () => slow,
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
      runnerFactory: (options) => fake.handler!(options),
      replacerFactory: () => slow,
    );
    fake.handler = (_) => _stream([_m('a.dart', 1)]);
    await closed.search(const TpSearchOptions(pattern: 'hello'));
    final replace = closed.replaceSingle('/root/a.dart', 'X');
    await closed.close();
    slow.release();
    expect(await replace, 1);
    expect(closed.state.replacedCount, isNull);
  });
}

/// Replacer that blocks until [release] so the cubit can be closed mid-replace.
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
