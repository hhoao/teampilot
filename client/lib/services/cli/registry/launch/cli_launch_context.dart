import '../../../../models/team_config.dart';
import '../../../../models/launch_security_policy.dart';

/// Semantic launch inputs shared by CLI argument capabilities and launch
/// boundaries.
final class CliLaunchContext {
  const CliLaunchContext({
    required this.team,
    required this.member,
    LaunchSecurityPolicy? launchSecurityPolicy,
    this.sessionTeam,
    this.workingDirectory,
    this.additionalDirectories = const [],
    this.fixedSessionId,
    this.resumeSessionId,
    this.settingsPath,
    this.appendSystemPromptFile,
    this.useWslPaths = false,
    this.nativeAgentTeam,
    this.isSimpleSynthetic = false,
  }) : _explicitLaunchSecurityPolicy = launchSecurityPolicy;

  final TeamProfile team;
  final TeamMemberConfig member;
  final LaunchSecurityPolicy? _explicitLaunchSecurityPolicy;

  LaunchSecurityPolicy get launchSecurityPolicy =>
      _explicitLaunchSecurityPolicy ?? member.launchSecurityPolicy;
  final String? sessionTeam;
  final String? workingDirectory;
  final List<String> additionalDirectories;
  final String? fixedSessionId;
  final String? resumeSessionId;
  final String? settingsPath;
  final String? appendSystemPromptFile;
  final bool useWslPaths;

  /// When set, forces Claude `--team-name` / `--agent-name` / `--agent-id`.
  ///
  /// Personal/simple builds a 1-member synthetic [TeamMode.native] profile for
  /// argv plumbing; callers must pass `false` so Claude does not enter agent
  /// "manual mode" (multi-call loops). `null` keeps legacy derive: on when
  /// [team] is not mixed.
  final bool? nativeAgentTeam;

  /// True only for the synthetic one-member profile used by Simple launches.
  /// This is a launch-boundary fact, not a Claude team flag override.
  final bool isSimpleSynthetic;

  String get teamName => sessionTeam ?? team.name.trim();

  String get memberDisplayName => member.name.trim();

  /// CLI roster / `--agent-name` key ([TeamMemberConfig.id]).
  String get memberCliId => member.id.trim();

  /// Whether Claude native agent-team flags should be emitted.
  bool get usesNativeAgentTeam =>
      nativeAgentTeam ?? team.teamMode != TeamMode.mixed;

  CliLaunchContext copyWith({
    TeamProfile? team,
    TeamMemberConfig? member,
    LaunchSecurityPolicy? launchSecurityPolicy,
    String? sessionTeam,
    String? workingDirectory,
    List<String>? additionalDirectories,
    String? fixedSessionId,
    String? resumeSessionId,
    String? settingsPath,
    String? appendSystemPromptFile,
    bool? useWslPaths,
    bool? nativeAgentTeam,
    bool? isSimpleSynthetic,
  }) {
    return CliLaunchContext(
      team: team ?? this.team,
      member: member ?? this.member,
      launchSecurityPolicy:
          launchSecurityPolicy ?? _explicitLaunchSecurityPolicy,
      sessionTeam: sessionTeam ?? this.sessionTeam,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      additionalDirectories:
          additionalDirectories ?? this.additionalDirectories,
      fixedSessionId: fixedSessionId ?? this.fixedSessionId,
      resumeSessionId: resumeSessionId ?? this.resumeSessionId,
      settingsPath: settingsPath ?? this.settingsPath,
      appendSystemPromptFile:
          appendSystemPromptFile ?? this.appendSystemPromptFile,
      useWslPaths: useWslPaths ?? this.useWslPaths,
      nativeAgentTeam: nativeAgentTeam ?? this.nativeAgentTeam,
      isSimpleSynthetic: isSimpleSynthetic ?? this.isSimpleSynthetic,
    );
  }
}

String normalizePathForCli(String path, {required bool useWslPaths}) {
  if (!useWslPaths) return path;
  return windowsPathToWsl(path) ?? path;
}

String? windowsPathToWsl(String path) {
  final trimmed = path.trim();
  final uncMatch = RegExp(
    r'^\\+(?:wsl\.localhost|wsl\$)\\[^\\]+\\(.+)$',
    caseSensitive: false,
  ).firstMatch(trimmed.replaceAll('/', r'\'));
  if (uncMatch != null) {
    return '/${uncMatch.group(1)!.replaceAll(r'\', '/')}';
  }

  final match = RegExp(r'^([a-zA-Z]):[\\/]*(.*)$').firstMatch(trimmed);
  if (match == null) return null;
  final drive = match.group(1)!.toLowerCase();
  final rest = match.group(2)!.replaceAll('\\', '/');
  return rest.isEmpty ? '/mnt/$drive' : '/mnt/$drive/$rest';
}
