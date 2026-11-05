import '../../../../models/app_provider_config.dart';
import '../../../../models/team_config.dart';
import '../../../../repositories/app_provider_repository.dart';
import '../../../io/filesystem.dart';
import '../../../storage/home_storage.dart';

/// Resolves Qoder providers from the app catalog for session launch.
/// Member binding wins, then the team default, then a lone catalogued
/// provider.
final class QoderProviderSettingsResolver {
  QoderProviderSettingsResolver({
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
    return _repository.findById(CliTool.qoder, trimmed);
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
    final fromTeam = team.providerIdsByTool['qoder']?.trim() ?? '';
    if (fromTeam.isNotEmpty) {
      final byId = await findById(fromTeam);
      if (byId != null) return byId;
    }
    return resolveSole();
  }

  /// The single catalogued provider, if exactly one exists (standalone
  /// default).
  Future<AppProviderConfig?> resolveSole() async {
    final providers = await _repository.loadProviders(CliTool.qoder);
    return providers.length == 1 ? providers.first : null;
  }
}
