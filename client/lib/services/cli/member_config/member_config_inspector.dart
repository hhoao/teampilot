import '../../../models/team_config.dart';
import '../../io/filesystem.dart';
import '../../storage/app_storage.dart';
import '../../storage/runtime_storage_context.dart';
import '../cli_data_layout.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/cli_tool_registry.dart';
import '../registry/config_profile/config_profile_scope.dart';
import 'member_config_detail.dart';

/// Resolves a team member's real CLI CONFIG_DIR (runtime dir, with team-layer
/// fallback) and reads it via the CLI's [MemberConfigInspectionCapability].
class MemberConfigInspector {
  MemberConfigInspector({
    CliDataLayout? layout,
    Filesystem? fs,
    CliToolRegistry? registry,
  })  : _fs = fs ?? AppStorage.fs,
        _layout = layout ??
            CliDataLayout(
              teampilotRoot: RuntimeStorageContext.current.appDataRoot,
              fs: fs ?? AppStorage.fs,
            ),
        _registry = registry ?? CliToolRegistry.builtIn();

  final Filesystem _fs;
  final CliDataLayout _layout;
  final CliToolRegistry _registry;

  Future<MemberConfigDetail> inspect({
    required TeamConfig team,
    required TeamMemberConfig member,
    required String cliTeamName,
  }) async {
    final cli = member.cliWithin(team);
    final tool = cli.value;

    final resolved = await _resolveDir(
      team: team,
      member: member,
      cliTeamName: cliTeamName.trim(),
      tool: tool,
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
        mcpSnapshotPath: _layout.teamMcpServersFile(team.id),
        provider: member.provider,
        model: member.model,
        fs: _fs,
      ),
    );
  }

  Future<_ResolvedDir?> _resolveDir({
    required TeamConfig team,
    required TeamMemberConfig member,
    required String cliTeamName,
    required String tool,
  }) async {
    if (cliTeamName.isNotEmpty) {
      final dirId = team.teamMode == TeamMode.mixed
          ? mixedModeMemberScopeSessionId(_fs.pathContext, cliTeamName, member)
          : cliTeamName;
      final runtimeDir = _layout.memberToolDir(team.id, dirId, tool);
      if ((await _fs.stat(runtimeDir)).isDirectory) {
        return _ResolvedDir(runtimeDir, MemberConfigSourceLayer.runtime);
      }
    }
    final teamDir = _layout.teamToolDir(team.id, tool);
    if ((await _fs.stat(teamDir)).isDirectory) {
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
