import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/lock_pool.dart';
import '../storage/app_storage.dart';
import '../plugin/cli_plugin_layout.dart';
import '../plugin/cli_plugin_manifest_flavor.dart';
import '../io/filesystem.dart';
import '../session/launch_command_builder.dart';
/// Tools with a `config-profiles/{tool}/` tree (see [CliDataLayout]).
const List<String> cliLayoutDefaultTools = ['claude', 'flashskyai', 'codex'];

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
/// | `projects/` | TeamPilot session index (`projects.json`, `sessions/*.json`) |
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
/// └── teams/
///     └── {teamId}/                              # canonical [TeamConfig.id] (slug at create/load)
///         ├── session-counter.json               # allocates cliTeamName ({teamId}-{n})
///         ├── {tool}/                            # team — inherits app via symlinks
///         │   ├── agents/   → symlink to app …/agents/
///         │   ├── skills/   → symlink (or populated dir; see [ensureTeamInheritsApp])
///         │   └── plugins/  → team bundles (flashskyai only; [teamPluginsDir])
///         └── members/
///             └── {cliTeamName}/                 # e.g. my-team-3 or _adhoc
///                 └── {tool}/                    # member — PTY CONFIG_DIR
///                     ├── agents/   → symlink to team …/agents/
///                     ├── skills/   → symlink to team …/skills/
///                     ├── plugins/  → copies/symlinks from team at launch
///                     ├── projects/ …              # CLI transcripts (--session-id / taskId)
///                     ├── teams/…/config.json      # Claude agent-team roster only
///                     └── settings/, metadata, hooks …  # [ConfigProfileService]
/// ```
///
/// UI chat [AppSession.sessionId] (UUID) lives under `{teampilotRoot}/projects/sessions/`,
/// not under `members/{cliTeamName}/`.
///
/// **Inheritance:** [ensureTeamInheritsApp] links `agents/` and `skills/` from app
/// → team. [ensureMemberInheritsTeam] links the same names from team → member.
/// Symlink preferred; copy tree if the filesystem cannot link. Team scope also
/// gets explicit skill/plugin trees under `teams/{teamId}/flashskyai/` via
/// [TeamSkillLinkerService] / [TeamPluginLinkerService] (sources:
/// `skills/installed/`, `plugins/installed/`). [provisionMemberPluginsFromTeam]
/// materializes team plugins into the member CONFIG_DIR at session launch.
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
  String memberToolDir(String teamId, String sessionId, String tool) =>
      _pathContext.join(
        configProfilesDir,
        'teams',
        teamId.trim(),
        'members',
        sessionId.trim(),
        tool.trim(),
      );

  /// Team flashskyai skills link target:
  /// `config-profiles/teams/{teamId}/flashskyai/skills/`.
  ///
  /// Populated by [TeamSkillLinkerService] from `{teampilotRoot}/skills/installed/`.
  String teamSkillsDir(String teamId) =>
      _pathContext.join(teamToolDir(teamId, 'flashskyai'), 'skills');

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
    Iterable<String> tools = cliLayoutDefaultTools,
  }) {
    final trimmedTeam = teamId.trim();
    final trimmedSession = runtimeSessionId.trim();
    final tt = tools.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
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

  /// Ensures team `{tool}/` exists and inherits app `agents/` + `skills/`.
  ///
  /// If team `skills/` already has content, it is left unchanged
  /// ([preservePopulatedDirectory]) so [TeamSkillLinkerService] links are not wiped.
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
    await Future.wait([
      _ensureInheritedChild(
        childName: 'agents',
        parentToolRoot: appToolRoot(trimmedTool),
        ownToolRoot: teamRoot,
      ),
      _ensureInheritedChild(
        childName: 'skills',
        parentToolRoot: appToolRoot(trimmedTool),
        ownToolRoot: teamRoot,
        preservePopulatedDirectory: true,
      ),
    ]);
  }

  /// Ensures member `{tool}/` exists and inherits team `agents/` + `skills/`.
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
        await Future.wait([
          _ensureInheritedChild(
            childName: 'agents',
            parentToolRoot: teamRoot,
            ownToolRoot: memberRoot,
          ),
          _ensureInheritedChild(
            childName: 'skills',
            parentToolRoot: teamRoot,
            ownToolRoot: memberRoot,
          ),
        ]);
      },
    );
  }

  /// Member `plugins/` dir for a tool CONFIG_DIR.
  String memberPluginsDir(String teamId, String sessionId, String tool) =>
      _pathContext.join(
        memberToolDir(teamId, sessionId, tool),
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
    final flavor = cliPluginManifestFlavorForTool(trimmedTool) ??
        CliPluginManifestFlavor.claude;
    return CliPluginLayout.copyBundlesToMember(
      fs: _fs,
      teamPluginsDir: teamPluginsDir(trimmedTeam),
      memberPluginsDir: memberPluginsDir(trimmedTeam, trimmedSession, trimmedTool),
      flavor: flavor,
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
