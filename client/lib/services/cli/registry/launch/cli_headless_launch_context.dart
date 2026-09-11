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
    this.securityPolicy = LaunchSecurityPolicy.fullAccess,
    this.teamExtraArgs = '',
    this.memberExtraArgs = '',
    this.useWslPaths = false,
    this.expectJson = false,
    this.stream = false,
    this.promptViaStdin = false,
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

  /// Deliver [prompt] via the process stdin instead of an argv entry. Used
  /// for long prompts, which would otherwise exceed the ~8k-char cmd.exe
  /// command-line limit for npm `.cmd` shims on Windows.
  final bool promptViaStdin;
}
