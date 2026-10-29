import '../../../../models/app_provider_config.dart';
import '../../../../models/team_config.dart';
import '../../../../repositories/app_provider_repository.dart';
import '../../../io/filesystem.dart';
import '../../../storage/home_storage.dart';

/// Resolves Antigravity providers from the app catalog for session launch.
/// Member binding wins, then the team default, then a lone provider.
final class AntigravityProviderSettingsResolver {
  AntigravityProviderSettingsResolver({
    required String basePath,
    required HomeStorage storage,
    Filesystem? fs,
    AppProviderRepository? repository,
  }) : _repository =
           repository ??
           AppProviderRepository(basePath: basePath, fs: fs, storage: storage);

  final AppProviderRepository _repository;

  static const _cli = CliTool.antigravity;

  Future<AppProviderConfig?> findById(String? providerId) async {
    final trimmed = providerId?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return _repository.findById(_cli, trimmed);
  }

  /// Provider for the process about to launch: member binding, then team
  /// default, then the lone catalogued provider.
  Future<AppProviderConfig?> resolveForLaunch({
    required TeamProfile team,
    TeamMemberConfig? member,
  }) async {
    final selected = member;
    if (selected != null && selected.isValid) {
      final fromMember = await findById(selected.provider);
      if (fromMember != null) return fromMember;
    }

    final fromTeam = team.providerIdsByTool[_cli.value]?.trim() ?? '';
    final byTeam = await findById(fromTeam);
    if (byTeam != null) return byTeam;

    return resolveSole();
  }

  /// The single catalogued provider, if exactly one exists.
  Future<AppProviderConfig?> resolveSole() async {
    final providers = await _repository.loadProviders(_cli);
    if (providers.length == 1) return providers.first;
    return null;
  }
}
