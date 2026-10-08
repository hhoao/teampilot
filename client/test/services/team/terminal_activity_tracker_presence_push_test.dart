import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/runtime/pty/terminal_activity_tracker.dart';

/// Minimal visible-content PTY payload (a few printable glyphs).
Uint8List _visible(String s) => Uint8List.fromList(s.codeUnits);

/// Drives the tracker with FakeAsync's clock so the one-shot Timer and the
/// quiet/max-wait getters share a time source. Wall `DateTime.now` is *not*
/// advanced by `elapse` (see team_bus_routing_test).
void _withClock(
  void Function(FakeAsync async, DateTime Function() now) body,
) {
  fakeAsync((async) {
    body(async, async.getClock(DateTime.utc(2026, 1, 1)).now);
  });
}

TerminalActivityTracker _tracker({
  required DateTime Function() now,
  required Duration bootQuietAfter,
  required Duration bootMaxWait,
  void Function(bool bootReady)? onBootFrameChanged,
}) {
  return TerminalActivityTracker(
    bootQuietAfter: bootQuietAfter,
    bootMaxWait: bootMaxWait,
    onBootFrameChanged: onBootFrameChanged,
    now: now,
  );
}

void main() {
  test('boot-ready push shares the timer clock, not wall DateTime.now', () {
    _withClock((async, now) {
      final seen = <bool>[];
      final t = _tracker(
        now: now,
        bootQuietAfter: const Duration(seconds: 30),
        bootMaxWait: const Duration(minutes: 5),
        onBootFrameChanged: seen.add,
      );
      t.notePtyBytes(_visible('ready prompt'));
      async.elapse(const Duration(seconds: 30));
      expect(
        seen,
        [true],
        reason:
            'Timer fire must latch from the same clock it scheduled against; '
            're-reading DateTime.now() misses the quiet window under fakeAsync '
            'and under a starved CI isolate',
      );
    });
  });

  test('does not fire when no callback is wired', () {
    _withClock((async, now) {
      final t = _tracker(
        now: now,
        bootQuietAfter: const Duration(milliseconds: 50),
        bootMaxWait: const Duration(milliseconds: 400),
      );
      t.notePtyBytes(_visible('hello world'));
      async.elapse(const Duration(milliseconds: 50));
      expect(t.isBootFrameReady, isTrue);
    });
  });

  test('fires exactly once when the boot frame becomes ready', () {
    _withClock((async, now) {
      final seen = <bool>[];
      final t = _tracker(
        now: now,
        bootQuietAfter: const Duration(milliseconds: 50),
        bootMaxWait: const Duration(milliseconds: 400),
        onBootFrameChanged: seen.add,
      );
      t.notePtyBytes(_visible('ready prompt'));
      async.elapse(const Duration(milliseconds: 50));
      // Give a wrongly-armed second push time to surface before asserting dedupe.
      async.elapse(const Duration(milliseconds: 200));
      expect(seen, [
        true,
      ], reason: 'deduped: only the false→true flip is reported');
    });
  });

  test('bootMaxWait path fires without a quiet window', () {
    _withClock((async, now) {
      final seen = <bool>[];
      final t = _tracker(
        now: now,
        bootQuietAfter: const Duration(seconds: 30),
        bootMaxWait: const Duration(milliseconds: 400),
        onBootFrameChanged: seen.add,
      );
      for (var i = 0; i < 12 && seen.isEmpty; i++) {
        t.notePtyBytes(_visible('repaint $i'));
        async.elapse(const Duration(milliseconds: 50));
      }
      expect(seen, [true]);
    });
  });

  test('reset cancels the pending timer and clears the reported value', () {
    _withClock((async, now) {
      final seen = <bool>[];
      final t = _tracker(
        now: now,
        bootQuietAfter: const Duration(milliseconds: 50),
        bootMaxWait: const Duration(milliseconds: 200),
        onBootFrameChanged: seen.add,
      );
      t.notePtyBytes(_visible('booting'));
      t.reset();
      async.elapse(const Duration(milliseconds: 600));
      expect(seen, isEmpty, reason: 'reset must cancel the one-shot push');
    });
  });

  test('disposePresencePush stops further pushes', () {
    _withClock((async, now) {
      final seen = <bool>[];
      final t = _tracker(
        now: now,
        bootQuietAfter: const Duration(milliseconds: 50),
        bootMaxWait: const Duration(milliseconds: 200),
        onBootFrameChanged: seen.add,
      );
      t.notePtyBytes(_visible('booting'));
      t.disposePresencePush();
      async.elapse(const Duration(milliseconds: 600));
      expect(seen, isEmpty);
    });
  });

  test('listener attached after bytes arrived still gets the transition', () {
    _withClock((async, now) {
      final t = _tracker(
        now: now,
        bootQuietAfter: const Duration(milliseconds: 50),
        bootMaxWait: const Duration(milliseconds: 400),
      );
      t.notePtyBytes(_visible('late attach'));
      final seen = <bool>[];
      t.setBootFrameListener(seen.add);
      async.elapse(const Duration(milliseconds: 50));
      expect(seen, [true], reason: 'attach must arm the pending transition');
    });
  });

  test('detach then reattach (rebind) delivers the next transition', () {
    _withClock((async, now) {
      final first = <bool>[];
      final t = _tracker(
        now: now,
        bootQuietAfter: const Duration(milliseconds: 50),
        bootMaxWait: const Duration(milliseconds: 400),
        onBootFrameChanged: first.add,
      );
      t.notePtyBytes(_visible('boot one'));
      async.elapse(const Duration(milliseconds: 50));
      expect(first, [true]);

      t.disposePresencePush();

      final revived = <bool>[];
      t.setBootFrameListener(revived.add);
      t.reset();

      t.notePtyBytes(_visible('boot two'));
      async.elapse(const Duration(milliseconds: 50));
      expect(revived, [
        true,
      ], reason: 'rebind must revive the push on the reused tracker');
      expect(first, [true], reason: 'the detached listener stays detached');
    });
  });

  test('clearing the listener cancels a pending timer', () {
    _withClock((async, now) {
      final seen = <bool>[];
      final t = _tracker(
        now: now,
        bootQuietAfter: const Duration(milliseconds: 50),
        bootMaxWait: const Duration(milliseconds: 200),
        onBootFrameChanged: seen.add,
      );
      t.notePtyBytes(_visible('booting'));
      t.setBootFrameListener(null);
      async.elapse(const Duration(milliseconds: 600));
      expect(seen, isEmpty);
    });
  });
}
