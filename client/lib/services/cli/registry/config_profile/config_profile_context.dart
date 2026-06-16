import 'package:path/path.dart' as p;

import '../../../storage/runtime_layout.dart';
import '../../../../models/cli_preset.dart';
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
    paths.layout.sessionRuntimeToolDir(
      scope.projectId,
      scope.sessionId,
      tool,
    );

/// [LaunchProfileScope] for personal sessions (path keys only; use
/// [standaloneSessionToolDir] for CONFIG_DIR).
LaunchProfileScope launchScopeForStandalone(StandaloneLaunchProfileScope scope) =>
    LaunchProfileScope(
      projectId: scope.projectId,
      teamId: scope.projectId,
      sessionId: scope.sessionId,
      cliTeamName: scope.sessionId,
    );

/// Resolve CLI/provider/model/effort for a personal project from its active preset.
/// Returns null if no preset is active, not found, or [activePresetId] is empty.
CliPreset? resolveActivePreset(String? activePresetId, List<CliPreset> presets) {
  if (activePresetId == null || activePresetId.isEmpty) return null;
  for (final p in presets) {
    if (p.id == activePresetId) return p;
  }
  return null;
}

String standaloneProviderId(CliPreset? preset) {
  return preset?.provider.trim() ?? '';
}

String standaloneModelId(CliPreset? preset) {
  return preset?.model.trim() ?? '';
}

CliTool standaloneCli(CliPreset? preset, {CliTool fallback = CliTool.claude}) {
  return preset?.cli ?? fallback;
}

/// Minimal [TeamConfig] for personal / standalone PTY launch args.
TeamConfig standaloneTeamFromProfile(
  ProjectProfile profile, {
  required String projectId,
  required String sessionTeamName,
  required CliPreset? preset,
}) {
  final member = standaloneMemberFromProfile(profile, preset: preset);
  return TeamConfig(
    id: projectId.trim(),
    name: sessionTeamName.trim(),
    cli: preset?.cli ?? CliTool.claude,
    members: [member],
    skillIds: profile.skillIds,
    pluginIds: profile.pluginIds,
    mcpServerIds: profile.mcpServerIds,
    teamMode: TeamMode.native,
    forceTeamLeadDelegateMode: false,
  );
}

/// Single-agent stand-in from [ProjectProfile.agent] for standalone launch.
TeamMemberConfig standaloneMemberFromProfile(
  ProjectProfile profile, {
  required CliPreset? preset,
}) {
  final agent = profile.agent;
  final name = _standaloneMemberDisplayName(agent);
  return TeamMemberConfig(
    id: TeamMemberNaming.slugMemberName(name),
    name: name,
    provider: preset?.provider.trim() ?? '',
    model: preset?.model.trim() ?? '',
    agent: agent.agent,
    agentType: agent.agentType,
    extraArgs: agent.extraArgs,
    prompt: agent.prompt,
    dangerouslySkipPermissions: agent.dangerouslySkipPermissions,
    cli: preset?.cli ?? CliTool.claude,
    effort: preset?.effort.trim() ?? '',
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

  RuntimeLayout get layout;

  String sessionToolDir(
    String projectId,
    String sessionId,
    String tool, {
    String? memberId,
  });
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
    required this.projectId,
    required this.teamId,
    required this.sessionId,
    required this.members,
    required this.paths,
    this.team,
    this.standaloneScope,
    this.profile,
    this.memberId,
  });

  final String projectId;
  final String teamId;
  final String sessionId;
  final List<TeamMemberConfig> members;
  final ConfigProfileDelegate paths;
  final TeamConfig? team;
  final StandaloneLaunchProfileScope? standaloneScope;
  final ProjectProfile? profile;
  final String? memberId;
}

class ConfigProfileLaunchContext {
  const ConfigProfileLaunchContext({
    required this.projectId,
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
    this.preset,
    this.memberId,
  });

  final String projectId;
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
  final CliPreset? preset;
  final String? memberId;
}
