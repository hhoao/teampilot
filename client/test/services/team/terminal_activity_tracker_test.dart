import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team/terminal_activity_tracker.dart';

void main() {
  const idle = Duration(milliseconds: 40);
  const bootQuiet = Duration(milliseconds: 40);

  test('isWorking false during boot burst, true after arm', () {
    final tracker = TerminalActivityTracker(idleAfter: idle);
    final now = DateTime.now();

    tracker.noteOutput(now);
    expect(tracker.isWorking, isFalse);
    tracker.reset();
    expect(tracker.isWorking, isFalse);

    // Boot output stamped in the past so arming does not wait on wall clock.
    tracker.markActive(now.subtract(idle));
    expect(tracker.isWorking, isFalse);
    tracker.markActive(now);
    expect(tracker.isWorking, isTrue);
  });

  test(
    'reading isWorking after reset does not arm before first PTY output',
    () {
      final tracker = TerminalActivityTracker(idleAfter: idle);
      tracker.reset();

      // Idle-watch polls isWorking while the shell is still silent after
      // onConfirmedRunning → reset(). That must not arm the tracker, or the
      // first startup banner is treated as a finished agent turn.
      expect(tracker.isWorking, isFalse);

      final now = DateTime.now();
      tracker.notePtyBytes(
        Uint8List.fromList('welcome\n'.codeUnits),
        now.subtract(idle),
      );
      expect(
        tracker.isWorking,
        isFalse,
        reason: 'boot quiet arm must not invent activity without post-arm PTY',
      );
    },
  );

  test('boot output burst does not show working until quiet', () {
    final tracker = TerminalActivityTracker(idleAfter: idle);
    final now = DateTime.now();
    tracker.noteOutput(now.subtract(idle));
    expect(tracker.isWorking, isFalse);
    tracker.noteOutput(now.subtract(idle));
    expect(tracker.isWorking, isFalse);
    tracker.markActive(now);
    expect(tracker.isWorking, isTrue);
  });

  test('isBootFrameReady after visible output and boot quiet', () {
    final tracker = TerminalActivityTracker(bootQuietAfter: bootQuiet);
    final frame = Uint8List.fromList('→ prompt\n'.codeUnits);
    final now = DateTime.now();

    tracker.reset();
    tracker.notePtyBytes(frame, now);
    expect(tracker.isBootFrameReady, isFalse);

    tracker.reset();
    tracker.notePtyBytes(frame, now.subtract(bootQuiet));
    expect(tracker.isBootFrameReady, isTrue);
  });

  test('isBootFrameReady latches and does not revert on later PTY churn', () {
    final tracker = TerminalActivityTracker(bootQuietAfter: bootQuiet);
    final now = DateTime.now();
    tracker.reset();
    tracker.notePtyBytes(
      Uint8List.fromList('→ prompt\n'.codeUnits),
      now.subtract(bootQuiet),
    );
    expect(tracker.isBootFrameReady, isTrue);

    tracker.notePtyBytes(
      Uint8List.fromList('→ prompt\nspinner\n'.codeUnits),
      now,
    );
    expect(tracker.isBootFrameReady, isTrue);
  });

  test(
    'isBootFrameReady stays false while visible fingerprint keeps changing',
    () {
      final tracker = TerminalActivityTracker(
        bootQuietAfter: const Duration(milliseconds: 80),
      );
      tracker.reset();
      final now = DateTime.now();
      for (var i = 0; i < 6; i++) {
        tracker.notePtyBytes(
          Uint8List.fromList('→ prompt spinner-$i\n'.codeUnits),
          now.add(Duration(milliseconds: i * 20)),
        );
        expect(
          tracker.isBootFrameReady,
          isFalse,
          reason: 'churn before quiet window must not latch (i=$i)',
        );
      }
      expect(tracker.bootFrameDebugSummary.contains('latched=false'), isTrue);
    },
  );

  test('isBootFrameReady waits for visible content not escape-only quiet', () {
    final tracker = TerminalActivityTracker(bootQuietAfter: bootQuiet);
    final now = DateTime.now();
    tracker.reset();
    // Alternate screen + clear — common cursor startup before TUI paints.
    tracker.notePtyBytes(
      Uint8List.fromList([0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x68]),
      now.subtract(bootQuiet),
    );
    tracker.notePtyBytes(
      Uint8List.fromList([0x1b, 0x5b, 0x32, 0x4a]),
      now.subtract(bootQuiet),
    );
    expect(tracker.isBootFrameReady, isFalse);

    tracker.notePtyBytes(
      Uint8List.fromList('Cursor Agent ready\n'.codeUnits),
      now.subtract(bootQuiet),
    );
    expect(tracker.isBootFrameReady, isTrue);
  });

  test('whitespace-only tail is not visible content', () {
    final tracker = TerminalActivityTracker(bootQuietAfter: bootQuiet);
    tracker.reset();
    tracker.notePtyBytes(
      Uint8List.fromList('     \n\t \n'.codeUnits),
      DateTime.now().subtract(bootQuiet),
    );
    expect(tracker.isBootFrameReady, isFalse);
  });

  test('isWorking false after idleAfter elapses', () {
    final tracker = TerminalActivityTracker(idleAfter: idle);
    final now = DateTime.now();
    tracker.reset();
    expect(tracker.isWorking, isFalse);
    tracker.markActive(now.subtract(idle)); // boot output → arms
    expect(tracker.isWorking, isFalse);
    tracker.markActive(now); // post-boot activity
    expect(tracker.isWorking, isTrue);
    tracker.markActive(now.subtract(idle + const Duration(milliseconds: 20)));
    expect(tracker.isWorking, isFalse);
  });

  test('identical consecutive PTY chunks do not refresh activity', () {
    final tracker = TerminalActivityTracker(idleAfter: idle);
    final now = DateTime.now();
    tracker.reset();
    tracker.markActive(now.subtract(idle));
    expect(tracker.isWorking, isFalse);

    final frame = Uint8List.fromList([0x1b, ...'[Kspinner'.codeUnits]);
    // First chunk already older than idleAfter → idle.
    tracker.notePtyBytes(
      frame,
      now.subtract(idle + const Duration(milliseconds: 10)),
    );
    expect(tracker.isWorking, isFalse);

    // Identical fresher chunk must not refresh activity.
    tracker.notePtyBytes(frame, now);
    expect(tracker.isWorking, isFalse);

    tracker.notePtyBytes(Uint8List.fromList([...frame, 0x21]), now);
    expect(tracker.isWorking, isTrue);
  });

  test('different escape bytes with same last line dedupe', () {
    const tail = 'Composer 2.5   Run Everything\n/path/feat/automations';
    final a = utf8.encode('\x1b[1;1H→ prompt\n$tail');
    final b = utf8.encode('\x1b[2;1H\x1b[K→ prompt\n$tail');

    expect(
      TerminalActivityTracker.visiblePtyFingerprintHash(a),
      TerminalActivityTracker.visiblePtyFingerprintHash(b),
    );

    final tracker = TerminalActivityTracker(idleAfter: idle);
    final now = DateTime.now();
    tracker.reset();
    tracker.markActive(now.subtract(idle));
    expect(tracker.isWorking, isFalse);

    tracker.notePtyBytes(
      a,
      now.subtract(idle + const Duration(milliseconds: 10)),
    );
    expect(tracker.isWorking, isFalse);

    // Same visible fingerprint must not refresh activity.
    tracker.notePtyBytes(b, now);
    expect(tracker.isWorking, isFalse);
  });

  test('alternating spinner lines with stable tail dedupe', () {
    const tail = 'Composer 2.5\n/home/user/proj · main';
    final spinnerA = '${'▀' * 20}\n';
    final spinnerB = "${"'" * 20}\n";
    final a = utf8.encode('\x1b[H→ Plan\n$spinnerA$tail');
    final b = utf8.encode('\x1b[2;1H\x1b[K→ Plan\n$spinnerB$tail');
    expect(a.length, isNot(equals(b.length)));

    expect(
      TerminalActivityTracker.visiblePtyFingerprintHash(a, tailLines: 2),
      TerminalActivityTracker.visiblePtyFingerprintHash(b, tailLines: 2),
    );
  });

  test('upper lines outside tail window do not change fingerprint', () {
    const stable = 'status row\n→ prompt line\ninput area';
    final a = utf8.encode('volatile spinner\nnoise above\n$stable');
    final b = utf8.encode('different noise\nother row\n$stable');

    expect(
      TerminalActivityTracker.visiblePtyFingerprintHash(a, tailLines: 3),
      TerminalActivityTracker.visiblePtyFingerprintHash(b, tailLines: 3),
    );
    expect(
      TerminalActivityTracker.visiblePtyFingerprintHash(a, tailLines: 3),
      isNot(
        equals(
          TerminalActivityTracker.visiblePtyFingerprintHash(
            utf8.encode('volatile spinner\nnoise above\n$stable\nchanged'),
            tailLines: 3,
          ),
        ),
      ),
    );
  });

  test('no PTY bytes after latch is not quiet', () {
    final tracker = TerminalActivityTracker(idleAfter: idle);
    tracker.reset();
    tracker.latchTurnQuietBaseline(
      DateTime.now().subtract(const Duration(milliseconds: 50)),
    );
    expect(tracker.isQuietAfterTurnPtyActivity, isFalse);
  });

  test('fingerprint unchanged for idleAfter ends turn quiet', () {
    final tracker = TerminalActivityTracker(idleAfter: idle);
    final now = DateTime.now();
    tracker.reset();
    tracker.latchTurnQuietBaseline(now);

    final frame = Uint8List.fromList('prompt idle\n'.codeUnits);
    tracker.notePtyBytes(frame, now);
    expect(tracker.isQuietAfterTurnPtyActivity, isFalse);

    // Unchanged fingerprint does not move stability baseline.
    tracker.notePtyBytes(frame, now.add(const Duration(milliseconds: 25)));
    expect(tracker.isQuietAfterTurnPtyActivity, isFalse);

    tracker.reset();
    tracker.latchTurnQuietBaseline(now.subtract(idle));
    tracker.notePtyBytes(frame, now.subtract(idle));
    expect(tracker.isQuietAfterTurnPtyActivity, isTrue);

    tracker.latchTurnQuietBaseline(now);
    expect(tracker.isQuietAfterTurnPtyActivity, isFalse);
  });

  test('deduped repaint ends quiet without new noteOutput', () {
    final tracker = TerminalActivityTracker(idleAfter: idle);
    final now = DateTime.now();
    tracker.reset();
    tracker.latchTurnQuietBaseline(now.subtract(idle));

    final frame = Uint8List.fromList([0x1b, ...'[Kspinner\nstill'.codeUnits]);
    tracker.notePtyBytes(frame, now.subtract(idle));
    tracker.notePtyBytes(frame, now);
    expect(tracker.isQuietAfterTurnPtyActivity, isTrue);
  });

  test('last line change updates fingerprint', () {
    final a = utf8.encode('→ idle\n▀▀▀\nline one');
    final b = utf8.encode('→ idle\n▀▀▀\nline two');
    expect(
      TerminalActivityTracker.visiblePtyFingerprintHash(a),
      isNot(equals(TerminalActivityTracker.visiblePtyFingerprintHash(b))),
    );
  });
}
