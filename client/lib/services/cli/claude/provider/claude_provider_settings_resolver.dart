import '../../../../models/app_provider_config.dart';
import '../../../../models/cli_preset.dart';
import '../../../../models/team_config.dart';
import '../../../../models/team_launch_config.dart';
import '../../../../repositories/app_provider_repository.dart';
import '../../preset_resolver.dart';
import '../../../provider/tool_config_generator.dart';

/// Resolves Claude Code settings from the Claude provider catalog.
class ClaudeProviderSettingsResolver {
  ClaudeProviderSettingsResolver({
    required String basePath,
    AppProviderRepository? repository,
    ToolConfigGenerator? generator,
  }) : _repository = repository ?? AppProviderRepository(basePath: basePath),
       _generator = generator ?? const ToolConfigGenerator();

  final AppProviderRepository _repository;
  final ToolConfigGenerator _generator;

  Future<Map<String, Object?>?> resolve(String? providerId) async {
    final trimmed = providerId?.trim() ?? '';
    if (trimmed.isEmpty) return null;

    final provider = await _repository.findById(CliTool.claude, trimmed);
    if (provider == null) return null;
    return _generator.buildClaudeSettings(provider);
  }

  Future<String?> resolveProviderId(
    TeamProfile team, {
    List<CliPreset> globalPresets = const [],
  }) async {
    final normalized = team.normalizedLaunchConfig();
    if (teamLaunchShape(normalized) == TeamLaunchShape.preset) {
      final bundle = resolveTeamLaunchBundle(
        team: normalized,
        globalPresets: globalPresets,
      );
      final fromPreset = bundle.provider.trim();
      return fromPreset.isNotEmpty ? fromPreset : null;
    }

    final fromTeam = normalized.providerIdsByTool['claude']?.trim() ?? '';
    if (fromTeam.isNotEmpty) return fromTeam;

    for (final member in normalized.members) {
      final fromMember = member.provider.trim();
      if (fromMember.isNotEmpty) {
        final provider = await _repository.findById(CliTool.claude, fromMember);
        if (provider != null) return fromMember;
      }
    }

    final claudeProviders = await _listClaudeProviders();
    if (claudeProviders.length == 1) return claudeProviders.first.id;
    return null;
  }

  /// Team-level Claude settings from the active launch shape only.
  Future<Map<String, Object?>?> resolveTeamClaudeSettings(
    TeamProfile team, {
    List<CliPreset> globalPresets = const [],
  }) async {
    return resolve(await resolveProviderId(team, globalPresets: globalPresets));
  }

  /// Member settings: launch-resolved [member] provider, then [teamClaudeSettings].
  Future<Map<String, Object?>?> resolveMemberClaudeSettings({
    required TeamProfile team,
    required TeamMemberConfig member,
    Map<String, Object?>? teamClaudeSettings,
    List<CliPreset> globalPresets = const [],
  }) async {
    final fromMember = await resolve(member.provider);
    if (fromMember != null) return fromMember;

    if (teamClaudeSettings != null) return teamClaudeSettings;

    return resolveTeamClaudeSettings(team, globalPresets: globalPresets);
  }

  Future<List<AppProviderConfig>> _listClaudeProviders() async {
    return _repository.loadProviders(CliTool.claude);
  }
}
