import '../../services/follow_up/follow_up_submit_gate.dart';

/// History compose submit gate — thin wrapper for tests and [SessionChatView].
FollowUpSubmitAction resolveHistoryComposeSubmitAction({
  required bool permissionWaiting,
  required bool memberWorking,
  required String trimmedText,
  required bool supportsTurnInterrupt,
}) =>
    resolveFollowUpSubmitAction(
      permissionWaiting: permissionWaiting,
      memberWorking: memberWorking,
      composeTextEmpty: trimmedText.isEmpty,
      supportsTurnInterrupt: supportsTurnInterrupt,
    );

/// Routes enqueue vs deliver; stop/block are no-ops on submit (Stop uses onStop).
void dispatchHistoryComposeSubmit({
  required FollowUpSubmitAction action,
  required String text,
  required void Function(String text) onEnqueue,
  required void Function(String text) onDeliver,
}) {
  switch (action) {
    case FollowUpSubmitAction.enqueue:
      onEnqueue(text);
    case FollowUpSubmitAction.deliver:
      onDeliver(text);
    case FollowUpSubmitAction.block:
    case FollowUpSubmitAction.stop:
      break;
  }
}
