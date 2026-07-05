import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/member_pty_inject_service.dart';
import 'package:teampilot/services/terminal/pty_automation_retry_queue.dart';

void main() {
  test('tickRetries shouldSkip clears pending without onTick', () {
    var now = 0;
    final queue = PtyAutomationRetryQueue(
      retryIntervalMs: 0,
      maxAttempts: 5,
      nowMs: () => now,
    );
    final inject = MemberPtyInjectService(retryQueue: queue);
    const key = 'sess:worker';
    queue.schedule(
      key: key,
      sessionId: 'sess',
      memberId: 'worker',
      text: 'stale doorbell',
    );

    var ticked = 0;
    inject.tickRetries(
      shouldSkip: (_) => true,
      onTick: (_) => ticked++,
    );

    expect(ticked, 0);
    expect(queue.isPending(key), isFalse);
  });

  test('clearPending removes scheduled retry', () {
    final queue = PtyAutomationRetryQueue(retryIntervalMs: 0, maxAttempts: 5);
    final inject = MemberPtyInjectService(retryQueue: queue);
    const key = 'sess:worker';
    queue.schedule(
      key: key,
      sessionId: 'sess',
      memberId: 'worker',
      text: 'hello',
    );

    inject.clearPending('sess', 'worker');

    expect(queue.isPending(key), isFalse);
  });
}
