import 'session_security_policy.dart';

final class SessionInitRequest {
  const SessionInitRequest({
    required this.workspaceId,
    required this.sessionId,
    required this.memberId,
    required this.cli,
    required this.cliExecutablePath,
    required this.homeRoot,
    required this.workRoot,
    this.providerId = '',
    this.identityId = '',
    this.workingDirectory = '',
    this.additionalDirectories = const [],
    this.cliTeamName = '',
    this.resumeSessionId,
    this.createSessionId,
    this.securityPolicy = SessionSecurityPolicy.fullAccess,
    this.skillIds = const [],
    this.pluginIds = const [],
    this.mcpIds = const [],
  });

  final String workspaceId;
  final String sessionId;
  final String memberId;
  final String cli;
  final String cliExecutablePath;
  final String homeRoot;
  final String workRoot;
  final String providerId;
  final String identityId;
  final String workingDirectory;
  final List<String> additionalDirectories;
  final String cliTeamName;
  final String? resumeSessionId;
  final String? createSessionId;
  final SessionSecurityPolicy securityPolicy;
  final List<String> skillIds;
  final List<String> pluginIds;
  final List<String> mcpIds;
}
