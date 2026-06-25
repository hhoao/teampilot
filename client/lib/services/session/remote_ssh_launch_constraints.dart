import 'dart:convert';

import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../ssh/ssh_client_factory.dart';
import '../ssh/ssh_run_result.dart';
import 'shell_launch_spec.dart';

/// Mirrors Claude Code `setup.ts` root + bypass check: root is allowed when
/// `IS_SANDBOX=1` (containers / TPU devspaces) or bubblewrap is enabled.
const claudeCodeSandboxEnvKey = 'IS_SANDBOX';
const claudeCodeSandboxEnvValue = '1';

/// Whether the remote SSH login runs as Unix root (`uid 0`).
Future<bool> remoteSshRunsAsRoot({
  required SshClientFactory sshClientFactory,
  required SshProfile profile,
}) async {
  final client = await sshClientFactory.clientFor(profile);
  final result = await client.runWithResult('id -u', stderr: false);
  if (sshRunFailed(result)) return false;
  return utf8.decode(result.stdout, allowMalformed: true).trim() == '0';
}

/// Linux Docker probe — same as Claude Code `envDynamic.getIsDocker()`.
Future<bool> remoteSshInDockerContainer({
  required SshClientFactory sshClientFactory,
  required SshProfile profile,
}) async {
  final client = await sshClientFactory.clientFor(profile);
  final result = await client.runWithResult('test -f /.dockerenv', stderr: false);
  return sshRunSucceeded(result);
}

/// How to reconcile member skip-permissions with Claude Code `setup.ts` on SSH.
enum RemoteRootSkipPermissionsPolicy {
  /// No change (non-root, or skip-permissions off).
  unchanged,

  /// Root inside a container: export `IS_SANDBOX=1`, keep the CLI flag.
  injectSandboxEnv,

  /// Root on a non-container host: drop the flag (setup.ts would exit 1).
  dropFlag,
}

RemoteRootSkipPermissionsPolicy resolveRemoteRootSkipPermissionsPolicy({
  required bool skipPermissionsRequested,
  required bool runsAsRoot,
  required bool remoteInDocker,
}) {
  if (!skipPermissionsRequested || !runsAsRoot) {
    return RemoteRootSkipPermissionsPolicy.unchanged;
  }
  if (remoteInDocker) return RemoteRootSkipPermissionsPolicy.injectSandboxEnv;
  return RemoteRootSkipPermissionsPolicy.dropFlag;
}

/// Applies Claude Code launch constraints for remote SSH (P3c).
///
/// When the login is root and the member requests skip-permissions, container
/// hosts get `IS_SANDBOX=1` (setup.ts escape hatch); bare-metal root drops the
/// flag instead of letting the CLI abort.
Future<ShellLaunchSpec> applyRemoteSshLaunchConstraints({
  required ShellLaunchSpec spec,
  required RuntimeTarget memberTarget,
  required SshClientFactory? sshClientFactory,
  required SshProfile? profile,
}) async {
  if (memberTarget.kind != RuntimeKind.ssh ||
      sshClientFactory == null ||
      profile == null) {
    return spec;
  }
  final member = spec.launchContext.member;
  if (!member.dangerouslySkipPermissions) return spec;

  final runsAsRoot = await remoteSshRunsAsRoot(
    sshClientFactory: sshClientFactory,
    profile: profile,
  );
  final remoteInDocker = runsAsRoot
      ? await remoteSshInDockerContainer(
          sshClientFactory: sshClientFactory,
          profile: profile,
        )
      : false;
  final policy = resolveRemoteRootSkipPermissionsPolicy(
    skipPermissionsRequested: member.dangerouslySkipPermissions,
    runsAsRoot: runsAsRoot,
    remoteInDocker: remoteInDocker,
  );

  return switch (policy) {
    RemoteRootSkipPermissionsPolicy.unchanged => spec,
    RemoteRootSkipPermissionsPolicy.injectSandboxEnv => () {
      final plan = spec.plan;
      final env = Map<String, String>.from(plan.env);
      env[claudeCodeSandboxEnvKey] = claudeCodeSandboxEnvValue;
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
          isFreshConversation: plan.isFreshConversation,
          toolValue: plan.toolValue,
          warnings: plan.warnings,
        ),
        launchContext: spec.launchContext,
        sessionTeam: spec.sessionTeam,
      );
    }(),
    RemoteRootSkipPermissionsPolicy.dropFlag => () {
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
          isFreshConversation: plan.isFreshConversation,
          toolValue: plan.toolValue,
          warnings: [
            ...plan.warnings,
            'remote_ssh_root_skip_permissions_disabled: '
                'Claude Code rejects --dangerously-skip-permissions for root '
                'outside a sandbox (setup.ts); launching with permission prompts '
                'on ${profile.hostIdentifier}. Use a non-root SSH user or a '
                'container with IS_SANDBOX=1.',
          ],
        ),
        launchContext: spec.launchContext.copyWith(
          member: member.copyWith(dangerouslySkipPermissions: false),
        ),
        sessionTeam: spec.sessionTeam,
      );
    }(),
  };
}
