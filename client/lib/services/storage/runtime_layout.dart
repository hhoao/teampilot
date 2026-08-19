import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/team_config.dart';
import '../../utils/lock_pool.dart';
import '../io/filesystem.dart';
import '../session/launch_command_builder.dart';
import '../storage/app_storage.dart';
import 'workspace_layout.dart';

/// Tools with a `cli-defaults/{tool}/` tree (see [RuntimeLayout]).
final List<String> runtimeLayoutDefaultTools = CliTool.values
    .map((c) => c.value)
    .toList(growable: false);

/// Canonical paths for CLI **runtime config** under TeamPilot app data.
///
/// See [docs/workspace-storage-layout.md] for the full tree. [WorkspaceLayout]
/// owns UI metadata; this class owns `cli-defaults/`, `identities-runtime/`, and
/// session/runtime inheritance under each workspace session.
class RuntimeLayout {
  RuntimeLayout({
    required this.teampilotRoot,
    Filesystem? fs,
    WorkspaceLayout? workspace,
  }) : _fs = fs ?? AppStorage.fs,
       workspace =
           workspace ?? WorkspaceLayout(teampilotRoot: teampilotRoot, fs: fs);

  final String teampilotRoot;
  final Filesystem _fs;
  final WorkspaceLayout workspace;

  static final _identityInheritLocks = LockPool();
  static final _workspaceInheritLocks = LockPool();

  p.Context get _pathContext => _fs.pathContext;

  String get cliDefaultsDir => _pathContext.join(teampilotRoot, 'cli-defaults');

  String get identitiesRuntimeDir =>
      _pathContext.join(teampilotRoot, 'identities-runtime');

  String appToolRoot(String tool) =>
      _pathContext.join(cliDefaultsDir, tool.trim());

  String identityRuntimeDir(String profileId) =>
      _pathContext.join(identitiesRuntimeDir, profileId.trim());

  String identityToolDir(String profileId, String tool) =>
      _pathContext.join(identityRuntimeDir(profileId), tool.trim());

  String identitySessionCounterFile(String profileId) =>
      _pathContext.join(identityRuntimeDir(profileId), 'session-counter.json');

  String identityMcpDir(String profileId) =>
      _pathContext.join(identityRuntimeDir(profileId), 'mcp');

  String identityMcpServersFile(String profileId) =>
      _pathContext.join(identityMcpDir(profileId), 'servers.json');

  String workspaceConfigToolDir(String workspaceId, String tool) =>
      workspace.workspaceConfigToolDir(workspaceId, tool);

  String sessionRuntimeToolDir(
    String workspaceId,
    String sessionId,
    String tool, {
    String? memberId,
  }) => workspace.sessionRuntimeToolDir(
    workspaceId,
    sessionId,
    tool,
    memberId: memberId,
  );

  String sessionRuntimePluginsDir(
    String workspaceId,
    String sessionId,
    String tool, {
    String? memberId,
  }) => workspace.sessionRuntimePluginsDir(
    workspaceId,
    sessionId,
    tool,
    memberId: memberId,
  );

  String sessionRuntimePluginPoolDir(
    String workspaceId,
    String sessionId,
    String tool, {
    String? memberId,
  }) => workspace.sessionRuntimePluginPoolDir(
    workspaceId,
    sessionId,
    tool,
    memberId: memberId,
  );

  String workspaceTeamRuntimeDir(String workspaceId, String teamId) =>
      workspace.workspaceTeamRuntimeDir(workspaceId, teamId);

  String workspaceRuntimeToolDir(
    String workspaceId,
    String teamId,
    String tool,
  ) => workspace.workspaceRuntimeToolDir(workspaceId, teamId, tool);

  String workspaceLifecycleManifestPath(
    String workspaceId,
    String teamId,
    String tool,
  ) => workspace.workspaceLifecycleManifestPath(workspaceId, teamId, tool);

  String workspaceRuntimeMemberToolDir(
    String workspaceId,
    String teamId,
    String memberId,
    String tool,
  ) => workspace.workspaceRuntimeMemberToolDir(
    workspaceId,
    teamId,
    memberId,
    tool,
  );

  String get appFlashskyaiLlmConfigFile =>
      _pathContext.join(appToolRoot('flashskyai'), 'llm_config.json');

  List<String> transcriptSearchRoots({
    required String workspaceId,
    required String sessionId,
    String? profileId,
    String? memberId,
    Iterable<String>? tools,
  }) {
    final trimmedIdentity = profileId?.trim() ?? '';
    final trimmedWorkspace = workspaceId.trim();
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
      if (trimmedWorkspace.isNotEmpty)
        for (final tool in tt) workspaceConfigToolDir(trimmedWorkspace, tool),
      if (trimmedWorkspace.isNotEmpty && trimmedSession.isNotEmpty)
        for (final tool in tt) ...[
          // Mixed seats nest under runtime/<member>/<tool>. Native Claude /
          // flashskyai agent teams share runtime/<tool> (no member segment) so
          // History must search both when a memberId is present.
          if (trimmedMember.isNotEmpty)
            sessionRuntimeToolDir(
              trimmedWorkspace,
              trimmedSession,
              tool,
              memberId: trimmedMember,
            ),
          sessionRuntimeToolDir(trimmedWorkspace, trimmedSession, tool),
        ],
    ];
  }

  static String workspaceBucketForPrimaryPath(String primaryPath) {
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

  static String _identityInheritLockKey(String profileId, String tool) =>
      '${profileId.trim()}|${tool.trim()}';

  static String _workspaceInheritLockKey(String workspaceId, String tool) =>
      'workspace|${workspaceId.trim()}|${tool.trim()}';

  Future<void> ensureIdentityInheritsApp(String profileId, String tool) async {
    final trimmedIdentity = profileId.trim();
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

  Future<void> ensureWorkspaceConfigInheritsApp(
    String workspaceId,
    String tool,
  ) async {
    final trimmedWorkspace = workspaceId.trim();
    final trimmedTool = tool.trim();
    if (trimmedWorkspace.isEmpty || trimmedTool.isEmpty) return;
    await _workspaceInheritLocks.synchronized(
      _workspaceInheritLockKey(trimmedWorkspace, trimmedTool),
      () => _ensureWorkspaceConfigInheritsAppUnlocked(
        trimmedWorkspace,
        trimmedTool,
      ),
    );
  }

  Future<void> _ensureWorkspaceConfigInheritsAppUnlocked(
    String trimmedWorkspace,
    String trimmedTool,
  ) async {
    await ensureAppToolLayout(trimmedTool);
    final workspaceRoot = workspaceConfigToolDir(trimmedWorkspace, trimmedTool);
    await _fs.ensureDir(workspaceRoot);
    await _ensureInheritedChild(
      childName: 'agents',
      parentToolRoot: appToolRoot(trimmedTool),
      ownToolRoot: workspaceRoot,
    );
  }

  Future<void> ensureSessionRuntimeInheritsWorkspace(
    String workspaceId,
    String sessionId,
    String tool, {
    String? memberId,
  }) async {
    final trimmedWorkspace = workspaceId.trim();
    final trimmedSession = sessionId.trim();
    final trimmedTool = tool.trim();
    if (trimmedWorkspace.isEmpty ||
        trimmedSession.isEmpty ||
        trimmedTool.isEmpty) {
      return;
    }
    await _workspaceInheritLocks.synchronized(
      _workspaceInheritLockKey(trimmedWorkspace, trimmedTool),
      () async {
        await _ensureWorkspaceConfigInheritsAppUnlocked(
          trimmedWorkspace,
          trimmedTool,
        );
        final sessionRoot = sessionRuntimeToolDir(
          trimmedWorkspace,
          trimmedSession,
          trimmedTool,
          memberId: memberId,
        );
        await _fs.ensureDir(sessionRoot);
        final workspaceRoot = workspaceConfigToolDir(
          trimmedWorkspace,
          trimmedTool,
        );
        await _ensureInheritedChild(
          childName: 'agents',
          parentToolRoot: workspaceRoot,
          ownToolRoot: sessionRoot,
        );
      },
    );
  }

  Future<void> ensureSessionRuntimeInheritsIdentity(
    String workspaceId,
    String sessionId,
    String profileId,
    String tool, {
    String? memberId,
  }) async {
    final trimmedWorkspace = workspaceId.trim();
    final trimmedSession = sessionId.trim();
    final trimmedIdentity = profileId.trim();
    final trimmedTool = tool.trim();
    if (trimmedWorkspace.isEmpty ||
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
          trimmedWorkspace,
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

  Future<void> ensureSessionInheritsOpencodePluginDeps(
    String workspaceId,
    String sessionId, {
    String? memberId,
  }) async {
    final trimmedWorkspace = workspaceId.trim();
    final trimmedSession = sessionId.trim();
    if (trimmedWorkspace.isEmpty || trimmedSession.isEmpty) return;

    await _workspaceInheritLocks.synchronized(
      _workspaceInheritLockKey(trimmedWorkspace, 'opencode'),
      () async {
        await ensureAppToolLayout('opencode');
        final sessionRoot = sessionRuntimeToolDir(
          trimmedWorkspace,
          trimmedSession,
          'opencode',
          memberId: memberId,
        );
        await _fs.ensureDir(sessionRoot);
        final appRoot = appToolRoot('opencode');

        await _ensureInheritedChild(
          childName: 'node_modules',
          parentToolRoot: appRoot,
          ownToolRoot: sessionRoot,
        );

        // Files cannot use _ensureInheritedChild (ensureDir/copyTree).
        // Also inherit package-lock.json so OpenCode's Npm.checkDirty does not
        // reify a second ~55MB tree into the session config dir on every launch.
        await _ensureInheritedFile(
          fileName: 'package.json',
          parentToolRoot: appRoot,
          ownToolRoot: sessionRoot,
        );
        await _ensureInheritedFile(
          fileName: 'package-lock.json',
          parentToolRoot: appRoot,
          ownToolRoot: sessionRoot,
        );
      },
    );
  }

  /// Links `session …/codex/.tmp/plugins` → `cli-defaults/codex/.tmp/plugins`.
  ///
  /// When the shared tree is missing/empty and the session still has a real
  /// plugins dir, promotes that dir into the shared root first (one-time
  /// migration), then symlinks. Codex writes through the link into the shared
  /// cache.
  Future<void> ensureSessionInheritsCodexTmpPlugins(
    String workspaceId,
    String sessionId, {
    String? memberId,
  }) async {
    final trimmedWorkspace = workspaceId.trim();
    final trimmedSession = sessionId.trim();
    if (trimmedWorkspace.isEmpty || trimmedSession.isEmpty) return;

    await _workspaceInheritLocks.synchronized(
      _workspaceInheritLockKey(trimmedWorkspace, 'codex'),
      () async {
        await ensureAppToolLayout('codex');
        final appTmp = _pathContext.join(appToolRoot('codex'), '.tmp');
        final sharedPlugins = _pathContext.join(appTmp, 'plugins');
        final sessionRoot = sessionRuntimeToolDir(
          trimmedWorkspace,
          trimmedSession,
          'codex',
          memberId: memberId,
        );
        final sessionTmp = _pathContext.join(sessionRoot, '.tmp');
        final sessionPlugins = _pathContext.join(sessionTmp, 'plugins');

        await _fs.ensureDir(appTmp);
        await _maybePromoteCodexPluginsToShared(
          sharedPlugins: sharedPlugins,
          sessionPlugins: sessionPlugins,
        );
        await _fs.ensureDir(sessionTmp);
        await _ensureInheritedChild(
          childName: 'plugins',
          parentToolRoot: appTmp,
          ownToolRoot: sessionTmp,
        );
      },
    );
  }

  Future<void> _maybePromoteCodexPluginsToShared({
    required String sharedPlugins,
    required String sessionPlugins,
  }) async {
    final sharedStat = await _fs.stat(sharedPlugins);
    final sessionStat = await _fs.stat(sessionPlugins);
    final sessionIsRealDir =
        sessionStat.exists && sessionStat.isDirectory && !sessionStat.isSymlink;
    if (!sessionIsRealDir) {
      if (!sharedStat.exists) {
        await _fs.ensureDir(sharedPlugins);
      }
      return;
    }

    final sharedMissing = !sharedStat.exists;
    final sharedEmpty =
        sharedStat.exists &&
        sharedStat.isDirectory &&
        !sharedStat.isSymlink &&
        (await _fs.listDir(sharedPlugins)).isEmpty;
    if (sharedMissing || sharedEmpty) {
      if (sharedStat.exists) {
        await _fs.removeRecursive(sharedPlugins);
      }
      await _fs.ensureDir(_pathContext.dirname(sharedPlugins));
      await _fs.rename(sessionPlugins, sharedPlugins);
      return;
    }
  }

  Future<void> _ensureInheritedFile({
    required String fileName,
    required String parentToolRoot,
    required String ownToolRoot,
  }) async {
    final source = _pathContext.join(parentToolRoot, fileName);
    final target = _pathContext.join(ownToolRoot, fileName);
    if (!(await _fs.stat(source)).exists) return;
    if (await _inheritLinkCurrent(source: source, target: target)) {
      return;
    }
    if ((await _fs.stat(target)).exists) {
      await _fs.removeRecursive(target);
    }
    final linked = await _fs.createSymlink(target: source, linkPath: target);
    if (!linked) {
      await _fs.copyFile(source, target);
    }
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
      await _fs.listDir(path);
      return true;
    } on Object {
      return false;
    }
  }

  Future<bool> _inheritLinkCurrent({
    required String source,
    required String target,
  }) async {
    final targetStat = await _fs.lstat(target);
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
      final resolvedTarget = await _fs.resolveSymlink(target);
      if (resolvedTarget == null) return false;
      return _pathContext.normalize(resolvedTarget) == normalizedSource;
    }
    return false;
  }
}
