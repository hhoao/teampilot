import '../../../models/app_provider_config.dart';
import '../../../models/team_config.dart';
import '../../../repositories/app_provider_repository.dart';

/// Resolves opencode providers from the app catalog for session launch.
///
/// Mirrors [CodexProviderSettingsResolver]: member binding wins, then team
/// default, then a lone provider in the catalog.
final class OpencodeProviderSettingsResolver {
  OpencodeProviderSettingsResolver({
    required String basePath,
    AppProviderRepository? repository,
  }) : _repository = repository ?? AppProviderRepository(basePath: basePath);

  final AppProviderRepository _repository;

  Future<AppProviderConfig?> findById(String? providerId) async {
    final trimmed = providerId?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return _repository.findById(CliTool.opencode, trimmed);
  }

  Future<String?> resolveProviderId(
    TeamConfig team, {
    TeamMemberConfig? member,
  }) async {
    final fromTeam = team.providerIdsByTool['opencode']?.trim() ?? '';
    if (fromTeam.isNotEmpty) return fromTeam;

    final selected = member;
    if (selected != null && selected.isValid) {
      final fromMember = selected.provider.trim();
      if (fromMember.isNotEmpty && await findById(fromMember) != null) {
        return fromMember;
      }
    }

    for (final rosterMember in team.members) {
      final fromMember = rosterMember.provider.trim();
      if (fromMember.isEmpty) continue;
      if (await findById(fromMember) != null) return fromMember;
    }

    final providers = await _repository.loadProviders(CliTool.opencode);
    if (providers.length == 1) return providers.first.id;
    return null;
  }

  /// Provider for the process about to launch: member binding, then team default.
  Future<AppProviderConfig?> resolveForLaunch({
    required TeamConfig team,
    TeamMemberConfig? member,
  }) async {
    final selected = member;
    if (selected != null && selected.isValid) {
      final fromMember = await findById(selected.provider);
      if (fromMember != null) return fromMember;
    }

    final teamId = await resolveProviderId(team, member: member);
    if (teamId != null) return findById(teamId);

    return null;
  }

  /// The single catalogued provider, if exactly one exists (standalone default).
  Future<AppProviderConfig?> resolveSole() async {
    final providers = await _repository.loadProviders(CliTool.opencode);
    if (providers.length == 1) return providers.first;
    return null;
  }
}
