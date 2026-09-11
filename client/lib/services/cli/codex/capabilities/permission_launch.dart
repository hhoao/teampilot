import '../../../../models/team_config.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_capability_error.dart';
import '../../registry/launch/cli_launch_context.dart';

final class CodexPermissionLaunch implements CliLaunchArgProvider {
  const CodexPermissionLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(CliLaunchContext context) {
    final policy = context.launchSecurityPolicy;
    if (policy == LaunchSecurityPolicy.cliDefault) return const [];
    if (policy == LaunchSecurityPolicy.fullAccess) {
      return [
        _contribution(const [
          '--dangerously-bypass-approvals-and-sandbox',
          '--dangerously-bypass-hook-trust',
        ], key: 'codex-permission-bypass'),
      ];
    }

    final args = <String>[];
    switch (policy.approval) {
      case LaunchApprovalPolicy.cliDefault:
        break;
      case LaunchApprovalPolicy.ask:
        args.addAll(['--ask-for-approval', 'on-request']);
      case LaunchApprovalPolicy.never:
        args.addAll(['--ask-for-approval', 'never']);
      case LaunchApprovalPolicy.autoApprove:
        if (policy.sandbox != LaunchSandboxPolicy.workspaceWrite) {
          throw _unsupportedPolicy();
        }
        args.add('--approve-for-me');
    }

    switch (policy.sandbox) {
      case LaunchSandboxPolicy.cliDefault:
        break;
      case LaunchSandboxPolicy.readOnly:
        args.addAll(['--sandbox', 'read-only']);
      case LaunchSandboxPolicy.workspaceWrite:
        if (policy.approval != LaunchApprovalPolicy.autoApprove) {
          args.addAll(['--sandbox', 'workspace-write']);
        }
      case LaunchSandboxPolicy.fullAccess:
        args.addAll(['--sandbox', 'danger-full-access']);
    }

    if (policy.hookTrust == LaunchHookTrustPolicy.bypass) {
      args.add('--dangerously-bypass-hook-trust');
    }
    return [_contribution(args)];
  }

  CliLaunchArgContribution _contribution(
    List<String> args, {
    String key = 'codex-permission',
  }) => CliLaunchArgContribution(
    key: key,
    phase: LaunchArgPhase.security,
    exclusiveGroup: 'codex-permission-mode',
    args: args,
  );

  CliLaunchCapabilityException _unsupportedPolicy() =>
      const CliLaunchCapabilityException(
        cli: CliTool.codex,
        contributionKey: 'codex-permission',
        reason: 'Codex does not support this launch security policy tuple.',
        exclusiveGroup: 'codex-permission-mode',
      );
}
