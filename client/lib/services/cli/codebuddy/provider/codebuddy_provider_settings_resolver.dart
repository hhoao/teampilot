import '../../../../models/app_provider_config.dart';
import '../../../../models/team_config.dart';
import '../../../../repositories/app_provider_repository.dart';
import '../../../io/filesystem.dart';
import '../../../storage/home_storage.dart';

/// Resolves CodeBuddy providers from the app catalog for session launch and
/// headless provisioning. Member binding wins, then the team default, then a
/// lone provider in the catalog.
final class CodebuddyProviderSettingsResolver {
  CodebuddyProviderSettingsResolver({
    required String basePath,
    required HomeStorage storage,
    Filesystem? fs,
    AppProviderRepository? repository,
  }) : _repository =
           repository ??
           AppProviderRepository(basePath: basePath, fs: fs, storage: storage);

  final AppProviderRepository _repository;

  Future<AppProviderConfig?> findById(String? providerId) async {
    final trimmed = providerId?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return _repository.findById(CliTool.codebuddy, trimmed);
  }

  Future<String?> resolveProviderId(
    TeamProfile team, {
    TeamMemberConfig? member,
  }) async {
    final fromTeam = team.providerIdsByTool['codebuddy']?.trim() ?? '';
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

    final providers = await _repository.loadProviders(CliTool.codebuddy);
    if (providers.length == 1) return providers.first.id;
    return null;
  }

  /// Provider for the process about to launch: member binding, then team
  /// default.
  Future<AppProviderConfig?> resolveForLaunch({
    required TeamProfile team,
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

  /// The single catalogued provider, if exactly one exists (standalone
  /// default).
  Future<AppProviderConfig?> resolveSole() async {
    final providers = await _repository.loadProviders(CliTool.codebuddy);
    if (providers.length == 1) return providers.first;
    return null;
  }
}
