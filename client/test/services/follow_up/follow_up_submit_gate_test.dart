import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/follow_up/follow_up_submit_gate.dart';

void main() {
  test('permission waiting blocks', () {
    expect(
      resolveFollowUpSubmitAction(
        permissionWaiting: true,
        memberWorking: false,
        composeTextEmpty: false,
        supportsTurnInterrupt: true,
      ),
      FollowUpSubmitAction.block,
    );
  });

  test('idle delivers; busy+text enqueues; busy+empty stops when supported', () {
    expect(
      resolveFollowUpSubmitAction(
        permissionWaiting: false,
        memberWorking: false,
        composeTextEmpty: false,
        supportsTurnInterrupt: true,
      ),
      FollowUpSubmitAction.deliver,
    );
    expect(
      resolveFollowUpSubmitAction(
        permissionWaiting: false,
        memberWorking: true,
        composeTextEmpty: false,
        supportsTurnInterrupt: true,
      ),
      FollowUpSubmitAction.enqueue,
    );
    expect(
      resolveFollowUpSubmitAction(
        permissionWaiting: false,
        memberWorking: true,
        composeTextEmpty: true,
        supportsTurnInterrupt: true,
      ),
      FollowUpSubmitAction.stop,
    );
    expect(
      resolveFollowUpSubmitAction(
        permissionWaiting: false,
        memberWorking: true,
        composeTextEmpty: true,
        supportsTurnInterrupt: false,
      ),
      FollowUpSubmitAction.block,
    );
  });
}
