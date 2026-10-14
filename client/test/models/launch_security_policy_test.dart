import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_security_policy.dart';

void main() {
  test('default policy is full access', () {
    const policy = LaunchSecurityPolicy();

    expect(policy, LaunchSecurityPolicy.fullAccess);
    expect(policy.requiresDangerousExecution, isTrue);
  });

  test('cliDefault explicitly delegates all dimensions to the CLI', () {
    const policy = LaunchSecurityPolicy.cliDefault;

    expect(policy.approval, LaunchApprovalPolicy.cliDefault);
    expect(policy.sandbox, LaunchSandboxPolicy.cliDefault);
    expect(policy.hookTrust, LaunchHookTrustPolicy.cliDefault);
    expect(policy.requiresDangerousExecution, isFalse);
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

  test('partial dangerous dimensions do not require full-access execution', () {
    expect(
      const LaunchSecurityPolicy(
        approval: LaunchApprovalPolicy.never,
        sandbox: LaunchSandboxPolicy.workspaceWrite,
        hookTrust: LaunchHookTrustPolicy.bypass,
      ).requiresDangerousExecution,
      isFalse,
    );
    expect(
      const LaunchSecurityPolicy(
        approval: LaunchApprovalPolicy.never,
        sandbox: LaunchSandboxPolicy.fullAccess,
        hookTrust: LaunchHookTrustPolicy.trustedOnly,
      ).requiresDangerousExecution,
      isFalse,
    );
  });

  test('named intermediate policy presets retain all three dimensions', () {
    expect(
      LaunchSecurityPolicy.askReadOnlyTrusted,
      const LaunchSecurityPolicy(
        approval: LaunchApprovalPolicy.ask,
        sandbox: LaunchSandboxPolicy.readOnly,
        hookTrust: LaunchHookTrustPolicy.trustedOnly,
      ),
    );
    expect(
      LaunchSecurityPolicy.autoApproveWorkspaceWriteTrusted,
      const LaunchSecurityPolicy(
        approval: LaunchApprovalPolicy.autoApprove,
        sandbox: LaunchSandboxPolicy.workspaceWrite,
        hookTrust: LaunchHookTrustPolicy.trustedOnly,
      ),
    );
  });

  test('ask named preset is not dangerous execution', () {
    expect(
      LaunchSecurityPolicy.ask,
      const LaunchSecurityPolicy(
        approval: LaunchApprovalPolicy.ask,
        sandbox: LaunchSandboxPolicy.fullAccess,
        hookTrust: LaunchHookTrustPolicy.cliDefault,
      ),
    );
    expect(LaunchSecurityPolicy.ask.requiresDangerousExecution, isFalse);
  });

  test('acp permission named-id codec omits fullAccess and maps unknown to fullAccess', () {
    expect(acpPermissionToJson(LaunchSecurityPolicy.fullAccess), isNull);
    expect(acpPermissionToJson(LaunchSecurityPolicy.ask), 'ask');
    expect(acpPermissionFromJson(null), LaunchSecurityPolicy.fullAccess);
    expect(acpPermissionFromJson('fullAccess'), LaunchSecurityPolicy.fullAccess);
    expect(acpPermissionFromJson('ask'), LaunchSecurityPolicy.ask);
    expect(acpPermissionFromJson('nope'), LaunchSecurityPolicy.fullAccess);
  });
}
