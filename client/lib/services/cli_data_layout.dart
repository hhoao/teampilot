import 'package:path/path.dart' as p;

import 'app_storage.dart';
import 'cli_plugin_layout.dart';
import 'cli_plugin_manifest_flavor.dart';
import 'io/filesystem.dart';
import 'launch_command_builder.dart';

/// Three tools whose runtime config we provision under `config-profiles/`.
const List<String> cliLayoutDefaultTools = ['claude', 'flashskyai', 'codex'];

/// Sole source of CLI runtime directory paths under TeamPilot's app-data root.
///
/// Layout (all paths relative to [teampilotRoot]):
///
/// ```
/// config-profiles/
///   {tool}/                                          # app level
///   teams/{teamId}/{tool}/                           # team level
///   teams/{teamId}/members/{sessionId}/{tool}/       # member level (PTY CONFIG_DIR)
/// ```
///
/// The CLI writes session transcripts to the **member** root, so
/// [transcriptSearchRoots] returns app + team + member tool roots to support
/// `--resume` lookups across all three layers.
class CliDataLayout {
  CliDataLayout({required this.teampilotRoot, Filesystem? fs})
    : _fs = fs ?? AppStorage.fs;

  final String teampilotRoot;
  final Filesystem _fs;

  p.Context get _pathContext => _fs.pathContext;

  String get configProfilesDir =>
      _pathContext.join(teampilotRoot, 'config-profiles');

  /// App-level tool root: `config-profiles/{tool}/`.
  String appToolRoot(String tool) =>
      _pathContext.join(configProfilesDir, tool.trim());

  /// Team-level tool root: `config-profiles/teams/{teamId}/{tool}/`.
  String teamToolDir(String teamId, String tool) =>
      _pathContext.join(configProfilesDir, 'teams', teamId.trim(), tool.trim());

  /// Member-level tool root: `config-profiles/teams/{teamId}/members/{sessionId}/{tool}/`.
  String memberToolDir(String teamId, String sessionId, String tool) =>
      _pathContext.join(
        configProfilesDir,
        'teams',
        teamId.trim(),
        'members',
        sessionId.trim(),
        tool.trim(),
      );

  /// Team-scope skills dir: `config-profiles/teams/{teamId}/flashskyai/skills/`.
  String teamSkillsDir(String teamId) =>
      _pathContext.join(teamToolDir(teamId, 'flashskyai'), 'skills');

  /// Team-scope plugins dir: `config-profiles/teams/{teamId}/flashskyai/plugins/`.
  String teamPluginsDir(String teamId) =>
      _pathContext.join(teamToolDir(teamId, 'flashskyai'), 'plugins');

  /// Convenience accessor for the FlashskyAI provider catalog file.
  String get appFlashskyaiLlmConfigFile =>
      _pathContext.join(appToolRoot('flashskyai'), 'llm_config.json');

  /// All tool roots to scan for `--resume` lookups: app + team + member.
  ///
  /// Caller appends `projects/<bucket>/<id>.jsonl` or `sessions/<id>.json` per
  /// the CLI's transcript layout. Order is broad → narrow (app, team, member).
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

  /// CLI bucket folder name under `projects/` for a workspace path
  /// (e.g. `/home/hhoa/agent` → `-home-hhoa-agent`, `D:\repo` → `-mnt-d-repo`).
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

  /// Creates the app-level tool root.
  Future<void> ensureAppToolLayout(String tool) async {
    await _fs.ensureDir(appToolRoot(tool));
  }

  /// Creates team root and symlinks `agents/` + `skills/` to app level.
  Future<void> ensureTeamInheritsApp(String teamId, String tool) async {
    final trimmedTeam = teamId.trim();
    final trimmedTool = tool.trim();
    if (trimmedTeam.isEmpty || trimmedTool.isEmpty) return;
    await ensureAppToolLayout(trimmedTool);
    final teamRoot = teamToolDir(trimmedTeam, trimmedTool);
    await _fs.ensureDir(teamRoot);
    await _ensureInheritedChild(
      childName: 'agents',
      parentToolRoot: appToolRoot(trimmedTool),
      ownToolRoot: teamRoot,
    );
    await _ensureInheritedChild(
      childName: 'skills',
      parentToolRoot: appToolRoot(trimmedTool),
      ownToolRoot: teamRoot,
    );
  }

  /// Creates member root and symlinks `agents/` + `skills/` to team level.
  ///
  /// Team plugins are copied into the member CONFIG_DIR by
  /// [provisionMemberPluginsFromTeam] (session launch).
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
    await ensureTeamInheritsApp(trimmedTeam, trimmedTool);
    final memberRoot = memberToolDir(trimmedTeam, trimmedSession, trimmedTool);
    await _fs.ensureDir(memberRoot);
    final teamRoot = teamToolDir(trimmedTeam, trimmedTool);
    await _ensureInheritedChild(
      childName: 'agents',
      parentToolRoot: teamRoot,
      ownToolRoot: memberRoot,
    );
    await _ensureInheritedChild(
      childName: 'skills',
      parentToolRoot: teamRoot,
      ownToolRoot: memberRoot,
    );
  }

  /// Member `plugins/` dir for a tool CONFIG_DIR.
  String memberPluginsDir(String teamId, String sessionId, String tool) =>
      _pathContext.join(
        memberToolDir(teamId, sessionId, tool),
        'plugins',
      );

  /// Copies formatted team plugin bundles into the session tool root.
  ///
  /// Source: [teamPluginsDir] (`flashskyai/plugins/<name>/` per bundle).
  /// Dest: `members/<session>/<tool>/plugins/<name>/` (real directories, not symlinks).
  Future<void> provisionMemberPluginsFromTeam(
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
    final flavor = cliPluginManifestFlavorForTool(trimmedTool) ??
        CliPluginManifestFlavor.claude;
    await CliPluginLayout.copyBundlesToMember(
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
  }) async {
    final source = _pathContext.join(parentToolRoot, childName);
    final target = _pathContext.join(ownToolRoot, childName);
    await _fs.ensureDir(source);
    final linked = await _fs.createSymlink(target: source, linkPath: target);
    if (linked) return;
    await _fs.copyTree(source: source, destination: target);
  }
}
