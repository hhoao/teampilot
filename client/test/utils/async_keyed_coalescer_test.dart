import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/async_keyed_coalescer.dart';

void main() {
  test('same key runs work once and shares result', () async {
    final c = AsyncKeyedCoalescer();
    var runs = 0;
    Future<int> work() async {
      runs++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return 7;
    }

    final results = await Future.wait([
      c.run('a', work),
      c.run('a', work),
      c.run('a', work),
    ]);
    expect(results, [7, 7, 7]);
    expect(runs, 1);
  });

  test('different keys run independently', () async {
    final c = AsyncKeyedCoalescer();
    var runs = 0;
    Future<String> work(String id) async {
      runs++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return id;
    }

    final results = await Future.wait([
      c.run('x', () => work('x')),
      c.run('y', () => work('y')),
    ]);
    expect(results.toSet(), {'x', 'y'});
    expect(runs, 2);
  });

  test('after completion same key can run again', () async {
    final c = AsyncKeyedCoalescer();
    var runs = 0;
    await c.run('a', () async {
      runs++;
      return 1;
    });
    await c.run('a', () async {
      runs++;
      return 2;
    });
    expect(runs, 2);
  });

  test('shared failure propagates to all waiters', () async {
    final c = AsyncKeyedCoalescer();
    var runs = 0;
    Future<void> boom() async {
      runs++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      throw StateError('nope');
    }

    final f1 = c.run('a', boom);
    final f2 = c.run('a', boom);
    await expectLater(f1, throwsA(isA<StateError>()));
    await expectLater(f2, throwsA(isA<StateError>()));
    expect(runs, 1);
  });
}
