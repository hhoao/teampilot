import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/prompt_submit_ack_tracker.dart';

void main() {
  test('注册后 ACK 命中完成 future', () async {
    final tracker = PromptSubmitAckTracker();
    final f = tracker.register(
      sessionId: 's1', memberId: 'm1', text: '1',
    );
    expect(tracker.tryAck(sessionId: 's1', memberId: 'm1', text: '1'), isTrue);
    expect(await f, isTrue);
  });

  test('文本不匹配不命中', () async {
    final tracker = PromptSubmitAckTracker();
    final f = tracker.register(
      sessionId: 's1', memberId: 'm1', text: '1',
    );
    expect(tracker.tryAck(sessionId: 's1', memberId: 'm1', text: '其他'), isFalse);
    expect(await f.timeout(const Duration(milliseconds: 50),
        onTimeout: () => false), isFalse);
  });

  test('clear 后不再命中', () async {
    final tracker = PromptSubmitAckTracker();
    tracker.register(sessionId: 's1', memberId: 'm1', text: '1');
    tracker.clear('s1', 'm1');
    expect(tracker.tryAck(sessionId: 's1', memberId: 'm1', text: '1'), isFalse);
  });

  test('多 seat 互不干扰', () async {
    final tracker = PromptSubmitAckTracker();
    final fa = tracker.register(sessionId: 's1', memberId: 'm1', text: '1');
    final fb = tracker.register(sessionId: 's2', memberId: 'm1', text: '1');
    expect(tracker.tryAck(sessionId: 's2', memberId: 'm1', text: '1'), isTrue);
    expect(await fb, isTrue);
    expect(tracker.tryAck(sessionId: 's1', memberId: 'm1', text: '1'), isTrue);
    expect(await fa, isTrue);
  });
}
