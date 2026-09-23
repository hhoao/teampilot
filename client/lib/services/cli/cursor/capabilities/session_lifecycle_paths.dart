import 'package:path/path.dart' as p;

import '../../../../models/team_config.dart';
import '../../../io/filesystem.dart';
import '../provider/cursor_home_layout.dart';
import '../provider/cursor_session_config_dir.dart';
import '../provider/cursor_windows_home_junction.dart';
import '../provider/cursor_workspace_trust.dart';
import '../provider/cursor_workspace_warm_tier.dart';
import '../../registry/capabilities/cli_session_capability.dart';
import '../../../storage/runtime_layout.dart';
import 'skill.dart';

/// Session lifecycle disk layout for mixed-mode cursor (per-member runtime).
final class CursorSessionLifecyclePaths {
  CursorSessionLifecyclePaths({
    required Filesystem fs,
    required RuntimeLayout layout,
    required String workspaceId,
    required String sessionId,
    required String teamId,
    required String workingDirectory,
    CursorHomeLayout? homeLayout,
  }) : _fs = fs,
       _layout = layout,
       _workspaceId = workspaceId.trim(),
       _sessionId = sessionId.trim(),
       _teamId = teamId.trim(),
       _workingDirectory = workingDirectory.trim(),
       _homeLayout =
           homeLayout ?? CursorHomeLayout(pathContext: fs.pathContext);

  static const tool = 'cursor';
  static const cliConfigBaseFileName = 'cli-config.base.json';

  final Filesystem _fs;
  final RuntimeLayout _layout;
  final String _workspaceId;
  final String _sessionId;
  final String _teamId;
  final String _workingDirectory;
  final CursorHomeLayout _homeLayout;

  p.Context get _ctx => _fs.pathContext;

  String get workspaceSlug =>
      CursorWorkspaceTrust.slugifyWorkspacePath(_workingDirectory);

  /// Team-scoped lifecycle manifest root (`init.json` only).
  String sharedRoot() =>
      _layout.workspaceRuntimeToolDir(_workspaceId, _teamId, tool);

  String sharedProjectsDir([String? slug]) => _ctx.join(
    sharedRoot(),
    CursorWorkspaceTrust.projectsDirName,
    (slug ?? workspaceSlug).trim(),
  );

  String memberHomeRoot(String memberId) =>
      CursorSessionConfigDir.mixedHomeRoot(
        _layout,
        workspaceId: _workspaceId,
        sessionId: _sessionId,
        memberId: memberId,
      );

  Future<String> resolvedMemberHomeRoot(String memberId) =>
      CursorWindowsHomeJunction.resolveAgentHome(
        fs: _fs,
        canonicalHome: memberHomeRoot(memberId),
      );

  String memberCursorDir(String memberHome) =>
      _homeLayout.cursorDir(memberHome);

  String memberCliConfigBasePath(String memberHome) =>
      _ctx.join(memberHome, cliConfigBaseFileName);

  String memberProjectsDir(String memberHome, [String? slug]) => _ctx.join(
    memberCursorDir(memberHome),
    CursorWorkspaceTrust.projectsDirName,
    (slug ?? workspaceSlug).trim(),
  );

  String memberPluginsLocalDir(String memberHome) => _ctx.join(
    memberCursorDir(memberHome),
    CursorWorkspaceWarmTier.pluginsDirName,
    CursorWorkspaceWarmTier.localPluginsSegment,
  );

  String memberPluginsMarketplacesDir(String memberHome) => _ctx.join(
    memberCursorDir(memberHome),
    CursorWorkspaceWarmTier.pluginsDirName,
    CursorWorkspaceWarmTier.marketplacesSegment,
  );

  String memberInstalledPluginsFile(String memberHome) => _ctx.join(
    memberCursorDir(memberHome),
    CursorWorkspaceWarmTier.pluginsDirName,
    CursorWorkspaceWarmTier.installedPluginsFileName,
  );

  String memberKnownMarketplacesFile(String memberHome) => _ctx.join(
    memberCursorDir(memberHome),
    CursorWorkspaceWarmTier.pluginsDirName,
    CursorWorkspaceWarmTier.knownMarketplacesFileName,
  );

  String memberSkillsCursorDir(String memberHome) => _ctx.join(
    memberCursorDir(memberHome),
    CursorSkillCapability.skillsSubdirName,
  );

  String memberSettingsFile(String memberHome) => _ctx.join(
    memberCursorDir(memberHome),
    CursorWorkspaceWarmTier.settingsFileName,
  );

  Future<void> ensureManifestDir() async {
    await _fs.ensureDir(sharedRoot());
  }

  /// Directory holding the member's `auth.json` — the platform credential
  /// anchor (`.config/cursor` on Linux, `AppData\Roaming\Cursor` on Windows,
  /// `.cursor` on macOS).
  String memberAuthDir(String memberHome) => _homeLayout.authDir(memberHome);

  String memberAuthFile(String memberHome) => _homeLayout.authJson(memberHome);

  Future<void> ensureMemberHomeLayout({required String memberId}) async {
    final canonicalHome = memberHomeRoot(memberId);
    final memberHome =
        await sessionMemberHomePreparedForResourceWrites(
          fs: _fs,
          tool: CliTool.cursor,
          layout: _layout,
          workspaceId: _workspaceId,
          sessionId: _sessionId,
          memberId: memberId,
        ) ??
        canonicalHome;
    await _fs.ensureDir(memberHome);
    final cursorDir = memberCursorDir(memberHome);
    await _fs.ensureDir(cursorDir);
    await _fs.ensureDir(_ctx.join(cursorDir, CursorHomeLayout.rulesDirName));
    await _fs.ensureDir(_ctx.join(cursorDir, CursorHomeLayout.hooksDirName));
    await _ensureMemberCursorResourceDirs(memberHome: memberHome);
    await ensureMemberAuthDir(memberHome: memberHome);
    // Real-$HOME passthrough is deferred to [CursorSessionLifecycleCapability]
    // after manifest flush (same as [CursorHomeProvisioner] with `realHomeRoot:
    // null` during staging). Mirroring here leaves symlinks on disk before
    // [ManifestFilesystem] staging; without a projection root those become
    // manifest entries whose targets fall outside the work plane and flush
    // materializes entire home trees on the UI isolate.
  }

  Future<void> _ensureMemberCursorResourceDirs({
    required String memberHome,
  }) async {
    await _fs.ensureDir(memberProjectsDir(memberHome));
    await _fs.ensureDir(memberPluginsLocalDir(memberHome));
    await _fs.ensureDir(memberPluginsMarketplacesDir(memberHome));
    await _fs.ensureDir(memberSkillsCursorDir(memberHome));
  }

  Future<void> ensureMemberAuthDir({required String memberHome}) async {
    await _fs.ensureDir(memberAuthDir(memberHome));
  }
}
