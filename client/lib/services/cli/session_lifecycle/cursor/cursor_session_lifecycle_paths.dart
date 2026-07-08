import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../io/filesystem.dart';
import '../../../provider/cursor/cursor_home_layout.dart';
import '../../../provider/cursor/cursor_member_home_passthrough.dart';
import '../../../provider/cursor/cursor_workspace_trust.dart';
import '../../../provider/cursor/cursor_workspace_warm_tier.dart';
import '../../../storage/runtime_layout.dart';
import '../../registry/resources/cursor_resource_capability.dart';

/// Session lifecycle disk layout for mixed-mode cursor warm tier + member overlay.
final class CursorSessionLifecyclePaths {
  CursorSessionLifecyclePaths({
    required Filesystem fs,
    required RuntimeLayout layout,
    required String workspaceId,
    required String teamId,
    required String workingDirectory,
    CursorHomeLayout? homeLayout,
  }) : _fs = fs,
       _layout = layout,
       _workspaceId = workspaceId.trim(),
       _teamId = teamId.trim(),
       _workingDirectory = workingDirectory.trim(),
       _homeLayout =
           homeLayout ?? CursorHomeLayout(pathContext: fs.pathContext);

  static const tool = 'cursor';

  final Filesystem _fs;
  final RuntimeLayout _layout;
  final String _workspaceId;
  final String _teamId;
  final String _workingDirectory;
  final CursorHomeLayout _homeLayout;

  p.Context get _ctx => _fs.pathContext;

  String get workspaceSlug =>
      CursorWorkspaceTrust.slugifyWorkspacePath(_workingDirectory);

  String sharedRoot() =>
      _layout.workspaceRuntimeToolDir(_workspaceId, _teamId, tool);

  String sharedProjectsDir([String? slug]) => _ctx.join(
    sharedRoot(),
    CursorWorkspaceTrust.projectsDirName,
    (slug ?? workspaceSlug).trim(),
  );

  String sharedPluginsLocalDir() =>
      CursorWorkspaceWarmTier.pluginsLocalDir(_layout, _workspaceId, _teamId);

  String sharedPluginsMarketplacesDir() =>
      CursorWorkspaceWarmTier.pluginsMarketplacesDir(
        _layout,
        _workspaceId,
        _teamId,
      );

  String sharedInstalledPluginsFile() =>
      CursorWorkspaceWarmTier.installedPluginsFile(_layout, _workspaceId, _teamId);

  String sharedKnownMarketplacesFile() =>
      CursorWorkspaceWarmTier.knownMarketplacesFile(_layout, _workspaceId, _teamId);

  String sharedSkillsCursorDir() =>
      CursorWorkspaceWarmTier.skillsCursorDir(_layout, _workspaceId, _teamId);

  String sharedSettingsFile() =>
      CursorWorkspaceWarmTier.settingsJson(_layout, _workspaceId, _teamId);

  String sharedMcpBaseFile() =>
      CursorWorkspaceWarmTier.mcpBase(_layout, _workspaceId, _teamId);

  String memberHomeRoot(String memberId) => _ctx.join(
    _layout.workspaceRuntimeMemberToolDir(
      _workspaceId,
      _teamId,
      memberId,
      tool,
    ),
    'home',
  );

  String memberCursorDir(String memberHome) => _homeLayout.cursorDir(memberHome);

  Future<void> ensureSharedDirs() async {
    await _fs.ensureDir(sharedRoot());
    await _fs.ensureDir(sharedProjectsDir());
    await _fs.ensureDir(sharedPluginsLocalDir());
    await _fs.ensureDir(sharedPluginsMarketplacesDir());
    await _fs.ensureDir(sharedSkillsCursorDir());
  }

  String memberAuthDir(String memberHome) =>
      _homeLayout.configCursorDir(memberHome);

  String memberAuthFile(String memberHome) => _ctx.join(
    memberAuthDir(memberHome),
    CursorHomeLayout.authFileName,
  );

  Future<void> ensureMemberHomeLayout({
    required String memberId,
    required String realHomeRoot,
  }) async {
    final memberHome = memberHomeRoot(memberId);
    await _fs.ensureDir(memberHome);
    final cursorDir = memberCursorDir(memberHome);
    await _fs.ensureDir(cursorDir);
    await _fs.ensureDir(_ctx.join(cursorDir, CursorHomeLayout.rulesDirName));
    await _fs.ensureDir(_ctx.join(cursorDir, CursorHomeLayout.hooksDirName));
    await _linkMemberSharedArtifacts(memberHome: memberHome);
    await ensureMemberAuthDir(memberHome: memberHome);
    await CursorMemberHomePassthrough(fs: _fs, layout: _homeLayout).mirror(
      realHomeRoot: realHomeRoot,
      memberHomeRoot: memberHome,
    );
  }

  Future<void> ensureMemberAuthDir({required String memberHome}) async {
    await _fs.ensureDir(memberAuthDir(memberHome));
  }

  Future<void> _linkMemberSharedArtifacts({required String memberHome}) async {
    final cursorDir = memberCursorDir(memberHome);
    await _linkMemberProjects(memberHome: memberHome);
    await _fs.ensureDir(_ctx.join(cursorDir, CursorWorkspaceWarmTier.pluginsDirName));
    await _linkDirectory(
      source: sharedPluginsLocalDir(),
      target: _ctx.join(
        cursorDir,
        CursorWorkspaceWarmTier.pluginsDirName,
        CursorWorkspaceWarmTier.localPluginsSegment,
      ),
    );
    await _linkDirectory(
      source: sharedPluginsMarketplacesDir(),
      target: _ctx.join(
        cursorDir,
        CursorWorkspaceWarmTier.pluginsDirName,
        CursorWorkspaceWarmTier.marketplacesSegment,
      ),
    );
    await _linkFile(
      source: sharedInstalledPluginsFile(),
      target: _ctx.join(
        cursorDir,
        CursorWorkspaceWarmTier.pluginsDirName,
        CursorWorkspaceWarmTier.installedPluginsFileName,
      ),
    );
    await _linkFile(
      source: sharedKnownMarketplacesFile(),
      target: _ctx.join(
        cursorDir,
        CursorWorkspaceWarmTier.pluginsDirName,
        CursorWorkspaceWarmTier.knownMarketplacesFileName,
      ),
    );
    await _linkDirectory(
      source: sharedSkillsCursorDir(),
      target: _ctx.join(
        cursorDir,
        CursorResourceCapability.skillsSubdirName,
      ),
    );
    await _linkFile(
      source: sharedSettingsFile(),
      target: _ctx.join(cursorDir, CursorWorkspaceWarmTier.settingsFileName),
    );
  }

  Future<void> _linkMemberProjects({required String memberHome}) async {
    final memberProjects = _ctx.join(
      memberCursorDir(memberHome),
      CursorWorkspaceTrust.projectsDirName,
    );
    final sharedProjectsRoot = _ctx.join(
      sharedRoot(),
      CursorWorkspaceTrust.projectsDirName,
    );
    await _linkDirectory(source: sharedProjectsRoot, target: memberProjects);
  }

  Future<bool> _linkDirectory({
    required String source,
    required String target,
  }) async {
    if (!(await _fs.stat(source)).exists) {
      await _fs.ensureDir(source);
    }
    if (await _linkAlreadyPointsTo(source: source, target: target)) {
      return true;
    }
    final targetStat = await _fs.stat(target);
    if (targetStat.exists) {
      await _fs.removeRecursive(target);
    }
    final linked = await _fs.createSymlink(target: source, linkPath: target);
    if (linked) return true;
    await _fs.copyTree(source: source, destination: target);
    return false;
  }

  Future<bool> _linkFile({
    required String source,
    required String target,
  }) async {
    final sourceParent = _ctx.dirname(source);
    if (!(await _fs.stat(sourceParent)).exists) {
      await _fs.ensureDir(sourceParent);
    }
    if (await _linkAlreadyPointsTo(source: source, target: target)) {
      return true;
    }
    final targetStat = await _fs.stat(target);
    if (targetStat.exists) {
      await _fs.removeRecursive(target);
    }
    final linked = await _fs.createSymlink(target: source, linkPath: target);
    if (linked) return true;
    if ((await _fs.stat(source)).isFile) {
      final content = await _fs.readString(source);
      if (content != null) {
        await _fs.atomicWrite(target, content);
      }
    }
    return false;
  }

  Future<bool> _linkAlreadyPointsTo({
    required String source,
    required String target,
  }) async {
    final targetStat = await _fs.stat(target);
    if (!targetStat.exists) return false;
    final normalizedSource = _ctx.normalize(_ctx.absolute(source));
    if (targetStat.isSymlink) {
      final linkTarget = await _fs.readSymlinkTarget(target);
      if (linkTarget == null) return false;
      return _ctx.normalize(_ctx.absolute(linkTarget)) == normalizedSource;
    }
    if (Platform.isWindows && targetStat.isDirectory) {
      final resolvedTarget = await _fs.resolveSymlink(target);
      if (resolvedTarget == null) return false;
      return _ctx.normalize(resolvedTarget) == normalizedSource;
    }
    return false;
  }
}
