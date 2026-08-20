import 'package:path/path.dart' as p;

import '../io/filesystem.dart';
import 'app_storage.dart';

/// Canonical paths for TeamPilot workbench entities under `{teampilotRoot}/workspace/`.
///
/// Each workspace is a self-contained directory; deleting a workspace removes
/// manifest, profile, assets, sessions (metadata + bus + CLI runtime).
///
/// ```
/// workspace/workspaces-index.json   # derived startup snapshot (manifest + session dir ids)
/// workspace/workspaces/{workspaceId}/
///   manifest.json       # Workspace
///   project-config.json # Project-scoped skills/plugins/mcp/extensions
///   profile.json        # legacy; unused after identity-model removal
///   assets/icon.*       # custom workspace icon
///   config/             # workspace-level CLI overrides
///     mcp/servers.json
///     {tool}/plugins/
///   automations/automations.json  # rules + run history for workspace
///   sessions/{sessionId}/
///     session.json
///     bus/mail/{memberId}.jsonl
///     bus/tasks.jsonl
///     runtime/{tool}/           # native / personal PTY CONFIG_DIR
///     runtime/{memberId}/{tool}/ # mixed-mode per-member CONFIG_DIR
///
///   runtime/teams/{teamId}/     # workspace+team CLI warm tier (mixed cursor)
///     cursor/init.json
///     cursor/projects/{slug}/
///     cursor/plugins/...
///   sessions/{sessionId}/runtime/{memberId}/cursor/home/  # mixed cursor HOME
/// ```
class WorkspaceLayout {
  WorkspaceLayout({required this.teampilotRoot, Filesystem? fs})
    : _fs = fs ?? AppStorage.fs;

  final String teampilotRoot;
  final Filesystem _fs;

  p.Context get _ctx => _fs.pathContext;

  String get workspaceRootDir => _ctx.join(teampilotRoot, 'workspace');

  /// Cached workspace list for fast home index load; rebuilt when stale or missing.
  String get workspacesIndexFile =>
      _ctx.join(workspaceRootDir, 'workspaces-index.json');

  String get workspacesDir => _ctx.join(workspaceRootDir, 'workspaces');

  String workspaceDir(String workspaceId) =>
      _ctx.join(workspacesDir, workspaceId.trim());

  String manifestFile(String workspaceId) =>
      _ctx.join(workspaceDir(workspaceId), 'manifest.json');

  String profileFile(String workspaceId) =>
      _ctx.join(workspaceDir(workspaceId), 'profile.json');

  /// Project-scoped skills/plugins/mcp/extension bindings.
  String projectConfigFile(String workspaceId) =>
      _ctx.join(workspaceDir(workspaceId), 'project-config.json');

  String assetsDir(String workspaceId) =>
      _ctx.join(workspaceDir(workspaceId), 'assets');

  String workspaceConfigDir(String workspaceId) =>
      _ctx.join(workspaceDir(workspaceId), 'config');

  String workspaceConfigToolDir(String workspaceId, String tool) =>
      _ctx.join(workspaceConfigDir(workspaceId), tool.trim());

  String workspaceAutomationsDir(String workspaceId) =>
      _ctx.join(workspaceDir(workspaceId), 'automations');

  String workspaceAutomationsFile(String workspaceId) =>
      _ctx.join(workspaceAutomationsDir(workspaceId), 'automations.json');

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

  /// Workspace-level runtime root (team-scoped children below).
  String workspaceRuntimeDir(String workspaceId) =>
      _ctx.join(workspaceDir(workspaceId), 'runtime');

  /// Per-team runtime root under [workspaceRuntimeDir].
  String workspaceTeamRuntimeDir(String workspaceId, String teamId) =>
      _ctx.join(workspaceRuntimeDir(workspaceId), 'teams', teamId.trim());

  /// Shared CLI warm tier for one team in a workspace (cursor projects, plugins).
  String workspaceRuntimeToolDir(
    String workspaceId,
    String teamId,
    String tool,
  ) => _ctx.join(workspaceTeamRuntimeDir(workspaceId, teamId), tool.trim());

  String workspaceLifecycleManifestPath(
    String workspaceId,
    String teamId,
    String tool,
  ) => _ctx.join(
    workspaceRuntimeToolDir(workspaceId, teamId, tool),
    'init.json',
  );

  String workspaceRuntimeMemberToolDir(
    String workspaceId,
    String teamId,
    String memberId,
    String tool,
  ) => _ctx.join(
    workspaceTeamRuntimeDir(workspaceId, teamId),
    memberId.trim(),
    tool.trim(),
  );

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
  }) => _ctx.join(
    sessionRuntimeToolDir(workspaceId, sessionId, tool, memberId: memberId),
    'plugins',
  );

  /// TeamPilot-owned staging area for CLIs that install plugins themselves.
  String sessionRuntimePluginPoolDir(
    String workspaceId,
    String sessionId,
    String tool, {
    String? memberId,
  }) {
    final trimmedMember = memberId?.trim() ?? '';
    final root = _ctx.join(
      sessionRuntimeDir(workspaceId, sessionId),
      '.teampilot',
    );
    return trimmedMember.isEmpty
        ? _ctx.join(root, tool.trim(), 'plugins')
        : _ctx.join(root, trimmedMember, tool.trim(), 'plugins');
  }

  /// App-managed location for a created git worktree:
  /// `<teampilotRoot>/worktrees/<repoName>/<branch>`. Branch slashes become
  /// nested directories (git accepts the path verbatim).
  String worktreePathFor({required String repoName, required String branch}) =>
      _ctx.join(teampilotRoot, 'worktrees', repoName.trim(), branch.trim());
}
