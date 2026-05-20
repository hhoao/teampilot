import 'dart:io';

import 'package:path/path.dart' as p;

import 'launch_command_builder.dart';

/// Three tools whose runtime config we provision under `config-profiles/`.
const List<String> cliLayoutDefaultTools = ['claude', 'flashskyai', 'codex'];

typedef LayoutDirectoryCreator = Future<void> Function(String path);

/// Returns true when the symlink was created; false when the caller should
/// fall back to copy (e.g. Windows native or SFTP without symlink support).
typedef LayoutSymlinkCreator =
    Future<bool> Function({required String target, required String linkPath});

typedef LayoutCopier = Future<void> Function({
  required String source,
  required String destination,
});

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
  CliDataLayout({
    required this.teampilotRoot,
    p.Context? pathContext,
    LayoutDirectoryCreator? createDirectory,
    LayoutSymlinkCreator? createSymlink,
    LayoutCopier? copyDirectory,
  }) : _pathContext = pathContext ?? _defaultContextFor(teampilotRoot),
       _createDirectory = createDirectory ?? _defaultCreateDirectory,
       _createSymlink = createSymlink ?? _defaultCreateSymlink,
       _copyDirectory = copyDirectory ?? _defaultCopyDirectory;

  final String teampilotRoot;
  final p.Context _pathContext;
  final LayoutDirectoryCreator _createDirectory;
  final LayoutSymlinkCreator _createSymlink;
  final LayoutCopier _copyDirectory;

  String get configProfilesDir => _pathContext.join(teampilotRoot, 'config-profiles');

  /// App-level tool root: `config-profiles/{tool}/`.
  String appToolRoot(String tool) =>
      _pathContext.join(configProfilesDir, tool.trim());

  /// Team-level tool root: `config-profiles/teams/{teamId}/{tool}/`.
  String teamToolDir(String teamId, String tool) => _pathContext.join(
    configProfilesDir,
    'teams',
    teamId.trim(),
    tool.trim(),
  );

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
    await _createDirectory(appToolRoot(tool));
  }

  /// Creates team root and symlinks `agents/` + `skills/` to app level.
  Future<void> ensureTeamInheritsApp(String teamId, String tool) async {
    final trimmedTeam = teamId.trim();
    final trimmedTool = tool.trim();
    if (trimmedTeam.isEmpty || trimmedTool.isEmpty) return;
    await ensureAppToolLayout(trimmedTool);
    final teamRoot = teamToolDir(trimmedTeam, trimmedTool);
    await _createDirectory(teamRoot);
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
  Future<void> ensureMemberInheritsTeam(
    String teamId,
    String sessionId,
    String tool,
  ) async {
    final trimmedTeam = teamId.trim();
    final trimmedSession = sessionId.trim();
    final trimmedTool = tool.trim();
    if (trimmedTeam.isEmpty ||
        trimmedSession.isEmpty ||
        trimmedTool.isEmpty) {
      return;
    }
    await ensureTeamInheritsApp(trimmedTeam, trimmedTool);
    final memberRoot = memberToolDir(trimmedTeam, trimmedSession, trimmedTool);
    await _createDirectory(memberRoot);
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

  Future<void> _ensureInheritedChild({
    required String childName,
    required String parentToolRoot,
    required String ownToolRoot,
  }) async {
    final source = _pathContext.join(parentToolRoot, childName);
    final target = _pathContext.join(ownToolRoot, childName);
    await _createDirectory(source);
    final linked = await _createSymlink(target: source, linkPath: target);
    if (linked) return;
    await _copyDirectory(source: source, destination: target);
  }

  static p.Context _defaultContextFor(String root) {
    return root.startsWith('/') ? p.Context(style: p.Style.posix) : p.context;
  }

  static Future<void> _defaultCreateDirectory(String path) {
    return Directory(path).create(recursive: true);
  }

  static Future<bool> _defaultCreateSymlink({
    required String target,
    required String linkPath,
  }) async {
    try {
      final link = Link(linkPath);
      if (link.existsSync()) {
        await link.delete();
      }
      final dir = Directory(linkPath);
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
      await Link(linkPath).create(target);
      return true;
    } on FileSystemException catch (e) {
      if (!Platform.isWindows) rethrow;
      final result = await Process.run('cmd', [
        '/c',
        'mklink',
        '/J',
        linkPath,
        target,
      ]);
      if (result.exitCode == 0) return true;
      // Fall back to copy if junction creation also fails.
      throw FileSystemException('junction failed', linkPath, e.osError);
    }
  }

  static Future<void> _defaultCopyDirectory({
    required String source,
    required String destination,
  }) async {
    final src = Directory(source);
    if (!src.existsSync()) {
      await Directory(destination).create(recursive: true);
      return;
    }
    final dst = Directory(destination);
    if (dst.existsSync()) {
      await dst.delete(recursive: true);
    }
    await dst.create(recursive: true);
    await for (final entity in src.list(recursive: true, followLinks: false)) {
      final rel = p.relative(entity.path, from: src.path);
      final destPath = p.join(dst.path, rel);
      if (entity is Directory) {
        await Directory(destPath).create(recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(destPath)).create(recursive: true);
        await entity.copy(destPath);
      }
    }
  }
}
