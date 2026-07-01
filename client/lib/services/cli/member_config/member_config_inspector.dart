import '../preset_resolver.dart';
import '../../../models/cli_preset.dart';
import '../../../models/team_config.dart';
import '../../io/filesystem.dart';
import '../../storage/app_storage.dart';
import '../../storage/runtime_layout.dart';
import '../../storage/runtime_context.dart' show RuntimeContext;
import '../../team/claude_team_roster_service.dart';
import '../registry/capabilities/cli_config_layout_capability.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/cli_tool_registry.dart';
import 'member_config_detail.dart';

/// Resolves a team member's real CLI CONFIG_DIR (runtime dir, with team-layer
/// fallback) and reads it via the CLI's [MemberConfigInspectionCapability].
class MemberConfigInspector {
  MemberConfigInspector({
    RuntimeLayout? layout,
    Filesystem? fs,
    CliToolRegistry? registry,
  })  : _fs = fs ?? AppStorage.fs,
        _layout = layout ??
            RuntimeLayout(
              teampilotRoot: AppStorage.appDataRoot,
              fs: fs ?? AppStorage.fs,
            ),
        _registry = registry ?? CliToolRegistry.builtIn();

  final Filesystem _fs;
  final RuntimeLayout _layout;
  final CliToolRegistry _registry;

  Future<MemberConfigDetail> inspect({
    required String workspaceId,
    required String sessionId,
    required TeamProfile team,
    required TeamMemberConfig member,
    RuntimeContext? workContext,
    List<CliPreset> globalPresets = const [],
  }) async {
    final cli = memberLaunchCli(
      team: team,
      member: member,
      globalPresets: globalPresets,
    );
    final tool = cli.value;
    final fs = workContext?.filesystem ?? _fs;
    final layout = workContext?.layout ?? _layout;

    final resolved = await _resolveDir(
      workspaceId: workspaceId,
      sessionId: sessionId,
      team: team,
      member: member,
      tool: tool,
      layout: layout,
      fs: fs,
    );
    if (resolved == null) {
      return MemberConfigDetail.none(cli: cli);
    }

    final capability =
        _registry.capability<MemberConfigInspectionCapability>(cli) ??
            const DefaultMemberConfigInspection();

    return capability.inspect(
      MemberConfigContext(
        cli: cli,
        configDir: resolved.dir,
        sourceLayer: resolved.layer,
        mcpSnapshotPath: layout.identityMcpServersFile(team.id),
        provider: member.provider,
        model: member.model,
        fs: fs,
      ),
    );
  }

  Future<_ResolvedDir?> _resolveDir({
    required String workspaceId,
    required String sessionId,
    required TeamProfile team,
    required TeamMemberConfig member,
    required String tool,
    required RuntimeLayout layout,
    required Filesystem fs,
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedWorkspaceId.isNotEmpty && trimmedSessionId.isNotEmpty) {
      final memberId = team.teamMode == TeamMode.mixed
          ? ClaudeTeamRosterService.safeClaudePathSegment(member.id)
          : null;
      final cli = CliTool.tryParse(tool);
      final runtimeDir = cli != null
          ? sessionConfigDirForTool(
              cli,
              layout,
              workspaceId: trimmedWorkspaceId,
              sessionId: trimmedSessionId,
              memberId: memberId,
            )
          : layout.sessionRuntimeToolDir(
              trimmedWorkspaceId,
              trimmedSessionId,
              tool,
              memberId: memberId,
            );
      if ((await fs.stat(runtimeDir)).isDirectory) {
        return _ResolvedDir(runtimeDir, MemberConfigSourceLayer.runtime);
      }
    }
    final teamDir = layout.identityToolDir(team.id, tool);
    if ((await fs.stat(teamDir)).isDirectory) {
      return _ResolvedDir(teamDir, MemberConfigSourceLayer.team);
    }
    return null;
  }
}

class _ResolvedDir {
  const _ResolvedDir(this.dir, this.layer);
  final String dir;
  final MemberConfigSourceLayer layer;
}
