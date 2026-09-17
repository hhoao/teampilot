String shellMemberIdForHistory({
  required String sessionId,
  required String selectedMemberId,
}) {
  final mid = selectedMemberId.trim();
  return mid.isEmpty ? sessionId : mid;
}

String historySeatKey({
  required String sessionId,
  required String selectedMemberId,
}) {
  final shell = shellMemberIdForHistory(
    sessionId: sessionId,
    selectedMemberId: selectedMemberId,
  );
  return '$sessionId|$shell';
}

/// Hot seats may run live transcript refresh; warm keep-alive seats must stop it.
bool isHistorySeatHot({
  required bool routeActive,
  required bool isMemberRunning,
}) =>
    routeActive || isMemberRunning;

/// Whether cold→hot live refresh may skip the initial softReload.
///
/// Idle tab switches stay cheap. Leftover optimistic pending or an awaiting
/// turn must softReload once so transcript tips that landed while cold are
/// reconciled.
bool shouldSkipLiveRefreshInitialSoftReload({
  required bool hasOptimisticPending,
  required bool awaitingAssistant,
}) =>
    !hasOptimisticPending && !awaitingAssistant;
