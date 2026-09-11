import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team/terminal_activity_tracker.dart';

/// Minimal visible-content PTY payload (a few printable glyphs).
Uint8List _visible(String s) => Uint8List.fromList(s.codeUnits);

/// Polls until [done] holds, or [timeout] elapses.
///
/// These tests drive the tracker's real one-shot `Timer` against the real
/// wall clock, so a fixed `Future.delayed` is load-sensitive: under a busy
/// machine (a full parallel suite run) the callback can land after the sleep
/// and the assertion misses a transition that did happen. Waiting on the
/// predicate up to a generous deadline makes the positive cases deterministic
/// without weakening them — if the transition never arrives, the deadline
/// passes and the following `expect` still fails.
Future<void> _waitFor(
  bool Function() done, {
  Duration timeout = const Duration(seconds: 10),
  Duration poll = const Duration(milliseconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(poll);
  }
}

void main() {
  test('does not fire when no callback is wired', () async {
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 50),
    );
    t.notePtyBytes(_visible('hello world'));
    await _waitFor(() => t.isBootFrameReady);
    // No callback wired → nothing to assert beyond "no crash", but the boot
    // getter must still behave exactly as before.
    expect(t.isBootFrameReady, isTrue);
  });

  test('fires exactly once when the boot frame becomes ready', () async {
    final seen = <bool>[];
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 50),
      bootMaxWait: const Duration(milliseconds: 400),
      onBootFrameChanged: seen.add,
    );
    t.notePtyBytes(_visible('ready prompt'));
    await _waitFor(() => seen.isNotEmpty);
    // Give a wrongly-armed second push time to surface before asserting dedupe.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(seen, [true], reason: 'deduped: only the false→true flip is reported');
  });

  test('bootMaxWait path fires without a quiet window', () async {
    final seen = <bool>[];
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(seconds: 30), // never quiet in time
      bootMaxWait: const Duration(milliseconds: 400),
      onBootFrameChanged: seen.add,
    );
    // Keep repainting so the quiet window never elapses.
    for (var i = 0; i < 12 && seen.isEmpty; i++) {
      t.notePtyBytes(_visible('repaint $i'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(seen, [true]);
  });

  test('reset cancels the pending timer and clears the reported value', () async {
    final seen = <bool>[];
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 50),
      bootMaxWait: const Duration(milliseconds: 200),
      onBootFrameChanged: seen.add,
    );
    t.notePtyBytes(_visible('booting'));
    t.reset();
    // Negative case: wait well past bootMaxWait so a leaked timer would fire.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(seen, isEmpty, reason: 'reset must cancel the one-shot push');
  });

  test('disposePresencePush stops further pushes', () async {
    final seen = <bool>[];
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 50),
      bootMaxWait: const Duration(milliseconds: 200),
      onBootFrameChanged: seen.add,
    );
    t.notePtyBytes(_visible('booting'));
    t.disposePresencePush();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(seen, isEmpty);
  });

  test('listener attached after bytes arrived still gets the transition',
      () async {
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 50),
      bootMaxWait: const Duration(milliseconds: 400),
    );
    // Bytes arrive with no listener wired — no timer is armed.
    t.notePtyBytes(_visible('late attach'));
    final seen = <bool>[];
    t.setBootFrameListener(seen.add);
    await _waitFor(() => seen.isNotEmpty);
    expect(seen, [true], reason: 'attach must arm the pending transition');
  });

  test('detach then reattach (rebind) delivers the next transition', () async {
    final first = <bool>[];
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 50),
      bootMaxWait: const Duration(milliseconds: 400),
      onBootFrameChanged: first.add,
    );
    t.notePtyBytes(_visible('boot one'));
    await _waitFor(() => first.isNotEmpty);
    expect(first, [true]);

    // Unbind for the rebind cycle — TerminalSession keeps this same tracker.
    t.disposePresencePush();

    final revived = <bool>[];
    t.setBootFrameListener(revived.add);
    // A rebind re-runs the launch confirm path, which resets the tracker.
    t.reset();

    t.notePtyBytes(_visible('boot two'));
    await _waitFor(() => revived.isNotEmpty);
    expect(revived, [true],
        reason: 'rebind must revive the push on the reused tracker');
    expect(first, [true], reason: 'the detached listener stays detached');
  });

  test('clearing the listener cancels a pending timer', () async {
    final seen = <bool>[];
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 50),
      bootMaxWait: const Duration(milliseconds: 200),
      onBootFrameChanged: seen.add,
    );
    t.notePtyBytes(_visible('booting'));
    t.setBootFrameListener(null);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(seen, isEmpty);
  });
}
