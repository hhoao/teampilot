enum FollowUpSubmitAction { deliver, enqueue, stop, block }

FollowUpSubmitAction resolveFollowUpSubmitAction({
  required bool permissionWaiting,
  required bool memberWorking,
  required bool composeTextEmpty,
  required bool supportsTurnInterrupt,
}) {
  if (permissionWaiting) return FollowUpSubmitAction.block;
  if (!memberWorking) {
    return composeTextEmpty
        ? FollowUpSubmitAction.block
        : FollowUpSubmitAction.deliver;
  }
  if (!composeTextEmpty) return FollowUpSubmitAction.enqueue;
  if (supportsTurnInterrupt) return FollowUpSubmitAction.stop;
  return FollowUpSubmitAction.block;
}
