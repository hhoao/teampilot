import '../../../models/team_config.dart';
import '../../storage/home_storage.dart';
import '../../storage/runtime_layout.dart';
import '../../chat/launch/config_profile_service.dart';
import '../../chat/session/session_lifecycle_service.dart';

/// Builds [ConfigProfileService] instances and ensures config-profile trees
/// exist for teams. Shared between [LaunchProfileCubit] CRUD and resource sync.
class TeamProfileProvisioner {
  TeamProfileProvisioner({
    required HomeStorage storage,
    ConfigProfileService? configProfileService,
    StorageRootsResolver? storageRootsResolver,
    String? appDataBasePathOverride,
  }) : _storage = storage,
       _configProfileService = configProfileService,
       _storageRootsResolver = storageRootsResolver,
       _appDataBasePathOverride =
           (appDataBasePathOverride != null &&
               appDataBasePathOverride.isNotEmpty)
           ? appDataBasePathOverride
           : null;

  final HomeStorage _storage;
  final ConfigProfileService? _configProfileService;
  final StorageRootsResolver? _storageRootsResolver;
  final String? _appDataBasePathOverride;

  String get _resolvedAppDataBasePath {
    final override = _appDataBasePathOverride;
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return _storage.paths.basePath;
  }

  Future<ConfigProfileService> service() async {
    final injected = _configProfileService;
    if (injected != null) return injected;
    final resolver = _storageRootsResolver;
    if (resolver == null) {
      final fs = _storage.fs;
      return ConfigProfileService(
        storage: _storage,
        basePath: _resolvedAppDataBasePath,
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: _resolvedAppDataBasePath, fs: fs),
      );
    }
    final roots = await resolver();
    return ConfigProfileService(
      storage: _storage,
      basePath: roots.teampilotRoot,
      fs: roots.fs,
      layout: roots.layout,
    );
  }

  Future<void> ensureTeamProfile(String teamId, {required CliTool cli}) async {
    final profileService = await service();
    await profileService.ensureTeamProfile(teamId, cli: cli);
  }

  Future<void> ensureForTeams(List<TeamProfile> teams) async {
    final profileService = await service();
    for (final team in teams) {
      await profileService.ensureTeamProfile(team.id, cli: team.cli);
    }
  }
}
