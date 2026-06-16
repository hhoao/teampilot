import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/team_config.dart';
import '../../utils/lock_pool.dart';
import '../cli/registry/capabilities/plugin_manifest_capability.dart';
import '../io/filesystem.dart';
import '../plugin/cli_plugin_layout.dart';
import '../session/launch_command_builder.dart';
import '../storage/app_storage.dart';
import 'workspace_layout.dart';

/// Tools with a `cli-defaults/{tool}/` tree (see [RuntimeLayout]).
final List<String> runtimeLayoutDefaultTools =
    CliTool.values.map((c) => c.value).toList(growable: false);

/// Canonical paths for CLI **runtime config** under TeamPilot app data.
///
/// See [docs/workspace-storage-layout.md] for the full tree. [WorkspaceLayout]
/// owns UI metadata; this class owns `cli-defaults/`, `teams-runtime/`, and
/// session/runtime inheritance under each project session.
class RuntimeLayout {
  RuntimeLayout({
    required this.teampilotRoot,
    Filesystem? fs,
    WorkspaceLayout? workspace,
  }) : _fs = fs ?? AppStorage.fs,
       workspace = workspace ?? WorkspaceLayout(teampilotRoot: teampilotRoot, fs: fs);

  final String teampilotRoot;
  final Filesystem _fs;
  final WorkspaceLayout workspace;

  static final _teamInheritLocks = LockPool();
  static final _projectInheritLocks = LockPool();

  p.Context get _pathContext => _fs.pathContext;

  String get cliDefaultsDir => _pathContext.join(teampilotRoot, 'cli-defaults');

  String get teamsRuntimeDir => _pathContext.join(teampilotRoot, 'teams-runtime');

  String appToolRoot(String tool) =>
      _pathContext.join(cliDefaultsDir, tool.trim());

  String teamRuntimeDir(String teamId) =>
      _pathContext.join(teamsRuntimeDir, teamId.trim());

  String teamToolDir(String teamId, String tool) =>
      _pathContext.join(teamRuntimeDir(teamId), tool.trim());

  String teamSessionCounterFile(String teamId) =>
      _pathContext.join(teamRuntimeDir(teamId), 'session-counter.json');

  String teamPluginsDir(String teamId) =>
      _pathContext.join(teamToolDir(teamId, 'flashskyai'), 'plugins');

  String teamMcpDir(String teamId) =>
      _pathContext.join(teamRuntimeDir(teamId), 'mcp');

  String teamMcpServersFile(String teamId) =>
      _pathContext.join(teamMcpDir(teamId), 'servers.json');

  String projectConfigToolDir(String projectId, String tool) =>
      workspace.projectConfigToolDir(projectId, tool);

  String projectConfigPluginsDir(String projectId) =>
      workspace.projectConfigPluginsDir(projectId);

  String projectConfigMcpDir(String projectId) =>
      workspace.projectConfigMcpDir(projectId);

  String projectConfigMcpServersFile(String projectId) =>
      workspace.projectConfigMcpServersFile(projectId);

  String sessionRuntimeToolDir(
    String projectId,
    String sessionId,
    String tool, {
    String? memberId,
  }) =>
      workspace.sessionRuntimeToolDir(
        projectId,
        sessionId,
        tool,
        memberId: memberId,
      );

  String sessionRuntimePluginsDir(
    String projectId,
    String sessionId,
    String tool, {
    String? memberId,
  }) =>
      workspace.sessionRuntimePluginsDir(
        projectId,
        sessionId,
        tool,
        memberId: memberId,
      );

  String get appFlashskyaiLlmConfigFile =>
      _pathContext.join(appToolRoot('flashskyai'), 'llm_config.json');

  List<String> transcriptSearchRoots({
    required String projectId,
    required String sessionId,
    String? teamId,
    String? memberId,
    Iterable<String>? tools,
  }) {
    final trimmedTeam = teamId?.trim() ?? '';
    final trimmedProject = projectId.trim();
    final trimmedSession = sessionId.trim();
    final trimmedMember = memberId?.trim() ?? '';
    final tt = (tools ?? runtimeLayoutDefaultTools)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return [
      for (final tool in tt) appToolRoot(tool),
      if (trimmedTeam.isNotEmpty)
        for (final tool in tt) teamToolDir(trimmedTeam, tool),
      if (trimmedProject.isNotEmpty)
        for (final tool in tt) projectConfigToolDir(trimmedProject, tool),
      if (trimmedProject.isNotEmpty && trimmedSession.isNotEmpty)
        for (final tool in tt)
          sessionRuntimeToolDir(
            trimmedProject,
            trimmedSession,
            tool,
            memberId: trimmedMember.isNotEmpty ? trimmedMember : null,
          ),
    ];
  }

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

  Future<void> ensureAppToolLayout(String tool) async {
    await _fs.ensureDir(appToolRoot(tool));
  }

  static String _teamInheritLockKey(String teamId, String tool) =>
      '${teamId.trim()}|${tool.trim()}';

  static String _projectInheritLockKey(String projectId, String tool) =>
      'project|${projectId.trim()}|${tool.trim()}';

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

  Future<void> ensureProjectConfigInheritsApp(
    String projectId,
    String tool,
  ) async {
    final trimmedProject = projectId.trim();
    final trimmedTool = tool.trim();
    if (trimmedProject.isEmpty || trimmedTool.isEmpty) return;
    await _projectInheritLocks.synchronized(
      _projectInheritLockKey(trimmedProject, trimmedTool),
      () => _ensureProjectConfigInheritsAppUnlocked(trimmedProject, trimmedTool),
    );
  }

  Future<void> _ensureProjectConfigInheritsAppUnlocked(
    String trimmedProject,
    String trimmedTool,
  ) async {
    await ensureAppToolLayout(trimmedTool);
    final projectRoot = projectConfigToolDir(trimmedProject, trimmedTool);
    await _fs.ensureDir(projectRoot);
    await _ensureInheritedChild(
      childName: 'agents',
      parentToolRoot: appToolRoot(trimmedTool),
      ownToolRoot: projectRoot,
    );
  }

  Future<void> ensureSessionRuntimeInheritsProject(
    String projectId,
    String sessionId,
    String tool, {
    String? memberId,
  }) async {
    final trimmedProject = projectId.trim();
    final trimmedSession = sessionId.trim();
    final trimmedTool = tool.trim();
    if (trimmedProject.isEmpty ||
        trimmedSession.isEmpty ||
        trimmedTool.isEmpty) {
      return;
    }
    await _projectInheritLocks.synchronized(
      _projectInheritLockKey(trimmedProject, trimmedTool),
      () async {
        await _ensureProjectConfigInheritsAppUnlocked(trimmedProject, trimmedTool);
        final sessionRoot = sessionRuntimeToolDir(
          trimmedProject,
          trimmedSession,
          trimmedTool,
          memberId: memberId,
        );
        await _fs.ensureDir(sessionRoot);
        final projectRoot = projectConfigToolDir(trimmedProject, trimmedTool);
        await _ensureInheritedChild(
          childName: 'agents',
          parentToolRoot: projectRoot,
          ownToolRoot: sessionRoot,
        );
      },
    );
  }

  Future<void> ensureSessionRuntimeInheritsTeam(
    String projectId,
    String sessionId,
    String teamId,
    String tool, {
    String? memberId,
  }) async {
    final trimmedProject = projectId.trim();
    final trimmedSession = sessionId.trim();
    final trimmedTeam = teamId.trim();
    final trimmedTool = tool.trim();
    if (trimmedProject.isEmpty ||
        trimmedSession.isEmpty ||
        trimmedTeam.isEmpty ||
        trimmedTool.isEmpty) {
      return;
    }
    await _teamInheritLocks.synchronized(
      _teamInheritLockKey(trimmedTeam, trimmedTool),
      () async {
        await _ensureTeamInheritsAppUnlocked(trimmedTeam, trimmedTool);
        final sessionRoot = sessionRuntimeToolDir(
          trimmedProject,
          trimmedSession,
          trimmedTool,
          memberId: memberId,
        );
        await _fs.ensureDir(sessionRoot);
        final teamRoot = teamToolDir(trimmedTeam, trimmedTool);
        await _ensureInheritedChild(
          childName: 'agents',
          parentToolRoot: teamRoot,
          ownToolRoot: sessionRoot,
        );
      },
    );
  }

  Future<String?> provisionSessionPluginsFromTeam(
    String projectId,
    String sessionId,
    String teamId,
    String tool, {
    String? memberId,
  }) async {
    final trimmedProject = projectId.trim();
    final trimmedSession = sessionId.trim();
    final trimmedTeam = teamId.trim();
    final trimmedTool = tool.trim();
    if (trimmedProject.isEmpty ||
        trimmedSession.isEmpty ||
        trimmedTeam.isEmpty ||
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
      teamPluginsDir: teamPluginsDir(trimmedTeam),
      memberPluginsDir: sessionRuntimePluginsDir(
        trimmedProject,
        trimmedSession,
        trimmedTool,
        memberId: memberId,
      ),
      paths: paths,
    );
  }

  Future<String?> provisionSessionPluginsFromProject(
    String projectId,
    String sessionId,
    String tool, {
    String? memberId,
  }) async {
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
      teamPluginsDir: projectConfigPluginsDir(trimmedProject),
      memberPluginsDir: sessionRuntimePluginsDir(
        trimmedProject,
        trimmedSession,
        trimmedTool,
        memberId: memberId,
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
