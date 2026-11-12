import '../../../../models/app_provider_config.dart';
import '../../../../models/team_config.dart';
import '../../../../repositories/app_provider_repository.dart';
import '../../../io/filesystem.dart';
import '../../../storage/home_storage.dart';

/// Resolves Grok providers from the app catalog for session launch.
/// Member binding wins, then the team default, then a lone catalogued
/// provider.
final class GrokProviderSettingsResolver {
  GrokProviderSettingsResolver({
    required String basePath,
    required HomeStorage storage,
    Filesystem? fs,
    AppProviderRepository? repository,
    CliTool cli = CliTool.grok,
    String? toolKey,
  }) : _cli = cli,
       _toolKey = toolKey ?? cli.value,
       _repository =
           repository ??
           AppProviderRepository(basePath: basePath, fs: fs, storage: storage);

  final AppProviderRepository _repository;
  final CliTool _cli;
  final String _toolKey;

  Future<AppProviderConfig?> findById(String? providerId) async {
    final trimmed = providerId?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return _repository.findById(_cli, trimmed);
  }

  Future<AppProviderConfig?> resolveForLaunch({
    required TeamProfile team,
    TeamMemberConfig? member,
  }) async {
    final selected = member;
    if (selected != null && selected.isValid) {
      final fromMember = await findById(selected.provider);
      if (fromMember != null) return fromMember;
    }
    final fromTeam = team.providerIdsByTool[_toolKey]?.trim() ?? '';
    if (fromTeam.isNotEmpty) {
      final byId = await findById(fromTeam);
      if (byId != null) return byId;
    }
    return resolveSole();
  }

  /// The single catalogued provider, if exactly one exists (standalone
  /// default).
  Future<AppProviderConfig?> resolveSole() async {
    final providers = await _repository.loadProviders(_cli);
    return providers.length == 1 ? providers.first : null;
  }
}
