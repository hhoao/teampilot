/// Default idle time before a disconnected session is closed.
const acpProxyIdleTimeout = Duration(minutes: 30);

/// Whether the idle clock should advance.
///
/// True only when the phone is gone, no turn is in progress, and no
/// permission request is still waiting. A running turn or an open permission
/// must not be reaped.
bool shouldRunIdleTimer({
  required bool phoneConnected,
  required bool turnInProgress,
  required bool permissionPending,
}) {
  return !phoneConnected && !turnInProgress && !permissionPending;
}
