abstract interface class TeamGenerationRecoveryPort {
  Future<void> recoverAll(Iterable<String> workspaceIds);
  Future<void> recoverWorkspace(String workspaceId);
}
