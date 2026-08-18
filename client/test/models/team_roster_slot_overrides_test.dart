import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/models/team_roster_slot.dart';

void main() {
  test('TeamRosterSlotOverrides round-trips replicas 0', () {
    const o = TeamRosterSlotOverrides(replicas: 0);
    expect(o.toJson()['replicas'], 0);
    expect(TeamRosterSlotOverrides.fromJson(o.toJson()).replicas, 0);
  });

  test('TeamRosterSlotOverrides omits replicas when 1', () {
    expect(
      const TeamRosterSlotOverrides().toJson().containsKey('replicas'),
      isFalse,
    );
  });

  test(
    'TeamRosterSlotOverrides round-trips normalized launch security policy',
    () {
      const o = TeamRosterSlotOverrides(
        launchSecurityPolicy: LaunchSecurityPolicy(
          approval: LaunchApprovalPolicy.ask,
          sandbox: LaunchSandboxPolicy.readOnly,
          hookTrust: LaunchHookTrustPolicy.trustedOnly,
        ),
      );

      expect(TeamRosterSlotOverrides.fromJson(o.toJson()), o);
    },
  );
}
