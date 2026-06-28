import '../../utils/trusted_project_paths.dart';
import '../cli/registry/config_profile/claude_config_profile_capability.dart';
import '../cli/registry/config_profile/codex_config_profile_capability.dart';
import '../cli/registry/config_profile/cursor_config_profile_capability.dart';
import '../cli/registry/config_profile/flashskyai_config_profile_capability.dart';
import '../io/filesystem.dart';
import '../provider/codex/codex_project_trust_toml.dart';
import '../provider/cursor/cursor_session_config_dir.dart';
import '../provider/cursor/cursor_workspace_trust_provisioner.dart';
import '../storage/runtime_layout.dart';
import 'config_profile_infrastructure.dart';

/// Pre-trusts workspace directories at the workspace config layer so the first
/// session launch does not block on interactive CLI trust dialogs.
final class WorkspaceTrustProvisioner {
  WorkspaceTrustProvisioner({
    required RuntimeLayout layout,
    required Filesystem fs,
    ConfigProfileInfrastructure? profileInfra,
  }) : _layout = layout,
       _fs = fs,
       _profileInfra =
           profileInfra ??
           ConfigProfileInfrastructure(
             basePath: layout.teampilotRoot,
             layout: layout,
             fs: fs,
           );

  final RuntimeLayout _layout;
  final Filesystem _fs;
  final ConfigProfileInfrastructure _profileInfra;

  Future<void> provisionWorkspace({
    required String workspaceId,
    required Iterable<String> directories,
    Iterable<String> tools = const [
      ClaudeConfigProfileCapability.toolId,
      FlashskyaiConfigProfileCapability.toolId,
      CodexConfigProfileCapability.toolId,
      CursorConfigProfileCapability.toolId,
    ],
  }) async {
    final paths = [
      for (final directory in directories)
        if (directory.trim().isNotEmpty) directory.trim(),
    ];
    if (paths.isEmpty) return;

    final toolIds = {
      for (final tool in tools)
        if (tool.trim().isNotEmpty) tool.trim(),
    };
    final tasks = <Future<void>>[];
    if (toolIds.contains(ClaudeConfigProfileCapability.toolId)) {
      tasks.add(
        _provisionClaudeFamilyMetadata(
          workspaceId: workspaceId,
          tool: ClaudeConfigProfileCapability.toolId,
          metadataFileName: ClaudeConfigProfileCapability.metadataFileName,
          defaultMetadata: ClaudeConfigProfileCapability.defaultMetadata,
          defaultProjectConfig:
              ClaudeConfigProfileCapability.defaultProjectConfig,
          directories: paths,
        ),
      );
    }
    if (toolIds.contains(FlashskyaiConfigProfileCapability.toolId)) {
      tasks.add(
        _provisionClaudeFamilyMetadata(
          workspaceId: workspaceId,
          tool: FlashskyaiConfigProfileCapability.toolId,
          metadataFileName: FlashskyaiConfigProfileCapability.metadataFileName,
          defaultMetadata: FlashskyaiConfigProfileCapability.defaultMetadata,
          defaultProjectConfig:
              FlashskyaiConfigProfileCapability.defaultProjectConfig,
          directories: paths,
        ),
      );
    }
    if (toolIds.contains(CodexConfigProfileCapability.toolId)) {
      tasks.add(
        _provisionCodexTrust(workspaceId: workspaceId, directories: paths),
      );
    }
    if (toolIds.contains(CursorConfigProfileCapability.toolId)) {
      tasks.add(
        _provisionCursorTrust(workspaceId: workspaceId, directories: paths),
      );
    }
    if (tasks.isEmpty) return;
    await Future.wait(tasks);
  }

  Future<void> _provisionClaudeFamilyMetadata({
    required String workspaceId,
    required String tool,
    required String metadataFileName,
    required Map<String, Object?> defaultMetadata,
    required Map<String, Object?> defaultProjectConfig,
    required List<String> directories,
  }) {
    return _profileInfra.writeWorkspaceTrustedProjectsMetadata(
      workspaceId: workspaceId,
      tool: tool,
      metadataFileName: metadataFileName,
      defaultMetadata: defaultMetadata,
      defaultProjectConfig: defaultProjectConfig,
      directories: directories,
    );
  }

  Future<void> _provisionCodexTrust({
    required String workspaceId,
    required List<String> directories,
  }) async {
    final codexDir = _layout.workspaceConfigToolDir(
      workspaceId,
      CodexConfigProfileCapability.toolId,
    );
    await _fs.ensureDir(codexDir);
    final configPath = _fs.pathContext.join(codexDir, 'config.toml');
    final existing = await _fs.readString(configPath) ?? '';
    final keys = await collectTrustedProjectKeys(
      fs: _fs,
      directories: directories,
    );
    final updated = CodexProjectTrustToml.applyTrustedDirectories(
      existing,
      keys,
    );
    if (updated == existing.trim()) return;
    await _fs.atomicWrite(configPath, updated);
  }

  Future<void> _provisionCursorTrust({
    required String workspaceId,
    required List<String> directories,
  }) async {
    final toolDir = _layout.workspaceConfigToolDir(
      workspaceId,
      CursorConfigProfileCapability.toolId,
    );
    final homeRoot = _fs.pathContext.join(
      toolDir,
      CursorSessionConfigDir.homeSegment,
    );
    await CursorWorkspaceTrustProvisioner(fs: _fs).provision(
      homeRoot: homeRoot,
      workspacePaths: {
        for (final directory in directories)
          ...await collectTrustedProjectKeys(fs: _fs, directories: [directory]),
      },
    );
  }
}
