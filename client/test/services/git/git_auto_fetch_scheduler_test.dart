import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/git/git_auto_fetch_scheduler.dart';

void main() {
  List<String> fetchedRoots = [];
  int fetchedCalls = 0;
  Completer<void>? gate;

  GitAutoFetchScheduler build({Duration interval = const Duration(minutes: 5)}) {
    fetchedRoots = [];
    fetchedCalls = 0;
    return GitAutoFetchScheduler(
      fetch: (dir) async {
        fetchedCalls++;
        fetchedRoots.add(dir);
        if (gate != null) await gate!.future;
      },
      onFetched: () {},
      interval: interval,
    );
  }

  test('start fetches immediately, then every interval', () {
    fakeAsync((async) {
      final scheduler = build()..start('/repo');
      expect(fetchedRoots, ['/repo']);
      async.elapse(const Duration(minutes: 5));
      expect(fetchedRoots, ['/repo', '/repo']);
      async.elapse(const Duration(minutes: 10));
      // Ticks fire at t=5, t=10 and t=15; elapse fires timers on the boundary.
      expect(fetchedRoots, ['/repo', '/repo', '/repo', '/repo']);
      scheduler.dispose();
    });
  });

  test('start with same running root is a no-op', () {
    fakeAsync((async) {
      final scheduler = build()..start('/repo');
      async.flushMicrotasks();
      scheduler.start('/repo'); // must not fetch again nor reset the timer
      expect(fetchedRoots, ['/repo']);
      async.elapse(const Duration(minutes: 5));
      expect(fetchedRoots, ['/repo', '/repo']);
      scheduler.dispose();
    });
  });

  test('start with a new root restarts and fetches immediately', () {
    fakeAsync((async) {
      final scheduler = build()..start('/a');
      async.flushMicrotasks();
      scheduler.start('/b');
      expect(fetchedRoots, ['/a', '/b']);
      async.elapse(const Duration(minutes: 5));
      expect(fetchedRoots, ['/a', '/b', '/b']);
      scheduler.dispose();
    });
  });

  test('tick while a fetch is in flight is skipped', () {
    fakeAsync((async) {
      gate = Completer<void>();
      final scheduler = build()..start('/repo');
      expect(fetchedCalls, 1);
      scheduler.tick();
      scheduler.tick();
      expect(fetchedCalls, 1, reason: 'in-flight fetch must not pile up');
      gate!.complete();
      async.flushMicrotasks();
      gate = null;
      scheduler.dispose();
    });
  });

  test('failures are swallowed and do not stop the schedule', () {
    fakeAsync((async) {
      var calls = 0;
      final scheduler = GitAutoFetchScheduler(
        fetch: (dir) async {
          calls++;
          // Must be an Exception (not an Error): the scheduler deliberately
          // lets Error crash tests — only Exception is swallowed.
          if (calls == 1) throw Exception('fetch failed');
        },
        onFetched: () {},
        interval: const Duration(minutes: 1),
      )..start('/repo');
      async.elapse(const Duration(minutes: 1));
      expect(calls, 2, reason: 'second tick must still run after a failure');
      scheduler.dispose();
    });
  });

  test('fetch times out after the configured timeout', () {
    fakeAsync((async) {
      gate = Completer<void>();
      var fetched = 0;
      final scheduler = GitAutoFetchScheduler(
        fetch: (dir) async {
          fetched++;
          await gate!.future;
        },
        onFetched: () => fail('onFetched must not fire on timeout'),
        interval: const Duration(minutes: 5),
        timeout: const Duration(seconds: 60),
      )..start('/repo');
      async.elapse(const Duration(seconds: 61));
      expect(fetched, 1);
      gate!.complete();
      gate = null;
      scheduler.dispose();
    });
  });

  test('stop halts fetching; start resumes with an immediate fetch', () {
    fakeAsync((async) {
      final scheduler = build()..start('/repo');
      async.flushMicrotasks();
      scheduler.stop();
      async.elapse(const Duration(minutes: 30));
      expect(fetchedRoots, ['/repo']);
      scheduler.start('/repo');
      expect(fetchedRoots, ['/repo', '/repo']);
      scheduler.dispose();
    });
  });
}
