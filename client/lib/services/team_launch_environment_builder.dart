import '../models/team_config.dart';
import 'claude_provider_settings_resolver.dart';
import 'config_profile_service.dart';
import 'flashskyai_storage_roots.dart';

typedef StorageRootsResolver = Future<StorageRootsSnapshot> Function();

/// Builds merged launch environment for a team session.
class TeamLaunchEnvironmentBuilder {
  const TeamLaunchEnvironmentBuilder._();

  static Future<Map<String, String>?> build({
    required String appDataBasePath,
    required TeamConfig team,
    TeamMemberConfig? member,
    String runtimeTeamId = '',
    String? llmConfigPathOverride,
    String workingDirectory = '',
    ConfigProfileService? configProfileService,
    StorageRootsResolver? storageRootsResolver,
    ClaudeProviderSettingsResolver? claudeSettingsResolver,
  }) async {
    final teamId = team.id.trim();
    if (teamId.isNotEmpty) {
      final service =
          configProfileService ??
          await _configProfileServiceFor(
            appDataBasePath: appDataBasePath,
            storageRootsResolver: storageRootsResolver,
          );
      final resolver =
          claudeSettingsResolver ??
          ClaudeProviderSettingsResolver(basePath: service.basePath);
      final claudeSettings = team.cli == TeamCli.claude
          ? await resolver.resolveTeamClaudeSettings(team)
          : null;
      final claudeSettingsByMember = team.cli == TeamCli.claude
          ? await _loadClaudeMemberProviderSettings(
              resolver: resolver,
              team: team,
              teamClaudeSettings: claudeSettings,
              launchedMember: member,
            )
          : const <String, Map<String, Object?>>{};
      return service.prepareTeamLaunch(
        teamId: teamId,
        runtimeTeamId: runtimeTeamId,
        cli: team.cli,
        members: team.members,
        member: member,
        workingDirectory: workingDirectory,
        claudeSettings: claudeSettings,
        claudeSettingsByMember: claudeSettingsByMember,
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

  static Future<Map<String, Map<String, Object?>>>
  _loadClaudeMemberProviderSettings({
    required ClaudeProviderSettingsResolver resolver,
    required TeamConfig team,
    required Map<String, Object?>? teamClaudeSettings,
    required TeamMemberConfig? launchedMember,
  }) async {
    final members = <String, TeamMemberConfig>{};
    for (final member in team.members.where((member) => member.isValid)) {
      members[member.id] = member;
    }
    final selected = launchedMember;
    if (selected != null && selected.isValid) {
      members[selected.id] = selected;
    }

    final settingsByMember = <String, Map<String, Object?>>{};
    for (final member in members.values) {
      final settings = await resolver.resolveMemberClaudeSettings(
        team: team,
        member: member,
        teamClaudeSettings: teamClaudeSettings,
      );
      if (settings != null) {
        settingsByMember[member.id] = settings;
        settingsByMember[member.name] = settings;
      }
    }
    return settingsByMember;
  }
}
