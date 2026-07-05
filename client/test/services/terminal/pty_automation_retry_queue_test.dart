import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/pty_automation_retry_queue.dart';

void main() {
  test('schedule bumps attempt and due returns ready ticks', () {
    var now = 0;
    final queue = PtyAutomationRetryQueue(
      retryIntervalMs: 5000,
      maxAttempts: 3,
      nowMs: () => now,
    );
    const key = 'sess:member';

    expect(
      queue.schedule(
        key: key,
        sessionId: 'sess',
        memberId: 'member',
        text: 'hello',
      ),
      isTrue,
    );

    expect(queue.due(blocked: (_) => false), isEmpty);

    now = 5000;
    final ticks = queue.due(blocked: (_) => false);
    expect(ticks, hasLength(1));
    expect(ticks.single.attempt, 1);
    expect(ticks.single.text, 'hello');
    expect(queue.isPending(key), isFalse);
  });

  test('schedule returns false when max attempts exceeded', () {
    final queue = PtyAutomationRetryQueue(
      retryIntervalMs: 0,
      maxAttempts: 2,
    );
    const key = 'k';
    expect(
      queue.schedule(
        key: key,
        sessionId: 's',
        memberId: 'm',
        text: 't',
      ),
      isTrue,
    );
    expect(
      queue.schedule(
        key: key,
        sessionId: 's',
        memberId: 'm',
        text: 't',
      ),
      isTrue,
    );
    expect(
      queue.schedule(
        key: key,
        sessionId: 's',
        memberId: 'm',
        text: 't',
      ),
      isFalse,
    );
    expect(queue.isPending(key), isFalse);
  });

  test('clear removes pending entry', () {
    final queue = PtyAutomationRetryQueue(retryIntervalMs: 0, maxAttempts: 5);
    queue.schedule(
      key: 'k',
      sessionId: 's',
      memberId: 'm',
      text: 't',
    );
    queue.clear('k');
    expect(queue.due(blocked: (_) => false), isEmpty);
  });
}
