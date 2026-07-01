import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team/terminal_activity_tracker.dart';

void main() {
  test('isWorking false during boot burst, true after arm', () {
    final tracker = TerminalActivityTracker(
      idleAfter: const Duration(seconds: 10),
    );
    tracker.noteOutput();
    expect(tracker.isWorking, isFalse);
    tracker.reset();
    expect(tracker.isWorking, isFalse);
    tracker.markActive();
    expect(tracker.isWorking, isTrue);
  });

  test('boot output burst does not show working until quiet', () async {
    final tracker = TerminalActivityTracker(
      idleAfter: const Duration(milliseconds: 40),
    );
    tracker.noteOutput();
    expect(tracker.isWorking, isFalse);
    tracker.noteOutput();
    expect(tracker.isWorking, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(tracker.isWorking, isFalse);
    tracker.markActive();
    expect(tracker.isWorking, isTrue);
  });

  test('isWorking false after idleAfter elapses', () async {
    final tracker = TerminalActivityTracker(
      idleAfter: const Duration(milliseconds: 40),
    );
    tracker.reset();
    expect(tracker.isWorking, isFalse);
    tracker.markActive();
    expect(tracker.isWorking, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(tracker.isWorking, isFalse);
  });

  test('identical consecutive PTY chunks do not refresh activity', () async {
    final tracker = TerminalActivityTracker(
      idleAfter: const Duration(milliseconds: 40),
    );
    tracker.reset();
    expect(tracker.isWorking, isFalse);
    tracker.markActive();

    final frame = Uint8List.fromList([0x1b, ...'[Kspinner'.codeUnits]);
    await Future<void>.delayed(const Duration(milliseconds: 25));
    tracker.notePtyBytes(frame);
    expect(tracker.isWorking, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 25));
    tracker.notePtyBytes(frame);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(tracker.isWorking, isFalse);

    tracker.notePtyBytes(Uint8List.fromList([...frame, 0x21]));
    expect(tracker.isWorking, isTrue);
  });

  test('different escape bytes with same last line dedupe', () async {
    const tail = 'Composer 2.5   Run Everything\n/path/feat/automations';
    final a = utf8.encode('\x1b[1;1H→ prompt\n$tail');
    final b = utf8.encode('\x1b[2;1H\x1b[K→ prompt\n$tail');

    expect(
      TerminalActivityTracker.visiblePtyFingerprintHash(a),
      TerminalActivityTracker.visiblePtyFingerprintHash(b),
    );

    final tracker = TerminalActivityTracker(
      idleAfter: const Duration(milliseconds: 40),
    );
    tracker.reset();
    expect(tracker.isWorking, isFalse);
    tracker.markActive();

    await Future<void>.delayed(const Duration(milliseconds: 25));
    tracker.notePtyBytes(a);
    expect(tracker.isWorking, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 25));
    tracker.notePtyBytes(b);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(tracker.isWorking, isFalse);
  });

  test('alternating spinner lines with stable tail dedupe', () async {
    const tail = 'Composer 2.5\n/home/user/proj · main';
    final spinnerA = '${'▀' * 20}\n';
    final spinnerB = "${"'" * 20}\n";
    final a = utf8.encode('\x1b[H→ Plan\n$spinnerA$tail');
    final b = utf8.encode('\x1b[2;1H\x1b[K→ Plan\n$spinnerB$tail');
    expect(a.length, isNot(equals(b.length)));

    expect(
      TerminalActivityTracker.visiblePtyFingerprintHash(a),
      TerminalActivityTracker.visiblePtyFingerprintHash(b),
    );
  });

  test('no PTY bytes after latch is not quiet', () {
    final tracker = TerminalActivityTracker(
      idleAfter: const Duration(milliseconds: 40),
    );
    tracker.reset();
    tracker.latchTurnQuietBaseline(
      DateTime.now().subtract(const Duration(milliseconds: 50)),
    );
    expect(tracker.isQuietAfterTurnPtyActivity, isFalse);
  });

  test('fingerprint unchanged for idleAfter ends turn quiet', () async {
    final tracker = TerminalActivityTracker(
      idleAfter: const Duration(milliseconds: 40),
    );
    tracker.reset();
    tracker.latchTurnQuietBaseline();

    final frame = Uint8List.fromList('prompt idle\n'.codeUnits);
    tracker.notePtyBytes(frame);
    expect(tracker.isQuietAfterTurnPtyActivity, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 25));
    tracker.notePtyBytes(frame);
    expect(tracker.isQuietAfterTurnPtyActivity, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(tracker.isQuietAfterTurnPtyActivity, isTrue);

    tracker.latchTurnQuietBaseline();
    expect(tracker.isQuietAfterTurnPtyActivity, isFalse);
  });

  test('deduped repaint ends quiet without new noteOutput', () async {
    final tracker = TerminalActivityTracker(
      idleAfter: const Duration(milliseconds: 40),
    );
    tracker.reset();
    tracker.latchTurnQuietBaseline();

    final frame = Uint8List.fromList([0x1b, ...'[Kspinner\nstill'.codeUnits]);
    tracker.notePtyBytes(frame);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    tracker.notePtyBytes(frame);
    await Future<void>.delayed(const Duration(milliseconds: 20));
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
