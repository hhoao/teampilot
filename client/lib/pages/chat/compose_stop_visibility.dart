/// Whether the session history compose card should show Stop instead of Send.
///
/// An edited-message resend is cancelled from the same button: while it runs
/// the seat is stopped/relaunching, so none of the turn predicates hold.
bool shouldShowComposeStop({
  required bool memberWorking,
  required bool supportsTurnInterrupt,
  required bool composeTextEmpty,
  bool userStoppedTurn = false,
  bool turnStarting = false,
  bool editOperationInFlight = false,
}) {
  if (editOperationInFlight) return !userStoppedTurn;
  return (memberWorking || turnStarting) &&
      supportsTurnInterrupt &&
      composeTextEmpty &&
      !userStoppedTurn;
}
