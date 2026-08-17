import '../../models/runtime_target.dart';
import '../../models/launch_security_policy.dart';
import '../../models/ssh_profile.dart';
import '../../utils/logging/logger.dart';
import '../cli/registry/launch/cli_launch_context.dart';
import '../ssh/ssh_member_session.dart';
import '../ssh/ssh_run_result.dart';
import 'shell_launch_spec.dart';

/// Mirrors Claude Code `setup.ts` root + bypass check: root is allowed when
/// `IS_SANDBOX=1` (containers / TPU devspaces) or bubblewrap is enabled.
const claudeCodeSandboxEnvKey = 'IS_SANDBOX';
const claudeCodeSandboxEnvValue = '1';

Future<bool> remoteSshRunsAsRoot({
  required SshMemberSession memberSession,
}) async {
  final result = await memberSession.runWithResult('id -u', stderr: false);
  if (sshRunFailed(result)) return false;
  return String.fromCharCodes(result.stdout).trim() == '0';
}

Future<bool> remoteSshInDockerContainer({
  required SshMemberSession memberSession,
}) async {
  final result = await memberSession.runWithResult(
    'test -f /.dockerenv',
    stderr: false,
  );
  return sshRunSucceeded(result);
}

/// How to reconcile a dangerous security policy with Claude Code `setup.ts` on SSH.
enum RemoteRootSecurityPolicy {
  /// No change (non-root, or safe policy).
  unchanged,

  /// Root with sandbox env: export `IS_SANDBOX=1`, keep the requested policy.
  /// Triggered by container detection or per-target opt-in on bare-metal root.
  injectSandboxEnv,

  /// Root on a non-container host: transform to a safe policy.
  dropDangerousPolicy,
}

const _safeRemoteRootSecurityPolicy = LaunchSecurityPolicy(
  approval: LaunchApprovalPolicy.ask,
  sandbox: LaunchSandboxPolicy.workspaceWrite,
  hookTrust: LaunchHookTrustPolicy.trustedOnly,
);

CliLaunchContext restrictRemoteRootSecurityPolicy(CliLaunchContext context) {
  return context.copyWith(
    member: context.member.copyWith(
      launchSecurityPolicy: _safeRemoteRootSecurityPolicy,
    ),
    launchSecurityPolicy: _safeRemoteRootSecurityPolicy,
  );
}

RemoteRootSecurityPolicy resolveRemoteRootSecurityPolicy({
  required LaunchSecurityPolicy securityPolicy,
  required bool runsAsRoot,
  required bool remoteInDocker,
  bool injectRootSandboxEnv = false,
}) {
  if (!securityPolicy.requiresDangerousExecution || !runsAsRoot) {
    return RemoteRootSecurityPolicy.unchanged;
  }
  if (remoteInDocker || injectRootSandboxEnv) {
    return RemoteRootSecurityPolicy.injectSandboxEnv;
  }
  return RemoteRootSecurityPolicy.dropDangerousPolicy;
}

/// Applies Claude Code launch constraints for remote SSH (P3c).
Future<ShellLaunchSpec> applyRemoteSshLaunchConstraints({
  required ShellLaunchSpec spec,
  required RuntimeTarget memberTarget,
  required SshMemberSession? memberSession,
  required SshProfile? profile,
  bool injectRootSandboxEnv = false,
}) async {
  if (!usesSshTransport(memberTarget.kind) ||
      memberSession == null ||
      profile == null) {
    return spec;
  }
  final member = spec.launchContext.member;
  final securityPolicy = spec.launchContext.launchSecurityPolicy;
  if (!securityPolicy.requiresDangerousExecution) return spec;

  final runsAsRoot = await remoteSshRunsAsRoot(memberSession: memberSession);
  final remoteInDocker = runsAsRoot
      ? await remoteSshInDockerContainer(memberSession: memberSession)
      : false;
  final policy = resolveRemoteRootSecurityPolicy(
    securityPolicy: securityPolicy,
    runsAsRoot: runsAsRoot,
    remoteInDocker: remoteInDocker,
    injectRootSandboxEnv: injectRootSandboxEnv,
  );

  return switch (policy) {
    RemoteRootSecurityPolicy.unchanged => spec,
    RemoteRootSecurityPolicy.injectSandboxEnv => () {
      final plan = spec.plan;
      final env = Map<String, String>.from(plan.env);
      env[claudeCodeSandboxEnvKey] = claudeCodeSandboxEnvValue;
      final reason = remoteInDocker ? 'container root' : 'target opt-in';
      appLogger.d(
        '[remote-ssh-launch] $reason on ${profile.hostIdentifier}: '
        'injecting $claudeCodeSandboxEnvKey=$claudeCodeSandboxEnvValue',
      );
      return ShellLaunchSpec(
        plan: LaunchPlan(
          env: env,
          resume: plan.resume,
          taskId: plan.taskId,
          cliTeamName: plan.cliTeamName,
          memberConfigDir: plan.memberConfigDir,
          resolvedRoots: plan.resolvedRoots,
          createSessionId: plan.createSessionId,
          resumeSessionId: plan.resumeSessionId,
          nativeSessionIdToPersist: plan.nativeSessionIdToPersist,
          toolValue: plan.toolValue,
          warnings: plan.warnings,
        ),
        launchContext: spec.launchContext,
        sessionTeam: spec.sessionTeam,
      );
    }(),
    RemoteRootSecurityPolicy.dropDangerousPolicy => () {
      final plan = spec.plan;
      return ShellLaunchSpec(
        plan: LaunchPlan(
          env: plan.env,
          resume: plan.resume,
          taskId: plan.taskId,
          cliTeamName: plan.cliTeamName,
          memberConfigDir: plan.memberConfigDir,
          resolvedRoots: plan.resolvedRoots,
          createSessionId: plan.createSessionId,
          resumeSessionId: plan.resumeSessionId,
          nativeSessionIdToPersist: plan.nativeSessionIdToPersist,
          toolValue: plan.toolValue,
          warnings: [
            ...plan.warnings,
            'remote_ssh_root_security_policy_restricted: '
                'Claude Code rejects dangerous root execution outside a '
                'sandbox (setup.ts); launching with safe security policy '
                'on ${profile.hostIdentifier}. Use a non-root SSH user, a '
                'container with IS_SANDBOX=1, or enable root sandbox env '
                'in SSH target settings.',
          ],
        ),
        launchContext: restrictRemoteRootSecurityPolicy(spec.launchContext),
        sessionTeam: spec.sessionTeam,
      );
    }(),
  };
}
