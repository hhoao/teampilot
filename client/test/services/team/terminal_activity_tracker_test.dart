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
}
