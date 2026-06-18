import 'package:path/path.dart' as p;

import '../io/filesystem.dart';
import 'app_storage.dart';

/// Canonical paths for TeamPilot workbench entities under `{teampilotRoot}/workspace/`.
///
/// Each workspace is a self-contained directory; deleting a workspace removes
/// manifest, profile, assets, sessions (metadata + bus + CLI runtime).
///
/// ```
/// workspace/workspaces/{workspaceId}/
///   manifest.json       # Workspace
///   profile.json        # PersonalIdentity (personal workspaces)
///   assets/icon.*       # custom workspace icon
///   config/             # workspace-level CLI overrides
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

  String get workspacesDir => _ctx.join(workspaceDir, 'workspaces');

  String workspaceDir(String workspaceId) =>
      _ctx.join(workspacesDir, workspaceId.trim());

  String manifestFile(String workspaceId) =>
      _ctx.join(workspaceDir(workspaceId), 'manifest.json');

  String profileFile(String workspaceId) =>
      _ctx.join(workspaceDir(workspaceId), 'profile.json');

  String assetsDir(String workspaceId) =>
      _ctx.join(workspaceDir(workspaceId), 'assets');

  String workspaceConfigDir(String workspaceId) =>
      _ctx.join(workspaceDir(workspaceId), 'config');

  String workspaceConfigToolDir(String workspaceId, String tool) =>
      _ctx.join(workspaceConfigDir(workspaceId), tool.trim());

  String workspaceConfigPluginsDir(String workspaceId) => _ctx.join(
    workspaceConfigToolDir(workspaceId, 'flashskyai'),
    'plugins',
  );

  String workspaceConfigMcpDir(String workspaceId) =>
      _ctx.join(workspaceConfigDir(workspaceId), 'mcp');

  String workspaceConfigMcpServersFile(String workspaceId) =>
      _ctx.join(workspaceConfigMcpDir(workspaceId), 'servers.json');

  String sessionsDir(String workspaceId) =>
      _ctx.join(workspaceDir(workspaceId), 'sessions');

  String sessionDir(String workspaceId, String sessionId) =>
      _ctx.join(sessionsDir(workspaceId), sessionId.trim());

  String sessionFile(String workspaceId, String sessionId) =>
      _ctx.join(sessionDir(workspaceId, sessionId), 'session.json');

  String busDir(String workspaceId, String sessionId) =>
      _ctx.join(sessionDir(workspaceId, sessionId), 'bus');

  String busMailDir(String workspaceId, String sessionId) =>
      _ctx.join(busDir(workspaceId, sessionId), 'mail');

  String busMailFile(String workspaceId, String sessionId, String memberId) =>
      _ctx.join(busMailDir(workspaceId, sessionId), '${memberId.trim()}.jsonl');

  String busTasksDir(String workspaceId, String sessionId) =>
      _ctx.join(busDir(workspaceId, sessionId), 'tasks');

  String busTasksFile(String workspaceId, String sessionId) =>
      _ctx.join(busTasksDir(workspaceId, sessionId), 'tasks.jsonl');

  String sessionRuntimeDir(String workspaceId, String sessionId) =>
      _ctx.join(sessionDir(workspaceId, sessionId), 'runtime');

  /// PTY CONFIG_DIR for [tool]. Pass [memberId] in mixed team mode.
  String sessionRuntimeToolDir(
    String workspaceId,
    String sessionId,
    String tool, {
    String? memberId,
  }) {
    final trimmedMember = memberId?.trim() ?? '';
    if (trimmedMember.isNotEmpty) {
      return _ctx.join(
        sessionRuntimeDir(workspaceId, sessionId),
        trimmedMember,
        tool.trim(),
      );
    }
    return _ctx.join(sessionRuntimeDir(workspaceId, sessionId), tool.trim());
  }

  String sessionRuntimePluginsDir(
    String workspaceId,
    String sessionId,
    String tool, {
    String? memberId,
  }) =>
      _ctx.join(
        sessionRuntimeToolDir(
          workspaceId,
          sessionId,
          tool,
          memberId: memberId,
        ),
        'plugins',
      );
}
