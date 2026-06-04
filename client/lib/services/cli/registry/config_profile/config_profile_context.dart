import 'package:path/path.dart' as p;

import '../../cli_data_layout.dart';
import '../../../../models/team_config.dart';
import '../../../io/filesystem.dart';
import '../../../host/host_execution_environment.dart';
import 'config_profile_scope.dart';

export 'config_profile_scope.dart';

/// Path facade for [ConfigProfileCapability] implementations.
abstract interface class ConfigProfilePaths {
  String get basePath;

  Filesystem get fs;

  p.Context get pathContext;

  CliDataLayout get layout;

  String sessionToolDir(String teamId, String sessionId, String tool);
}

/// Shared profile I/O and cross-CLI hooks (RTK, team-lead scripts).
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
  });

  Future<bool> isRtkEnabled();

  Future<Map<String, Object?>> maybeApplyRtk(
    Map<String, Object?> settings,
    String? memberToolDir,
  );

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
  });

  final String teamId;
  final String sessionId;
  final List<TeamMemberConfig> members;
  final ConfigProfileDelegate paths;
  final TeamConfig? team;
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
}
