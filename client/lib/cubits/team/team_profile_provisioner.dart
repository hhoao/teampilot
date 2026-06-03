import '../../models/team_config.dart';
import '../../services/cli/cli_data_layout.dart';
import '../../services/provider/config_profile_service.dart';
import '../../services/session/session_lifecycle_service.dart';
import '../../services/storage/app_storage.dart';

/// Builds [ConfigProfileService] instances and ensures config-profile trees
/// exist for teams. Shared between [TeamCubit] CRUD and resource sync.
class TeamProfileProvisioner {
  TeamProfileProvisioner({
    ConfigProfileService? configProfileService,
    StorageRootsResolver? storageRootsResolver,
    String? appDataBasePathOverride,
  }) : _configProfileService = configProfileService,
       _storageRootsResolver = storageRootsResolver,
       _appDataBasePathOverride =
           (appDataBasePathOverride != null && appDataBasePathOverride.isNotEmpty)
           ? appDataBasePathOverride
           : null;

  final ConfigProfileService? _configProfileService;
  final StorageRootsResolver? _storageRootsResolver;
  final String? _appDataBasePathOverride;

  String get _resolvedAppDataBasePath {
    final override = _appDataBasePathOverride;
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return AppStorage.paths.basePath;
  }

  Future<ConfigProfileService> service() async {
    final injected = _configProfileService;
    if (injected != null) return injected;
    final resolver = _storageRootsResolver;
    if (resolver == null) {
      final fs = AppStorage.fs;
      return ConfigProfileService(
        basePath: _resolvedAppDataBasePath,
        fs: fs,
        layout: CliDataLayout(teampilotRoot: _resolvedAppDataBasePath, fs: fs),
      );
    }
    final roots = await resolver();
    return ConfigProfileService(
      basePath: roots.teampilotRoot,
      fs: roots.fs,
      layout: roots.layout,
    );
  }

  Future<void> ensureTeamProfile(String teamId, {required TeamCli cli}) async {
    final profileService = await service();
    await profileService.ensureTeamProfile(teamId, cli: cli);
  }

  Future<void> ensureForTeams(List<TeamConfig> teams) async {
    final profileService = await service();
    for (final team in teams) {
      await profileService.ensureTeamProfile(team.id, cli: team.cli);
    }
  }
}
