import '../../../models/app_provider_config.dart';
import '../../../models/team_config.dart';
import '../../../repositories/app_provider_repository.dart';

/// Resolves Cursor providers from the app catalog for session launch.
final class CursorProviderSettingsResolver {
  CursorProviderSettingsResolver({
    required String basePath,
    AppProviderRepository? repository,
  }) : _repository = repository ?? AppProviderRepository(basePath: basePath);

  final AppProviderRepository _repository;

  Future<AppProviderConfig?> findById(String? providerId) async {
    final trimmed = providerId?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return _repository.findById(CliTool.cursor, trimmed);
  }

  Future<String?> resolveProviderId(
    TeamIdentity team, {
    TeamMemberConfig? member,
  }) async {
    final selected = member;
    if (selected != null && selected.isValid) {
      final fromMember = selected.provider.trim();
      if (fromMember.isNotEmpty) {
        final provider = await findById(fromMember);
        if (provider != null) return fromMember;
      }
    }

    final fromTeam = team.providerIdsByTool['cursor']?.trim() ?? '';
    if (fromTeam.isNotEmpty) return fromTeam;

    for (final rosterMember in team.members) {
      final fromMember = rosterMember.provider.trim();
      if (fromMember.isEmpty) continue;
      final provider = await findById(fromMember);
      if (provider != null) return fromMember;
    }

    final cursorProviders = await _repository.loadProviders(CliTool.cursor);
    if (cursorProviders.length == 1) return cursorProviders.first.id;
    return null;
  }

  /// Provider for the process about to launch: member binding, then team default.
  Future<AppProviderConfig?> resolveForLaunch({
    required TeamIdentity team,
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
}
