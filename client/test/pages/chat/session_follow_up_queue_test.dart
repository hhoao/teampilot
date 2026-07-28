import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/session_follow_up_compose_submit.dart';
import 'package:teampilot/services/follow_up/follow_up_submit_gate.dart';

void main() {
  test('working member with text enqueues without deliver', () {
    var enqueued = false;
    var delivered = false;

    final action = resolveHistoryComposeSubmitAction(
      permissionWaiting: false,
      memberWorking: true,
      trimmedText: 'follow up',
      supportsTurnInterrupt: true,
    );
    expect(action, FollowUpSubmitAction.enqueue);

    dispatchHistoryComposeSubmit(
      action: action,
      text: 'follow up',
      onEnqueue: (_) => enqueued = true,
      onDeliver: (_) => delivered = true,
    );

    expect(enqueued, isTrue);
    expect(delivered, isFalse);
  });

  test('idle member with text delivers without enqueue', () {
    var enqueued = false;
    var delivered = false;

    final action = resolveHistoryComposeSubmitAction(
      permissionWaiting: false,
      memberWorking: false,
      trimmedText: 'hello',
      supportsTurnInterrupt: true,
    );
    expect(action, FollowUpSubmitAction.deliver);

    dispatchHistoryComposeSubmit(
      action: action,
      text: 'hello',
      onEnqueue: (_) => enqueued = true,
      onDeliver: (_) => delivered = true,
    );

    expect(enqueued, isFalse);
    expect(delivered, isTrue);
  });

  test('working member with empty text does not deliver on submit', () {
    var delivered = false;

    final action = resolveHistoryComposeSubmitAction(
      permissionWaiting: false,
      memberWorking: true,
      trimmedText: '',
      supportsTurnInterrupt: true,
    );
    expect(action, FollowUpSubmitAction.stop);

    dispatchHistoryComposeSubmit(
      action: action,
      text: '',
      onEnqueue: (_) {},
      onDeliver: (_) => delivered = true,
    );

    expect(delivered, isFalse);
  });
}
