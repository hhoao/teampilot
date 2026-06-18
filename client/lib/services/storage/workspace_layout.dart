import 'package:path/path.dart' as p;

import '../io/filesystem.dart';
import 'app_storage.dart';

/// Canonical paths for TeamPilot workbench entities under `{teampilotRoot}/workspace/`.
///
/// Each project is a self-contained directory; deleting a project removes
/// manifest, profile, assets, sessions (metadata + bus + CLI runtime).
///
/// ```
/// workspace/projects/{projectId}/
///   manifest.json       # Workspace
///   profile.json        # PersonalIdentity (personal projects)
///   assets/icon.*       # custom project icon
///   config/             # project-level CLI overrides
///     mcp/servers.json
///     {tool}/plugins/
///   sessions/{sessionId}/
///     session.json
///     bus/mail/{memberId}.jsonl
///     bus/tasks.jsonl
///     runtime/{tool}/           # native / personal PTY CONFIG_DIR
///     runtime/{memberId}/{tool}/ # mixed-mode per-member CONFIG_DIR
/// ```
class WorkspaceLayout {
  WorkspaceLayout({required this.teampilotRoot, Filesystem? fs})
    : _fs = fs ?? AppStorage.fs;

  final String teampilotRoot;
  final Filesystem _fs;

  p.Context get _ctx => _fs.pathContext;

  String get workspaceDir => _ctx.join(teampilotRoot, 'workspace');

  String get projectsDir => _ctx.join(workspaceDir, 'projects');

  String projectDir(String projectId) =>
      _ctx.join(projectsDir, projectId.trim());

  String manifestFile(String projectId) =>
      _ctx.join(projectDir(projectId), 'manifest.json');

  String profileFile(String projectId) =>
      _ctx.join(projectDir(projectId), 'profile.json');

  String assetsDir(String projectId) =>
      _ctx.join(projectDir(projectId), 'assets');

  String projectConfigDir(String projectId) =>
      _ctx.join(projectDir(projectId), 'config');

  String projectConfigToolDir(String projectId, String tool) =>
      _ctx.join(projectConfigDir(projectId), tool.trim());

  String projectConfigPluginsDir(String projectId) => _ctx.join(
    projectConfigToolDir(projectId, 'flashskyai'),
    'plugins',
  );

  String projectConfigMcpDir(String projectId) =>
      _ctx.join(projectConfigDir(projectId), 'mcp');

  String projectConfigMcpServersFile(String projectId) =>
      _ctx.join(projectConfigMcpDir(projectId), 'servers.json');

  String sessionsDir(String projectId) =>
      _ctx.join(projectDir(projectId), 'sessions');

  String sessionDir(String projectId, String sessionId) =>
      _ctx.join(sessionsDir(projectId), sessionId.trim());

  String sessionFile(String projectId, String sessionId) =>
      _ctx.join(sessionDir(projectId, sessionId), 'session.json');

  String busDir(String projectId, String sessionId) =>
      _ctx.join(sessionDir(projectId, sessionId), 'bus');

  String busMailDir(String projectId, String sessionId) =>
      _ctx.join(busDir(projectId, sessionId), 'mail');

  String busMailFile(String projectId, String sessionId, String memberId) =>
      _ctx.join(busMailDir(projectId, sessionId), '${memberId.trim()}.jsonl');

  String busTasksDir(String projectId, String sessionId) =>
      _ctx.join(busDir(projectId, sessionId), 'tasks');

  String busTasksFile(String projectId, String sessionId) =>
      _ctx.join(busTasksDir(projectId, sessionId), 'tasks.jsonl');

  String sessionRuntimeDir(String projectId, String sessionId) =>
      _ctx.join(sessionDir(projectId, sessionId), 'runtime');

  /// PTY CONFIG_DIR for [tool]. Pass [memberId] in mixed team mode.
  String sessionRuntimeToolDir(
    String projectId,
    String sessionId,
    String tool, {
    String? memberId,
  }) {
    final trimmedMember = memberId?.trim() ?? '';
    if (trimmedMember.isNotEmpty) {
      return _ctx.join(
        sessionRuntimeDir(projectId, sessionId),
        trimmedMember,
        tool.trim(),
      );
    }
    return _ctx.join(sessionRuntimeDir(projectId, sessionId), tool.trim());
  }

  String sessionRuntimePluginsDir(
    String projectId,
    String sessionId,
    String tool, {
    String? memberId,
  }) =>
      _ctx.join(
        sessionRuntimeToolDir(
          projectId,
          sessionId,
          tool,
          memberId: memberId,
        ),
        'plugins',
      );
}
