import '../../../../models/team_config.dart';
import '../cli_capability.dart';
import '../config_profile/config_profile_context.dart';

/// Tool-specific session profile setup and launch environment contribution.
abstract interface class ConfigProfileCapability implements CliCapability {
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx);

  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  );
}

class ConfigProfileLaunchContribution {
  const ConfigProfileLaunchContribution({
    this.environment = const {},
    this.warnings = const [],
  });

  final Map<String, String> environment;
  final List<String> warnings;
}

class ClaudeLaunchExtras {
  const ClaudeLaunchExtras({
    this.settings,
    this.providerId,
    this.settingsByMember = const {},
  });

  final Map<String, Object?>? settings;
  final String? providerId;
  final Map<String, Map<String, Object?>> settingsByMember;
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
    this.claude,
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
  final ClaudeLaunchExtras? claude;
  final String? leadSessionId;
  final String? busIdleUrl;
}
