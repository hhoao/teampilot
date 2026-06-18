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
/// owns UI metadata; this class owns `cli-defaults/`, `identities-runtime/`, and
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

  static final _identityInheritLocks = LockPool();
  static final _projectInheritLocks = LockPool();

  p.Context get _pathContext => _fs.pathContext;

  String get cliDefaultsDir => _pathContext.join(teampilotRoot, 'cli-defaults');

  String get identitiesRuntimeDir =>
      _pathContext.join(teampilotRoot, 'identities-runtime');

  String appToolRoot(String tool) =>
      _pathContext.join(cliDefaultsDir, tool.trim());

  String identityRuntimeDir(String identityId) =>
      _pathContext.join(identitiesRuntimeDir, identityId.trim());

  String identityToolDir(String identityId, String tool) =>
      _pathContext.join(identityRuntimeDir(identityId), tool.trim());

  String identitySessionCounterFile(String identityId) =>
      _pathContext.join(identityRuntimeDir(identityId), 'session-counter.json');

  String identityPluginsDir(String identityId) =>
      _pathContext.join(identityToolDir(identityId, 'flashskyai'), 'plugins');

  String identityMcpDir(String identityId) =>
      _pathContext.join(identityRuntimeDir(identityId), 'mcp');

  String identityMcpServersFile(String identityId) =>
      _pathContext.join(identityMcpDir(identityId), 'servers.json');

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
    String? identityId,
    String? memberId,
    Iterable<String>? tools,
  }) {
    final trimmedIdentity = identityId?.trim() ?? '';
    final trimmedProject = projectId.trim();
    final trimmedSession = sessionId.trim();
    final trimmedMember = memberId?.trim() ?? '';
    final tt = (tools ?? runtimeLayoutDefaultTools)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return [
      for (final tool in tt) appToolRoot(tool),
      if (trimmedIdentity.isNotEmpty)
        for (final tool in tt) identityToolDir(trimmedIdentity, tool),
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

  static String _identityInheritLockKey(String identityId, String tool) =>
      '${identityId.trim()}|${tool.trim()}';

  static String _projectInheritLockKey(String projectId, String tool) =>
      'project|${projectId.trim()}|${tool.trim()}';

  Future<void> ensureIdentityInheritsApp(String identityId, String tool) async {
    final trimmedIdentity = identityId.trim();
    final trimmedTool = tool.trim();
    if (trimmedIdentity.isEmpty || trimmedTool.isEmpty) return;
    await _identityInheritLocks.synchronized(
      _identityInheritLockKey(trimmedIdentity, trimmedTool),
      () => _ensureIdentityInheritsAppUnlocked(trimmedIdentity, trimmedTool),
    );
  }

  Future<void> _ensureIdentityInheritsAppUnlocked(
    String trimmedIdentity,
    String trimmedTool,
  ) async {
    await ensureAppToolLayout(trimmedTool);
    final identityRoot = identityToolDir(trimmedIdentity, trimmedTool);
    await _fs.ensureDir(identityRoot);
    await _ensureInheritedChild(
      childName: 'agents',
      parentToolRoot: appToolRoot(trimmedTool),
      ownToolRoot: identityRoot,
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

  Future<void> ensureSessionRuntimeInheritsIdentity(
    String projectId,
    String sessionId,
    String identityId,
    String tool, {
    String? memberId,
  }) async {
    final trimmedProject = projectId.trim();
    final trimmedSession = sessionId.trim();
    final trimmedIdentity = identityId.trim();
    final trimmedTool = tool.trim();
    if (trimmedProject.isEmpty ||
        trimmedSession.isEmpty ||
        trimmedIdentity.isEmpty ||
        trimmedTool.isEmpty) {
      return;
    }
    await _identityInheritLocks.synchronized(
      _identityInheritLockKey(trimmedIdentity, trimmedTool),
      () async {
        await _ensureIdentityInheritsAppUnlocked(trimmedIdentity, trimmedTool);
        final sessionRoot = sessionRuntimeToolDir(
          trimmedProject,
          trimmedSession,
          trimmedTool,
          memberId: memberId,
        );
        await _fs.ensureDir(sessionRoot);
        final identityRoot = identityToolDir(trimmedIdentity, trimmedTool);
        await _ensureInheritedChild(
          childName: 'agents',
          parentToolRoot: identityRoot,
          ownToolRoot: sessionRoot,
        );
      },
    );
  }

  Future<String?> provisionSessionPluginsFromIdentity(
    String projectId,
    String sessionId,
    String identityId,
    String tool, {
    String? memberId,
  }) async {
    final trimmedProject = projectId.trim();
    final trimmedSession = sessionId.trim();
    final trimmedIdentity = identityId.trim();
    final trimmedTool = tool.trim();
    if (trimmedProject.isEmpty ||
        trimmedSession.isEmpty ||
        trimmedIdentity.isEmpty ||
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
      teamPluginsDir: identityPluginsDir(trimmedIdentity),
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
