import '../../cli_data_layout.dart';
import '../../../../models/team_config.dart';
import '../../../provider/claude_provider_credentials_service.dart';
import '../../../io/filesystem.dart';
import '../../../host/host_execution_environment.dart';
import 'package:path/path.dart' as p;

/// Resolved launch path scope for a team session.
class LaunchProfileScope {
  const LaunchProfileScope({
    required this.teamId,
    required this.sessionId,
    required this.cliTeamName,
  });

  final String teamId;
  final String sessionId;
  final String cliTeamName;
}

/// Narrow path facade for [ConfigProfileCapability] unit tests.
abstract interface class ConfigProfilePaths {
  String get basePath;

  Filesystem get fs;

  p.Context get pathContext;

  CliDataLayout get layout;

  String sessionToolDir(String teamId, String sessionId, String tool);

  String sessionFlashskyaiMetadataFile(String teamId, String sessionId);

  String sessionClaudeMetadataFile(String teamId, String sessionId);

  String sessionClaudeMemberSettingsFile(
    String teamId,
    String sessionId,
    TeamMemberConfig member,
  );

  String get appFlashskyaiLlmConfigFile;
}

/// Shared profile operations delegated from [ConfigProfileService].
abstract interface class ConfigProfileDelegate implements ConfigProfilePaths {
  Future<Map<String, Object?>> readMetadataFile(
    String path,
    Map<String, Object?> defaults,
  );

  Future<void> writeJsonIfChanged(String path, Map<String, Object?> value);

  Future<Map<String, Object?>> metadataWithTrustedProjects({
    required String metadataPath,
    required Map<String, Object?> defaultMetadata,
    required Iterable<String> directories,
  });

  Future<bool> trustedProjectsAlreadyCurrent(
    String metadataPath,
    Iterable<String> directories,
  );

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

  ClaudeProviderCredentialsService get claudeCredentials;

  HostExecutionEnvironment hostEnvironmentForProvision();
}
