import '../models/team_config.dart';
import 'config_profile_service.dart';
import 'flashskyai_storage_roots.dart';

typedef StorageRootsResolver = Future<StorageRootsSnapshot> Function();

/// Builds merged launch environment for a team session.
class TeamLaunchEnvironmentBuilder {
  const TeamLaunchEnvironmentBuilder._();

  static Future<Map<String, String>?> build({
    required String appDataBasePath,
    required TeamConfig team,
    String? llmConfigPathOverride,
    ConfigProfileService? configProfileService,
    StorageRootsResolver? storageRootsResolver,
  }) async {
    final teamId = team.id.trim();
    if (teamId.isNotEmpty) {
      final service =
          configProfileService ??
          await _configProfileServiceFor(
            appDataBasePath: appDataBasePath,
            storageRootsResolver: storageRootsResolver,
          );
      return service.prepareTeamLaunch(
        teamId: teamId,
        cli: team.cli,
      );
    }

    final override = llmConfigPathOverride?.trim();
    if (override == null || override.isEmpty) {
      return null;
    }
    return {'LLM_CONFIG_PATH': override};
  }

  static Future<ConfigProfileService> _configProfileServiceFor({
    required String appDataBasePath,
    StorageRootsResolver? storageRootsResolver,
  }) async {
    final resolver = storageRootsResolver;
    if (resolver == null) {
      return ConfigProfileService(basePath: appDataBasePath);
    }
    final roots = await resolver();
    final remote = roots.remoteFileStore;
    if (roots.storageIsRemote && remote != null) {
      return ConfigProfileService(
        basePath: roots.teampilotRoot,
        createDirectory: remote.ensureDirectory,
      );
    }
    return ConfigProfileService(basePath: roots.teampilotRoot);
  }
}
