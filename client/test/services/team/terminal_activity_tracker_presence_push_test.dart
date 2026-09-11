import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team/terminal_activity_tracker.dart';

/// Minimal visible-content PTY payload (a few printable glyphs + CR/LF).
Uint8List _visible(String s) => Uint8List.fromList(s.codeUnits);

void main() {
  test('does not fire when no callback is wired', () async {
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 20),
    );
    t.notePtyBytes(_visible('hello world'));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    // No callback wired → nothing to assert beyond "no crash", but the boot
    // getter must still behave exactly as before.
    expect(t.isBootFrameReady, isTrue);
  });

  test('fires exactly once when the boot frame becomes ready', () async {
    final seen = <bool>[];
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 20),
      bootMaxWait: const Duration(milliseconds: 200),
      onBootFrameChanged: seen.add,
    );
    t.notePtyBytes(_visible('ready prompt'));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(seen, [true], reason: 'deduped: only the false→true flip is reported');
  });

  test('bootMaxWait path fires without a quiet window', () async {
    final seen = <bool>[];
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(seconds: 30), // never quiet in time
      bootMaxWait: const Duration(milliseconds: 60),
      onBootFrameChanged: seen.add,
    );
    // Keep repainting so the quiet window never elapses.
    for (var i = 0; i < 6; i++) {
      t.notePtyBytes(_visible('repaint $i'));
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    expect(seen, [true]);
  });

  test('reset cancels the pending timer and clears the reported value', () async {
    final seen = <bool>[];
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 20),
      bootMaxWait: const Duration(milliseconds: 80),
      onBootFrameChanged: seen.add,
    );
    t.notePtyBytes(_visible('booting'));
    t.reset();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(seen, isEmpty, reason: 'reset must cancel the one-shot push');
  });

  test('disposePresencePush stops further pushes', () async {
    final seen = <bool>[];
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 20),
      bootMaxWait: const Duration(milliseconds: 60),
      onBootFrameChanged: seen.add,
    );
    t.notePtyBytes(_visible('booting'));
    t.disposePresencePush();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(seen, isEmpty);
  });

  test('listener attached after bytes arrived still gets the transition',
      () async {
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 20),
      bootMaxWait: const Duration(milliseconds: 80),
    );
    // Bytes arrive with no listener wired — no timer is armed.
    t.notePtyBytes(_visible('late attach'));
    final seen = <bool>[];
    t.setBootFrameListener(seen.add);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(seen, [true], reason: 'attach must arm the pending transition');
  });

  test('detach then reattach (rebind) delivers the next transition', () async {
    final first = <bool>[];
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 20),
      bootMaxWait: const Duration(milliseconds: 80),
      onBootFrameChanged: first.add,
    );
    t.notePtyBytes(_visible('boot one'));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(first, [true]);

    // Unbind for the rebind cycle — TerminalSession keeps this same tracker.
    t.disposePresencePush();

    final revived = <bool>[];
    t.setBootFrameListener(revived.add);
    // A rebind re-runs the launch confirm path, which resets the tracker.
    t.reset();

    t.notePtyBytes(_visible('boot two'));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(revived, [true],
        reason: 'rebind must revive the push on the reused tracker');
    expect(first, [true], reason: 'the detached listener stays detached');
  });

  test('clearing the listener cancels a pending timer', () async {
    final seen = <bool>[];
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 20),
      bootMaxWait: const Duration(milliseconds: 60),
      onBootFrameChanged: seen.add,
    );
    t.notePtyBytes(_visible('booting'));
    t.setBootFrameListener(null);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(seen, isEmpty);
  });
}
