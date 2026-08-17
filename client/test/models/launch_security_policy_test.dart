import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_security_policy.dart';

void main() {
  test(
    'default policy is explicit and delegates all dimensions to the CLI',
    () {
      const policy = LaunchSecurityPolicy();

      expect(policy.approval, LaunchApprovalPolicy.cliDefault);
      expect(policy.sandbox, LaunchSandboxPolicy.cliDefault);
      expect(policy.hookTrust, LaunchHookTrustPolicy.cliDefault);
      expect(policy.requiresDangerousExecution, isFalse);
    },
  );

  test('policy JSON round-trips all dimensions', () {
    const policy = LaunchSecurityPolicy(
      approval: LaunchApprovalPolicy.ask,
      sandbox: LaunchSandboxPolicy.workspaceWrite,
      hookTrust: LaunchHookTrustPolicy.trustedOnly,
    );

    expect(LaunchSecurityPolicy.fromJson(policy.toJson()), equals(policy));
  });

  test('policy equality and copyWith compare semantic dimensions', () {
    const policy = LaunchSecurityPolicy(
      approval: LaunchApprovalPolicy.autoApprove,
      sandbox: LaunchSandboxPolicy.readOnly,
      hookTrust: LaunchHookTrustPolicy.bypass,
    );

    expect(policy.copyWith(), equals(policy));
    expect(
      policy.copyWith(approval: LaunchApprovalPolicy.never),
      isNot(equals(policy)),
    );
  });

  test('full access policy requires dangerous execution', () {
    const policy = LaunchSecurityPolicy(
      approval: LaunchApprovalPolicy.never,
      sandbox: LaunchSandboxPolicy.fullAccess,
      hookTrust: LaunchHookTrustPolicy.bypass,
    );

    expect(policy.requiresDangerousExecution, isTrue);
  });
}
