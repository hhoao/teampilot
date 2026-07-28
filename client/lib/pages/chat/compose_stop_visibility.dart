/// Whether the session history compose card should show Stop instead of Send.
bool shouldShowComposeStop({
  required bool memberWorking,
  required bool supportsTurnInterrupt,
  required bool composeTextEmpty,
}) =>
    memberWorking && supportsTurnInterrupt && composeTextEmpty;
