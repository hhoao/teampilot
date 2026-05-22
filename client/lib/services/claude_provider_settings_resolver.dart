import '../models/app_provider_config.dart';
import '../models/team_config.dart';
import '../repositories/app_provider_repository.dart';
import 'tool_config_generator.dart';

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

    final provider = await _repository.findById(AppProviderCli.claude, trimmed);
    if (provider == null) return null;
    return _generator.buildClaudeSettings(provider);
  }

  Future<String?> resolveProviderId(TeamConfig team) async {
    final fromTeam = team.providerIdsByTool['claude']?.trim() ?? '';
    if (fromTeam.isNotEmpty) return fromTeam;

    for (final member in team.members) {
      final fromMember = member.provider.trim();
      if (fromMember.isNotEmpty) {
        final provider = await _repository.findById(
          AppProviderCli.claude,
          fromMember,
        );
        if (provider != null) return fromMember;
      }
    }

    final claudeProviders = await _listClaudeProviders();
    if (claudeProviders.length == 1) return claudeProviders.first.id;
    return null;
  }

  /// Team-level Claude settings: team tool binding, then any member id, then sole claude provider.
  Future<Map<String, Object?>?> resolveTeamClaudeSettings(
    TeamConfig team,
  ) async {
    final fromTeam = await resolve(team.providerIdsByTool['claude']);
    if (fromTeam != null) return fromTeam;

    for (final member in team.members) {
      final fromMember = await resolve(member.provider);
      if (fromMember != null) return fromMember;
    }

    final claudeProviders = await _listClaudeProviders();
    if (claudeProviders.length == 1) {
      return _generator.buildClaudeSettings(claudeProviders.first);
    }
    return null;
  }

  /// Member settings: member provider, then [teamClaudeSettings], then team-level fallbacks.
  Future<Map<String, Object?>?> resolveMemberClaudeSettings({
    required TeamConfig team,
    required TeamMemberConfig member,
    Map<String, Object?>? teamClaudeSettings,
  }) async {
    final fromMember = await resolve(member.provider);
    if (fromMember != null) return fromMember;

    if (teamClaudeSettings != null) return teamClaudeSettings;

    return resolveTeamClaudeSettings(team);
  }

  Future<List<AppProviderConfig>> _listClaudeProviders() async {
    return _repository.loadProviders(AppProviderCli.claude);
  }
}
