/// Kill routing for Resource Manager leaf bindings.
///
/// Chat leaves must use [disconnectMemberShell] (sessionId + memberId). Do not
/// call active-tab `ChatCubit.disconnectSession()` — that only targets the
/// selected member of the active chat tab.
Future<void> killResourceManagerBinding({
  required String bindingKey,
  required Future<void> Function(String sessionId, String memberId)
      disconnectMemberShell,
  required Future<void> Function(String workspaceId, String entryId)
      killWorkspaceShell,
}) async {
  if (bindingKey.startsWith('chat:')) {
    final rest = bindingKey.substring('chat:'.length);
    final sep = rest.indexOf(':');
    if (sep <= 0 || sep >= rest.length - 1) return;
    final sessionId = rest.substring(0, sep);
    final memberId = rest.substring(sep + 1);
    await disconnectMemberShell(sessionId, memberId);
    return;
  }

  if (bindingKey.startsWith('shell:')) {
    final rest = bindingKey.substring('shell:'.length);
    final sep = rest.indexOf(':');
    if (sep <= 0 || sep >= rest.length - 1) return;
    final workspaceId = rest.substring(0, sep);
    final entryId = rest.substring(sep + 1);
    await killWorkspaceShell(workspaceId, entryId);
  }
}
