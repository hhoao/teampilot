import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_policy.dart';

import '../../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  SeatRewindPolicy policy({
    bool mobile = false,
    bool git = true,
    RuntimeTarget? target,
  }) {
    return SeatRewindPolicy(
      isMobile: () => mobile,
      gitAvailable: () => git,
      layout: () => testHomeStorage.context.layout,
      launchTargetFor: (_, _) => target ?? RuntimeTarget.local(),
    );
  }

  AppSession session({bool mixed = false}) => AppSession(
    sessionId: mixed ? 'm1' : 's1',
    workspaceId: 'w1',
    createdAt: 1,
    sessionTeam: mixed ? 'team-1' : '',
  );

  test('personal local seat with git is eligible', () {
    final result = policy().evaluate(
      session: session(),
      memberId: null,
      cli: CliTool.claude,
      acp: true,
    );

    expect(result.allowed, isTrue);
    expect(result.store!.target.seatKey, 'personal');
    expect(result.store!.gitDir, contains('/rewind/personal'));
  });

  test('mixed seat is denied while the mixed switch is off', () {
    final result = policy().evaluate(
      session: session(mixed: true),
      memberId: 'm1',
      cli: CliTool.claude,
      acp: false,
    );

    expect(result.allowed, isFalse);
    expect(result.denial, RewindDenial.mixedSeatsDisabled);
  });

  test('mobile is denied before touching git', () {
    final result = policy(mobile: true).evaluate(
      session: session(),
      memberId: null,
      cli: CliTool.claude,
      acp: false,
    );

    expect(result.allowed, isFalse);
    expect(result.denial, RewindDenial.mobilePlatform);
  });

  test('remote runtime is denied', () {
    final result = policy(
      target: RuntimeTarget.ssh('profile', label: 'SSH'),
    ).evaluate(
      session: session(),
      memberId: null,
      cli: CliTool.claude,
      acp: false,
    );

    expect(result.allowed, isFalse);
    expect(result.denial, RewindDenial.remoteRuntime);
  });

  test('missing git is denied', () {
    final result = policy(git: false).evaluate(
      session: session(),
      memberId: null,
      cli: CliTool.claude,
      acp: false,
    );

    expect(result.allowed, isFalse);
    expect(result.denial, RewindDenial.gitMissing);
  });
}
