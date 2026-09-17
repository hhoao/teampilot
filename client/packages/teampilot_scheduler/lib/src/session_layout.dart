import 'package:path/path.dart' as p;

/// Canonical session-plane paths under [teampilotRoot].
///
/// Formulas match [docs/workspace-storage-layout.md] / client
/// `WorkspaceLayout` / `RuntimeLayout`.
final class SessionLayout {
  SessionLayout({required this.teampilotRoot, required this.pathContext});

  final String teampilotRoot;
  final p.Context pathContext;

  String get workspaceRootDir => pathContext.join(teampilotRoot, 'workspace');

  String get workspacesDir => pathContext.join(workspaceRootDir, 'workspaces');

  String workspaceDir(String workspaceId) =>
      pathContext.join(workspacesDir, workspaceId.trim());

  String workspaceConfigToolDir(String workspaceId, String tool) =>
      pathContext.join(workspaceDir(workspaceId), 'config', tool.trim());

  String sessionDir(String workspaceId, String sessionId) =>
      pathContext.join(workspaceDir(workspaceId), 'sessions', sessionId.trim());

  String sessionRuntimeDir(String workspaceId, String sessionId) =>
      pathContext.join(sessionDir(workspaceId, sessionId), 'runtime');

  String sessionRuntimeToolDir(
    String workspaceId,
    String sessionId,
    String tool, {
    String? memberId,
  }) {
    final trimmedMember = memberId?.trim() ?? '';
    if (trimmedMember.isNotEmpty) {
      return pathContext.join(
        sessionRuntimeDir(workspaceId, sessionId),
        trimmedMember,
        tool.trim(),
      );
    }
    return pathContext.join(
      sessionRuntimeDir(workspaceId, sessionId),
      tool.trim(),
    );
  }

  String get cliDefaultsDir => pathContext.join(teampilotRoot, 'cli-defaults');

  String get identitiesRuntimeDir =>
      pathContext.join(teampilotRoot, 'identities-runtime');

  String identityToolDir(String profileId, String tool) =>
      pathContext.join(identitiesRuntimeDir, profileId.trim(), tool.trim());
}
