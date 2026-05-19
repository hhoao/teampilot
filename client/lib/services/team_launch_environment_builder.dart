import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

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
    String workingDirectory = '',
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
      final claudeSettings = team.cli == TeamCli.claude
          ? await _loadClaudeProviderSettings(
              basePath: service.basePath,
              team: team,
            )
          : null;
      return service.prepareTeamLaunch(
        teamId: teamId,
        cli: team.cli,
        members: team.members,
        workingDirectory: workingDirectory,
        claudeSettings: claudeSettings,
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

  static Future<Map<String, Object?>?> _loadClaudeProviderSettings({
    required String basePath,
    required TeamConfig team,
  }) async {
    final providerId = team.providerIdsByTool['claude']?.trim() ?? '';
    if (providerId.isEmpty) return null;

    final file = File(
      p.join(basePath, 'providers', 'claude', providerId, 'settings.json'),
    );
    if (!await file.exists()) return null;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
    return null;
  }
}
