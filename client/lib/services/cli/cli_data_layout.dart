import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/lock_pool.dart';
import '../storage/app_storage.dart';
import '../../models/team_config.dart';
import '../plugin/cli_plugin_layout.dart';
import '../cli/registry/capabilities/plugin_manifest_capability.dart';
import '../io/filesystem.dart';
import '../session/launch_command_builder.dart';

/// Tools with a `config-profiles/{tool}/` tree (see [CliDataLayout]).
final List<String> cliLayoutDefaultTools =
    CliTool.values.map((c) => c.value).toList(growable: false);

/// Canonical paths for CLI **runtime config** under TeamPilot app data.
///
/// [teampilotRoot] is `AppPaths.basePath` / `RuntimeStorageContext.appDataRoot`
/// (e.g. `~/.local/share/com.hhoa.teampilot`). This class only models
/// `{teampilotRoot}/config-profiles/`. Other app-data dirs are separate:
///
/// | Path under [teampilotRoot] | Role |
/// |----------------------------|------|
/// | `providers/{tool}/providers.json` | UI provider catalog (not CONFIG_DIR) |
/// | `skills/installed/` | Global skill packages (source for team links) |
/// | `plugins/installed/` | Global plugin bundles (source for team links) |
/// | `projects/` | TeamPilot session index (`projects.json`, `sessions/{id}/`) |
/// | `config-profiles/` | **This layout** — per-tool trees the CLIs read at launch |
///
/// ## Three isolation layers
///
/// Each layer has one directory per tool (`claude`, `flashskyai`, `codex`):
///
/// ```
/// {teampilotRoot}/config-profiles/
/// ├── {tool}/                                    # app — shared defaults
/// │   ├── agents/                                # optional app-wide agents
/// │   ├── skills/                                # optional app-wide skills
/// │   ├── projects/                              # transcripts (see below)
/// │   └── …                                      # tool-specific files (e.g. llm_config.json)
/// ├── teams/
/// │   └── {teamId}/                              # canonical [TeamConfig.id] (slug at create/load)
/// │       ├── session-counter.json               # allocates cliTeamName ({teamId}-{n})
/// │       ├── {tool}/                            # team — inherits app via symlinks
/// │       │   ├── agents/   → symlink to app …/agents/
/// │       │   └── plugins/  → team bundles (flashskyai only; [teamPluginsDir])
/// │       └── members/
/// │           └── {cliTeamName}/                 # e.g. my-team-3 or _adhoc
/// │               ├── {tool}/                    # non-mixed: shared session CONFIG_DIR
/// │               └── {memberId}/                # mixed: one isolated CONFIG_DIR per agent process
/// │                   └── {tool}/                # member — PTY CONFIG_DIR
/// │                   ├── agents/   → symlink to team …/agents/
/// │                   ├── skills/   → materialized at launch by ResourceProvisioningService
/// │                   ├── plugins/  → copies/symlinks from team at launch
/// │                   ├── projects/ …              # CLI transcripts (--session-id / taskId)
/// │                   ├── teams/…/config.json      # Claude agent-team roster only
/// │                   └── settings/, metadata, hooks …  # [ConfigProfileService]
/// └── standalone/
///     └── projects/{projectId}/                  # personal — [ProjectProfile] scope
///         ├── {tool}/                            # project layer (inherits app)
///         │   └── plugins/                       # [ProjectPluginLinkerService] (flashskyai)
///         ├── mcp/servers.json                   # project MCP snapshot
///         └── sessions/{sessionId}/{tool}/       # personal PTY CONFIG_DIR
/// ```
///
/// UI chat [AppSession.sessionId] (UUID) lives under its own self-contained
/// directory `{teampilotRoot}/projects/sessions/{sessionId}/` (metadata +
/// bus-mail/ + bus-tasks/), not under `members/{cliTeamName}/`. See
/// [SessionStorageLayout].
///
/// **Inheritance:** [ensureTeamInheritsApp] links `agents/` from app → team.
/// [ensureMemberInheritsTeam] links `agents/` from team → member. Symlink
/// preferred; copy tree if the filesystem cannot link. Team scope also gets
/// explicit plugin trees under `teams/{teamId}/flashskyai/` via
/// [TeamPluginLinkerService] (source: `plugins/installed/`).
/// [provisionMemberPluginsFromTeam] materializes team plugins into the member
/// CONFIG_DIR at session launch. Skills are materialized into the leaf
/// CONFIG_DIR at launch by [ResourceProvisioningService].
///
/// **PTY env (member root):** [ConfigProfileService.prepareTeamLaunch] sets
/// `CLAUDE_CONFIG_DIR` / `FLASHSKYAI_CONFIG_DIR` (and `FLASHSKYAI_SESSION_HOME_DIR`)
/// to [memberToolDir]. FlashskyAI also uses app-level [appFlashskyaiLlmConfigFile]
/// via `LLM_CONFIG_PATH`.
///
/// ## Transcripts (`projects/` under each tool root)
///
/// CLIs store conversation state under `{toolRoot}/projects/`, not under
/// TeamPilot's top-level `projects/` index. Layout per workspace [primaryPath]:
///
/// ```
/// {toolRoot}/projects/{bucket}/{sessionId}.jsonl
/// {toolRoot}/projects/{bucket}/{sessionId}/   # directory form (some tools)
/// ```
///
/// [projectBucketForPrimaryPath] encodes [primaryPath] as `{bucket}` (e.g.
/// `/home/user/repo` → `-home-user-repo`). [transcriptSearchRoots] lists app,
/// then team, then member tool roots (broad → narrow) so `--resume` and session
/// probes can find transcripts written at any layer.
class CliDataLayout {
  CliDataLayout({required this.teampilotRoot, Filesystem? fs})
    : _fs = fs ?? AppStorage.fs;

  final String teampilotRoot;
  final Filesystem _fs;

  /// Serializes [ensureTeamInheritsApp] per `(teamId, tool)` so concurrent
  /// member launches do not race on the shared team-level `agents/` / `skills/`.
  static final _teamInheritLocks = LockPool();

  /// Serializes standalone project inherit per `(projectId, tool)`.
  static final _standaloneInheritLocks = LockPool();

  p.Context get _pathContext => _fs.pathContext;

  /// `{teampilotRoot}/config-profiles`.
  String get configProfilesDir =>
      _pathContext.join(teampilotRoot, 'config-profiles');

  /// App layer: `config-profiles/{tool}/`.
  String appToolRoot(String tool) =>
      _pathContext.join(configProfilesDir, tool.trim());

  /// Team layer: `config-profiles/teams/{teamId}/{tool}/`.
  ///
  /// [teamId] must be canonical [TeamConfig.id] (slug assigned at create/load).
  String teamToolDir(String teamId, String tool) => _pathContext.join(
    configProfilesDir,
    'teams',
    teamId.trim(),
    tool.trim(),
  );

  /// `config-profiles/teams/{teamId}/session-counter.json` — CLI team name seq.
  String teamSessionCounterFile(String teamId) => _pathContext.join(
    configProfilesDir,
    'teams',
    teamId.trim(),
    'session-counter.json',
  );

  /// Member layer (PTY CONFIG_DIR):
  /// `config-profiles/teams/{teamId}/members/{cliTeamName}/{tool}/`.
  ///
  /// [sessionId] is [AppSession.cliTeamName] or [configProfileAdhocSessionId].
  /// In mixed mode each agent runs as its own process, so the launch scope nests
  /// the member under the session (`{cliTeamName}/{memberId}`) via
  /// [mixedModeMemberScopeSessionId]; the resulting per-member
  /// CONFIG_DIR keeps each member's teammate-bus MCP config + `X-Member` identity
  /// isolated. Teardown removes the `{cliTeamName}` parent, covering all members.
  String memberToolDir(String teamId, String sessionId, String tool) =>
      _pathContext.join(
        configProfilesDir,
        'teams',
        teamId.trim(),
        'members',
        sessionId.trim(),
        tool.trim(),
      );

  /// Team flashskyai plugin bundles:
  /// `config-profiles/teams/{teamId}/flashskyai/plugins/<name>/`.
  ///
  /// Populated by [TeamPluginLinkerService] from `{teampilotRoot}/plugins/installed/`.
  String teamPluginsDir(String teamId) =>
      _pathContext.join(teamToolDir(teamId, 'flashskyai'), 'plugins');

  /// Team MCP snapshot directory:
  /// `config-profiles/teams/{teamId}/mcp/`.
  ///
  /// Populated by [TeamMcpLinkerService] from `{teampilotRoot}/mcp/mcp_servers.json`.
  String teamMcpDir(String teamId) =>
      _pathContext.join(configProfilesDir, 'teams', teamId.trim(), 'mcp');

  /// Aggregated MCP servers for a team:
  /// `config-profiles/teams/{teamId}/mcp/servers.json`.
  String teamMcpServersFile(String teamId) =>
      _pathContext.join(teamMcpDir(teamId), 'servers.json');

  /// Personal projects root: `config-profiles/standalone/projects/`.
  String standaloneProjectsDir() =>
      _pathContext.join(configProfilesDir, 'standalone', 'projects');

  /// Personal project root:
  /// `config-profiles/standalone/projects/{projectId}/`.
  String standaloneProjectDir(String projectId) => _pathContext.join(
    standaloneProjectsDir(),
    projectId.trim(),
  );

  /// Personal project tool root:
  /// `config-profiles/standalone/projects/{projectId}/{tool}/`.
  String standaloneProjectToolDir(String projectId, String tool) =>
      _pathContext.join(standaloneProjectDir(projectId), tool.trim());

  /// Personal project flashskyai plugin bundles:
  /// `config-profiles/standalone/projects/{projectId}/flashskyai/plugins/`.
  String standaloneProjectPluginsDir(String projectId) => _pathContext.join(
    standaloneProjectToolDir(projectId, 'flashskyai'),
    'plugins',
  );

  /// Personal project MCP snapshot directory:
  /// `config-profiles/standalone/projects/{projectId}/mcp/`.
  String standaloneProjectMcpDir(String projectId) =>
      _pathContext.join(standaloneProjectDir(projectId), 'mcp');

  /// Aggregated MCP servers for a personal project:
  /// `config-profiles/standalone/projects/{projectId}/mcp/servers.json`.
  String standaloneProjectMcpServersFile(String projectId) =>
      _pathContext.join(standaloneProjectMcpDir(projectId), 'servers.json');

  /// Personal session layer (PTY CONFIG_DIR):
  /// `config-profiles/standalone/projects/{projectId}/sessions/{sessionId}/{tool}/`.
  String standaloneProjectSessionToolDir(
    String projectId,
    String sessionId,
    String tool,
  ) => _pathContext.join(
    standaloneProjectDir(projectId),
    'sessions',
    sessionId.trim(),
    tool.trim(),
  );

  /// App-level FlashskyAI LLM catalog (not per-session):
  /// `config-profiles/flashskyai/llm_config.json`.
  ///
  /// Passed to the CLI as `LLM_CONFIG_PATH` while CONFIG_DIR stays at member root.
  String get appFlashskyaiLlmConfigFile =>
      _pathContext.join(appToolRoot('flashskyai'), 'llm_config.json');

  /// Tool roots to search for transcripts, in order: app → team → member.
  ///
  /// For each root, look under `projects/{bucket}/` where [projectBucketForPrimaryPath]
  /// derives `{bucket}` from the workspace [primaryPath]. Typical files:
  /// `{sessionId}.jsonl` or a `{sessionId}/` directory (see session lifecycle probes).
  List<String> transcriptSearchRoots({
    required String teamId,
    required String runtimeSessionId,
    Iterable<String>? tools,
  }) {
    final trimmedTeam = teamId.trim();
    final trimmedSession = runtimeSessionId.trim();
    final tt = (tools ?? cliLayoutDefaultTools)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return [
      for (final tool in tt) appToolRoot(tool),
      if (trimmedTeam.isNotEmpty)
        for (final tool in tt) teamToolDir(trimmedTeam, tool),
      if (trimmedTeam.isNotEmpty && trimmedSession.isNotEmpty)
        for (final tool in tt) memberToolDir(trimmedTeam, trimmedSession, tool),
    ];
  }

  /// Encodes a workspace [primaryPath] as the `projects/` subdirectory name.
  ///
  /// Examples: `/home/user/agent` → `-home-user-agent`;
  /// Windows `D:\repo` (WSL launch) → WSL path then `-mnt-d-repo`.
  /// Empty when path is `.` or `/`.
  static String projectBucketForPrimaryPath(String primaryPath) {
    var s = primaryPath.trim().replaceAll('\\', '/');
    if (s.isEmpty) return '';
    final wslStyle = LaunchCommandBuilder.windowsPathToWsl(s);
    if (wslStyle != null) {
      s = wslStyle;
    } else if (!s.startsWith('/')) {
      s = p.normalize(s).replaceAll('\\', '/');
    }
    if (s == '.' || s == '/') return '';
    return s.replaceAll('/', '-');
  }

  /// Ensures `config-profiles/{tool}/` exists (app layer only; no symlinks).
  Future<void> ensureAppToolLayout(String tool) async {
    await _fs.ensureDir(appToolRoot(tool));
  }

  static String _teamInheritLockKey(String teamId, String tool) =>
      '${teamId.trim()}|${tool.trim()}';

  static String _standaloneInheritLockKey(String projectId, String tool) =>
      'standalone|${projectId.trim()}|${tool.trim()}';

  /// Ensures team `{tool}/` exists and inherits app `agents/`.
  Future<void> ensureTeamInheritsApp(String teamId, String tool) async {
    final trimmedTeam = teamId.trim();
    final trimmedTool = tool.trim();
    if (trimmedTeam.isEmpty || trimmedTool.isEmpty) return;
    await _teamInheritLocks.synchronized(
      _teamInheritLockKey(trimmedTeam, trimmedTool),
      () => _ensureTeamInheritsAppUnlocked(trimmedTeam, trimmedTool),
    );
  }

  Future<void> _ensureTeamInheritsAppUnlocked(
    String trimmedTeam,
    String trimmedTool,
  ) async {
    await ensureAppToolLayout(trimmedTool);
    final teamRoot = teamToolDir(trimmedTeam, trimmedTool);
    await _fs.ensureDir(teamRoot);
    await _ensureInheritedChild(
      childName: 'agents',
      parentToolRoot: appToolRoot(trimmedTool),
      ownToolRoot: teamRoot,
    );
  }

  /// Ensures standalone project `{tool}/` exists and inherits app `agents/`.
  Future<void> ensureStandaloneProjectInheritsApp(
    String projectId,
    String tool,
  ) async {
    final trimmedProject = projectId.trim();
    final trimmedTool = tool.trim();
    if (trimmedProject.isEmpty || trimmedTool.isEmpty) return;
    await _standaloneInheritLocks.synchronized(
      _standaloneInheritLockKey(trimmedProject, trimmedTool),
      () => _ensureStandaloneProjectInheritsAppUnlocked(
        trimmedProject,
        trimmedTool,
      ),
    );
  }

  Future<void> _ensureStandaloneProjectInheritsAppUnlocked(
    String trimmedProject,
    String trimmedTool,
  ) async {
    await ensureAppToolLayout(trimmedTool);
    final projectRoot = standaloneProjectToolDir(trimmedProject, trimmedTool);
    await _fs.ensureDir(projectRoot);
    await _ensureInheritedChild(
      childName: 'agents',
      parentToolRoot: appToolRoot(trimmedTool),
      ownToolRoot: projectRoot,
    );
  }

  /// Ensures standalone session `{tool}/` exists and inherits project
  /// `agents/` + `skills/`.
  ///
  /// Holds the same per-project lock through session symlinks so concurrent
  /// session launches cannot re-enter project inherit while another session
  /// still links.
  Future<void> ensureStandaloneSessionInheritsProject(
    String projectId,
    String sessionId,
    String tool,
  ) async {
    final trimmedProject = projectId.trim();
    final trimmedSession = sessionId.trim();
    final trimmedTool = tool.trim();
    if (trimmedProject.isEmpty ||
        trimmedSession.isEmpty ||
        trimmedTool.isEmpty) {
      return;
    }
    await _standaloneInheritLocks.synchronized(
      _standaloneInheritLockKey(trimmedProject, trimmedTool),
      () async {
        await _ensureStandaloneProjectInheritsAppUnlocked(
          trimmedProject,
          trimmedTool,
        );
        final sessionRoot = standaloneProjectSessionToolDir(
          trimmedProject,
          trimmedSession,
          trimmedTool,
        );
        await _fs.ensureDir(sessionRoot);
        final projectRoot = standaloneProjectToolDir(trimmedProject, trimmedTool);
        // Skills are materialized into the leaf CONFIG_DIR as a real directory
        // owned per-session by ResourceProvisioningService; the session no
        // longer inherits a skills/ symlink from the project staging layer
        // (which would otherwise be written through and clobbered).
        await _ensureInheritedChild(
          childName: 'agents',
          parentToolRoot: projectRoot,
          ownToolRoot: sessionRoot,
        );
      },
    );
  }

  /// Ensures member `{tool}/` exists and inherits team `agents/`.
  ///
  /// Call [provisionMemberPluginsFromTeam] separately (session launch) for `plugins/`.
  ///
  /// Holds the same per-team lock through member symlinks so concurrent member
  /// launches cannot re-enter team inherit while another member still links.
  Future<void> ensureMemberInheritsTeam(
    String teamId,
    String sessionId,
    String tool,
  ) async {
    final trimmedTeam = teamId.trim();
    final trimmedSession = sessionId.trim();
    final trimmedTool = tool.trim();
    if (trimmedTeam.isEmpty || trimmedSession.isEmpty || trimmedTool.isEmpty) {
      return;
    }
    await _teamInheritLocks.synchronized(
      _teamInheritLockKey(trimmedTeam, trimmedTool),
      () async {
        await _ensureTeamInheritsAppUnlocked(trimmedTeam, trimmedTool);
        final memberRoot = memberToolDir(trimmedTeam, trimmedSession, trimmedTool);
        await _fs.ensureDir(memberRoot);
        final teamRoot = teamToolDir(trimmedTeam, trimmedTool);
        // Skills are materialized into the member leaf CONFIG_DIR as a real
        // directory owned per-member by ResourceProvisioningService; the member
        // no longer inherits a skills/ symlink from the team staging layer.
        await _ensureInheritedChild(
          childName: 'agents',
          parentToolRoot: teamRoot,
          ownToolRoot: memberRoot,
        );
      },
    );
  }

  /// Member `plugins/` dir for a tool CONFIG_DIR.
  String memberPluginsDir(String teamId, String sessionId, String tool) =>
      _pathContext.join(
        memberToolDir(teamId, sessionId, tool),
        'plugins',
      );

  /// Standalone session `plugins/` dir for a tool CONFIG_DIR.
  String standaloneProjectSessionPluginsDir(
    String projectId,
    String sessionId,
    String tool,
  ) =>
      _pathContext.join(
        standaloneProjectSessionToolDir(projectId, sessionId, tool),
        'plugins',
      );

  /// Copies or symlinks team plugin bundles into the member CONFIG_DIR.
  ///
  /// Source: [teamPluginsDir] (`…/flashskyai/plugins/<bundle>/`).
  /// Dest: [memberPluginsDir] (`…/members/{session}/{tool}/plugins/<bundle>/`).
  /// Returns optional provision-stamp JSON for [CliPluginRegistryService].
  Future<String?> provisionMemberPluginsFromTeam(
    String teamId,
    String sessionId,
    String tool,
  ) async {
    final trimmedTeam = teamId.trim();
    final trimmedSession = sessionId.trim();
    final trimmedTool = tool.trim();
    if (trimmedTeam.isEmpty || trimmedSession.isEmpty || trimmedTool.isEmpty) {
      return null;
    }
    final paths =
        pluginManifestPathsForTool(
          CliTool.tryParse(trimmedTool) ?? CliTool.claude,
        ) ??
        claudePluginManifestPaths;
    return CliPluginLayout.copyBundlesToMember(
      fs: _fs,
      teamPluginsDir: teamPluginsDir(trimmedTeam),
      memberPluginsDir: memberPluginsDir(trimmedTeam, trimmedSession, trimmedTool),
      paths: paths,
    );
  }

  /// Copies or symlinks project plugin bundles into the standalone session CONFIG_DIR.
  ///
  /// Source: [standaloneProjectPluginsDir] (`…/flashskyai/plugins/<bundle>/`).
  /// Dest: [standaloneProjectSessionPluginsDir].
  /// Returns optional provision-stamp JSON for [CliPluginRegistryService].
  Future<String?> provisionStandaloneSessionPluginsFromProject(
    String projectId,
    String sessionId,
    String tool,
  ) async {
    final trimmedProject = projectId.trim();
    final trimmedSession = sessionId.trim();
    final trimmedTool = tool.trim();
    if (trimmedProject.isEmpty ||
        trimmedSession.isEmpty ||
        trimmedTool.isEmpty) {
      return null;
    }
    final paths =
        pluginManifestPathsForTool(
          CliTool.tryParse(trimmedTool) ?? CliTool.claude,
        ) ??
        claudePluginManifestPaths;
    return CliPluginLayout.copyBundlesToMember(
      fs: _fs,
      teamPluginsDir: standaloneProjectPluginsDir(trimmedProject),
      memberPluginsDir: standaloneProjectSessionPluginsDir(
        trimmedProject,
        trimmedSession,
        trimmedTool,
      ),
      paths: paths,
    );
  }

  Future<void> _ensureInheritedChild({
    required String childName,
    required String parentToolRoot,
    required String ownToolRoot,
    bool preservePopulatedDirectory = false,
  }) async {
    final source = _pathContext.join(parentToolRoot, childName);
    final target = _pathContext.join(ownToolRoot, childName);
    if (!(await _fs.stat(source)).exists) {
      await _fs.ensureDir(source);
    }
    final targetStat = await _fs.stat(target);
    if (preservePopulatedDirectory && targetStat.isDirectory) {
      return;
    }
    if (await _inheritLinkCurrent(source: source, target: target)) {
      if (await _inheritedPathIsAccessible(target)) return;
      await _fs.removeRecursive(target);
    }
    final linked = await _fs.createSymlink(target: source, linkPath: target);
    if (linked) return;
    await _fs.copyTree(source: source, destination: target);
  }

  /// Whether [path] can be listed (symlink/junction targets are reachable).
  Future<bool> _inheritedPathIsAccessible(String path) async {
    try {
      if (!(await _fs.stat(path)).exists) return false;
      await Directory(path).list(followLinks: true).take(1).drain();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<bool> _inheritLinkCurrent({
    required String source,
    required String target,
  }) async {
    final targetStat = await _fs.stat(target);
    if (!targetStat.exists) return false;
    final normalizedSource = _pathContext.normalize(
      _pathContext.absolute(source),
    );
    if (targetStat.isSymlink) {
      final linkTarget = await _fs.readSymlinkTarget(target);
      if (linkTarget == null) return false;
      return _pathContext.normalize(_pathContext.absolute(linkTarget)) ==
          normalizedSource;
    }
    if (Platform.isWindows && targetStat.isDirectory) {
      try {
        final resolved = _pathContext.normalize(
          await Directory(target).resolveSymbolicLinks(),
        );
        return resolved == normalizedSource;
      } on FileSystemException {
        return false;
      }
    }
    return false;
  }
}
