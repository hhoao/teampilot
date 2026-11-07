import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/retryable_memo.dart';

void main() {
  test('memoizes a successful load', () async {
    var calls = 0;
    final memo = retryableMemo(() async => ++calls);

    expect(await memo(), 1);
    expect(await memo(), 1);
    expect(calls, 1);
  });

  test('does not memoize a failure; the next call retries', () async {
    var calls = 0;
    final memo = retryableMemo(() async {
      calls++;
      if (calls == 1) throw StateError('transient');
      return calls;
    });

    await expectLater(memo(), throwsStateError);
    expect(await memo(), 2);
    expect(await memo(), 2);
    expect(calls, 2);
  });

  test('concurrent callers share a single in-flight attempt', () async {
    var calls = 0;
    final completer = Completer<int>();
    final memo = retryableMemo(() {
      calls++;
      return completer.future;
    });

    final a = memo();
    final b = memo();
    completer.complete(7);

    expect(await a, 7);
    expect(await b, 7);
    expect(calls, 1);
  });
}
