enum SessionApprovalPolicy { cliDefault, ask, autoApprove, never }
enum SessionSandboxPolicy { cliDefault, readOnly, workspaceWrite, fullAccess }
enum SessionHookTrustPolicy { cliDefault, trustedOnly, bypass }

final class SessionSecurityPolicy {
  const SessionSecurityPolicy({
    this.approval = SessionApprovalPolicy.never,
    this.sandbox = SessionSandboxPolicy.fullAccess,
    this.hookTrust = SessionHookTrustPolicy.bypass,
  });
  static const fullAccess = SessionSecurityPolicy();
  final SessionApprovalPolicy approval;
  final SessionSandboxPolicy sandbox;
  final SessionHookTrustPolicy hookTrust;
}
