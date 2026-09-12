import 'package:flutter/foundation.dart';

enum LaunchApprovalPolicy { cliDefault, ask, autoApprove, never }

enum LaunchSandboxPolicy { cliDefault, readOnly, workspaceWrite, fullAccess }

enum LaunchHookTrustPolicy { cliDefault, trustedOnly, bypass }

/// Normalized, CLI-independent security intent for a launch.
@immutable
class LaunchSecurityPolicy {
  const LaunchSecurityPolicy({
    this.approval = LaunchApprovalPolicy.never,
    this.sandbox = LaunchSandboxPolicy.fullAccess,
    this.hookTrust = LaunchHookTrustPolicy.bypass,
  });

  /// Explicit full-access policy used by application defaults.
  static const fullAccess = LaunchSecurityPolicy();

  /// Explicitly delegate each security dimension to the CLI.
  static const cliDefault = LaunchSecurityPolicy(
    approval: LaunchApprovalPolicy.cliDefault,
    sandbox: LaunchSandboxPolicy.cliDefault,
    hookTrust: LaunchHookTrustPolicy.cliDefault,
  );

  /// A cautious explicit preset for permission controls that need to show
  /// more than the CLI default/full-access pair.
  static const askReadOnlyTrusted = LaunchSecurityPolicy(
    approval: LaunchApprovalPolicy.ask,
    sandbox: LaunchSandboxPolicy.readOnly,
    hookTrust: LaunchHookTrustPolicy.trustedOnly,
  );

  /// An explicit development preset that still retains trusted hook checks.
  static const autoApproveWorkspaceWriteTrusted = LaunchSecurityPolicy(
    approval: LaunchApprovalPolicy.autoApprove,
    sandbox: LaunchSandboxPolicy.workspaceWrite,
    hookTrust: LaunchHookTrustPolicy.trustedOnly,
  );

  final LaunchApprovalPolicy approval;
  final LaunchSandboxPolicy sandbox;
  final LaunchHookTrustPolicy hookTrust;

  /// Whether this policy asks the launcher for an explicitly dangerous mode.
  bool get requiresDangerousExecution =>
      approval == LaunchApprovalPolicy.never &&
      sandbox == LaunchSandboxPolicy.fullAccess &&
      hookTrust == LaunchHookTrustPolicy.bypass;

  LaunchSecurityPolicy copyWith({
    LaunchApprovalPolicy? approval,
    LaunchSandboxPolicy? sandbox,
    LaunchHookTrustPolicy? hookTrust,
  }) {
    return LaunchSecurityPolicy(
      approval: approval ?? this.approval,
      sandbox: sandbox ?? this.sandbox,
      hookTrust: hookTrust ?? this.hookTrust,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchSecurityPolicy &&
          approval == other.approval &&
          sandbox == other.sandbox &&
          hookTrust == other.hookTrust;

  @override
  int get hashCode => Object.hash(approval, sandbox, hookTrust);
}
