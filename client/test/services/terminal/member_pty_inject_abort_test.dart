import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/member_pty_inject_service.dart';
import 'package:teampilot/services/terminal/pty_automation_retry_queue.dart';

void main() {
  test('requestAbort marks seat aborted and clears pending', () {
    final retryQueue = PtyAutomationRetryQueue(
      retryIntervalMs: 0,
      maxAttempts: 1,
    );
    final service = MemberPtyInjectService(retryQueue: retryQueue);
    retryQueue.schedule(
      key: 's1:m1',
      sessionId: 's1',
      memberId: 'm1',
      text: 'pending',
    );

    service.requestAbort('s1', 'm1');

    expect(service.isAbortRequested('s1', 'm1'), isTrue);
    expect(service.hasPendingRetry('s1', 'm1'), isFalse);
  });
}
