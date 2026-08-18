import '../../../../models/launch_security_policy.dart';

/// Normalized semantic inputs for one-shot/headless CLI argument providers.
final class CliHeadlessLaunchContext {
  const CliHeadlessLaunchContext({
    required this.prompt,
    required this.model,
    required this.effort,
    required this.configDir,
    this.providerId = '',
    this.agent = '',
    this.workingDirectory,
    this.additionalDirectories = const [],
    this.fixedSessionId,
    this.resumeSessionId,
    this.securityPolicy = const LaunchSecurityPolicy(),
    this.teamExtraArgs = '',
    this.memberExtraArgs = '',
    this.useWslPaths = false,
    this.expectJson = false,
    this.stream = false,
  });

  final String prompt;
  final String model;
  final String effort;
  final String configDir;
  final String providerId;
  final String agent;
  final String? workingDirectory;
  final List<String> additionalDirectories;
  final String? fixedSessionId;
  final String? resumeSessionId;
  final LaunchSecurityPolicy securityPolicy;
  final String teamExtraArgs;
  final String memberExtraArgs;
  final bool useWslPaths;
  final bool expectJson;
  final bool stream;
}
