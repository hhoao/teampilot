import 'package:teampilot/models/launch_security_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_continue_overrides.dart';

void main() {
  test('SessionContinueOverrides round-trips JSON', () {
    const o = SessionContinueOverrides(
      launchSecurityPolicy: LaunchSecurityPolicyOverride.fullAccess,
      memberOverrides: {
        'builder-0': SessionMemberContinueOverride(
          presetId: 'p1',
          provider: 'anthropic',
          model: 'claude',
          effort: 'high',
          launchSecurityPolicy: LaunchSecurityPolicyOverride.cliDefault,
        ),
      },
    );
    final back = SessionContinueOverrides.fromJson(o.toJson());
    expect(back.launchSecurityPolicy?.requiresDangerousExecution, isTrue);
    expect(back.memberOverrides['builder-0']?.presetId, 'p1');
    expect(
      back
          .memberOverrides['builder-0']
          ?.launchSecurityPolicy
          ?.requiresDangerousExecution,
      isFalse,
    );
  });

  test('empty / missing JSON is unset', () {
    expect(
      SessionContinueOverrides.fromJson(
        null,
      ).launchSecurityPolicy?.requiresDangerousExecution,
      isNull,
    );
    expect(
      SessionContinueOverrides.fromJson(const {}).memberOverrides,
      isEmpty,
    );
  });

  test(
    'copyWith preserves or clears nullable policy containers explicitly',
    () {
      const policy = LaunchSecurityPolicyOverride(
        approval: LaunchApprovalPolicy.ask,
        sandbox: LaunchSandboxPolicy.readOnly,
        hookTrust: LaunchHookTrustPolicy.trustedOnly,
      );
      const member = SessionMemberContinueOverride(
        provider: 'provider',
        launchSecurityPolicy: policy,
      );
      const overrides = SessionContinueOverrides(
        launchSecurityPolicy: policy,
        memberOverrides: {'member': member},
      );

      expect(member.copyWith().launchSecurityPolicy, policy);
      expect(
        member.copyWith(launchSecurityPolicy: null).launchSecurityPolicy,
        isNull,
      );
      expect(overrides.copyWith().launchSecurityPolicy, policy);
      expect(
        overrides.copyWith(launchSecurityPolicy: null).launchSecurityPolicy,
        isNull,
      );
    },
  );
}
