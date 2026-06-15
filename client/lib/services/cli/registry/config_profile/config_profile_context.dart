import 'package:path/path.dart' as p;

import '../../cli_data_layout.dart';
import '../../../../models/project_profile.dart';
import '../../../../models/team_config.dart';
import '../../../../utils/team_member_naming.dart';
import '../../../io/filesystem.dart';
import '../../../host/host_execution_environment.dart';
import 'config_profile_scope.dart';

export 'config_profile_scope.dart';

/// Personal project PTY CONFIG_DIR for [tool].
String standaloneSessionToolDir(
  ConfigProfilePaths paths,
  StandaloneLaunchProfileScope scope,
  String tool,
) =>
    paths.layout.standaloneProjectSessionToolDir(
      scope.projectId,
      scope.sessionId,
      tool,
    );

/// [LaunchProfileScope] for personal sessions (path keys only; use
/// [standaloneSessionToolDir] for CONFIG_DIR).
LaunchProfileScope launchScopeForStandalone(StandaloneLaunchProfileScope scope) =>
    LaunchProfileScope(
      teamId: scope.projectId,
      sessionId: scope.sessionId,
      cliTeamName: scope.sessionId,
    );

// TODO: migrate to presets — resolve from active preset instead of profile maps
String standaloneProviderId(/* CliPreset? preset */) {
  // TODO: return preset?.provider.trim() ?? '';
  return '';
}

// TODO: migrate to presets — resolve from active preset instead of profile maps
String standaloneModelId(/* CliPreset? preset */) {
  // TODO: return preset?.model.trim() ?? '';
  return '';
}

/// Minimal [TeamConfig] for personal / standalone PTY launch args.
/// TODO: migrate to presets — accept CliPreset? parameter for cli/provider/model/effort
TeamConfig standaloneTeamFromProfile(
  ProjectProfile profile, {
  required String projectId,
  required String sessionTeamName,
}) {
  final member = standaloneMemberFromProfile(profile);
  return TeamConfig(
    id: projectId.trim(),
    name: sessionTeamName.trim(),
    cli: CliTool.claude, // TODO: preset?.cli ?? CliTool.claude
    members: [member],
    skillIds: profile.skillIds,
    pluginIds: profile.pluginIds,
    mcpServerIds: profile.mcpServerIds,
    teamMode: TeamMode.native,
    forceTeamLeadDelegateMode: false,
  );
}

/// Single-agent stand-in from [ProjectProfile.agent] for standalone launch.
/// TODO: migrate to presets — accept CliPreset? parameter
TeamMemberConfig standaloneMemberFromProfile(ProjectProfile profile) {
  final agent = profile.agent;
  final name = _standaloneMemberDisplayName(agent);
  return TeamMemberConfig(
    id: TeamMemberNaming.slugMemberName(name),
    name: name,
    provider: '', // TODO: preset?.provider.trim() ?? ''
    model: '', // TODO: preset?.model.trim() ?? ''
    agent: agent.agent,
    agentType: agent.agentType,
    extraArgs: agent.extraArgs,
    prompt: agent.prompt,
    dangerouslySkipPermissions: agent.dangerouslySkipPermissions,
    cli: CliTool.claude, // TODO: preset?.cli ?? CliTool.claude
    effort: '', // TODO: preset?.effort.trim() ?? ''
  );
}

String _standaloneMemberDisplayName(ProjectAgentConfig agent) {
  final fromAgent = agent.agent.trim();
  if (fromAgent.isNotEmpty) return fromAgent;
  final fromType = agent.agentType.trim();
  if (fromType.isNotEmpty) return fromType;
  return 'agent';
}

/// Path facade for [ConfigProfileCapability] implementations.
abstract interface class ConfigProfilePaths {
  String get basePath;

  Filesystem get fs;

  p.Context get pathContext;

  CliDataLayout get layout;

  String sessionToolDir(String teamId, String sessionId, String tool);
}

/// Shared profile I/O, extension settings hooks, and team-lead scripts.
abstract interface class ConfigProfileDelegate implements ConfigProfilePaths {
  Future<Map<String, Object?>> readMetadataFile(
    String path,
    Map<String, Object?> defaults,
  );

  Future<void> writeJsonIfChanged(String path, Map<String, Object?> value);

  Future<Map<String, Object?>> metadataWithTrustedProjects({
    required String metadataPath,
    required Map<String, Object?> defaultMetadata,
    required Map<String, Object?> defaultProjectConfig,
    required Iterable<String> directories,
  });

  Future<bool> trustedProjectsAlreadyCurrent(
    String metadataPath,
    Iterable<String> directories, {
    required Map<String, Object?> defaultMetadata,
  });

  Future<Map<String, Object?>> readSettingsFile(String path);

  Future<void> writeSettingsFile(
    String path,
    Map<String, Object?> settings, {
    String? memberToolDir,
    required String tool,
    String? teamId,
    String? projectId,
  });

  Future<bool> hasEnabledExtensionSettingsHooks(
    String tool, {
    String? teamId,
    String? projectId,
  });

  Future<Map<String, Object?>> applyExtensionSettings(
    Map<String, Object?> settings,
    String? memberToolDir, {
    required String tool,
    String? teamId,
    String? projectId,
  });

  Future<Map<String, Object?>> maybeApplyTeamLeadHooks(
    Map<String, Object?> settings,
    TeamMemberConfig member,
    String memberToolDir, {
    required bool forceTeamLeadDelegateMode,
  });

  Future<String?> resolveAppendSystemPromptPath({
    required LaunchProfileScope scope,
    required String tool,
    required TeamMemberConfig member,
  });

  HostExecutionEnvironment hostEnvironmentForProvision();
}

class ConfigProfileSessionContext {
  const ConfigProfileSessionContext({
    required this.teamId,
    required this.sessionId,
    required this.members,
    required this.paths,
    this.team,
    this.standaloneScope,
    this.profile,
  });

  final String teamId;
  final String sessionId;
  final List<TeamMemberConfig> members;
  final ConfigProfileDelegate paths;
  final TeamConfig? team;
  final StandaloneLaunchProfileScope? standaloneScope;
  final ProjectProfile? profile;
}

class ConfigProfileLaunchContext {
  const ConfigProfileLaunchContext({
    required this.teamId,
    required this.sessionId,
    required this.scope,
    this.team,
    this.member,
    required this.members,
    this.workingDirectory = '',
    this.additionalDirectories = const [],
    required this.paths,
    this.leadSessionId,
    this.busIdleUrl,
    this.standaloneScope,
    this.profile,
  });

  final String teamId;
  final String sessionId;
  final LaunchProfileScope scope;
  final TeamConfig? team;
  final TeamMemberConfig? member;
  final List<TeamMemberConfig> members;
  final String? workingDirectory;
  final List<String> additionalDirectories;
  final ConfigProfileDelegate paths;
  final String? leadSessionId;
  final String? busIdleUrl;
  final StandaloneLaunchProfileScope? standaloneScope;
  final ProjectProfile? profile;
}
