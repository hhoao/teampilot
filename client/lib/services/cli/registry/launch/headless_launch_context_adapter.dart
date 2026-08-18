import '../../../../models/team_config.dart';
import 'cli_headless_launch_context.dart';
import 'cli_launch_context.dart';

/// Adapts common headless semantics to the existing interactive providers so
/// session/workspace/security/user-argument encodings remain single-sourced.
CliLaunchContext interactiveContextForHeadless(
  CliHeadlessLaunchContext context,
  CliTool cli,
) {
  return CliLaunchContext(
    team: TeamProfile(
      id: 'headless',
      name: 'headless',
      cli: cli,
      teamMode: TeamMode.mixed,
      extraArgs: context.teamExtraArgs,
    ),
    member: TeamMemberConfig(
      id: 'headless',
      name: 'headless',
      provider: context.providerId,
      model: context.model,
      agent: context.agent,
      extraArgs: context.memberExtraArgs,
      launchSecurityPolicy: context.securityPolicy,
    ),
    workingDirectory: context.workingDirectory,
    additionalDirectories: context.additionalDirectories,
    fixedSessionId: context.fixedSessionId,
    resumeSessionId: context.resumeSessionId,
    useWslPaths: context.useWslPaths,
    isSimpleSynthetic: true,
  );
}
