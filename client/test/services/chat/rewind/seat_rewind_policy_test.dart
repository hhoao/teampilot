import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/rewind/rewind_capability.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_policy.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  /// A resolved work-plane context carrying [target] (Task 5 `ctx(target, dir)`
  /// shape). Reuses the installed test home's filesystem/paths but keeps the
  /// passed target so an ssh work plane is exercised end-to-end.
  RuntimeContext ctx(RuntimeTarget target) {
    final home = testHomeStorage.context;
    return RuntimeContext(
      target: target,
      filesystem: home.filesystem,
      home: home.home,
      cwd: home.cwd,
      appDataRoot: home.appDataRoot,
      paths: home.paths,
    );
  }

  /// Builds a policy with fully injected work-plane seams. The default is a
  /// local target, a resolved native context for that target, and an available
  /// git capability.
  SeatRewindPolicy policy({
    RuntimeTarget? target,
    RuntimeContext? Function(RuntimeTarget)? contextFor,
    RewindCapability? capability,
  }) {
    final workTarget = target ?? RuntimeTarget.local();
    final RuntimeContext? Function(RuntimeTarget) resolvedContext =
        contextFor ?? ctx;
    final cap = capability ?? const RewindCapability(available: true);
    return SeatRewindPolicy(
      workTargetFor: (_, _) => workTarget,
      contextFor: resolvedContext,
      capabilityFor: (_) => cap,
    );
  }

  AppSession session({bool mixed = false}) => AppSession(
    sessionId: mixed ? 'm1' : 's1',
    workspaceId: 'w1',
    createdAt: 1,
    sessionTeam: mixed ? 'team-1' : '',
  );

  test('personal + local target + git available is allowed', () {
    final result = policy().evaluate(
      session: session(),
      memberId: null,
      cli: CliTool.claude,
      acp: true,
    );

    expect(result.allowed, isTrue);
    expect(result.store!.target.seatKey, 'personal');
    expect(
      result.store!.gitDir.replaceAll('\\', '/'),
      contains('/rewind/personal'),
    );
  });

  test('mixed seat is denied (mixedSeatsDisabled)', () {
    final result = policy().evaluate(
      session: session(mixed: true),
      memberId: 'm1',
      cli: CliTool.claude,
      acp: false,
    );

    expect(result.allowed, isFalse);
    expect(result.denial, RewindDenial.mixedSeatsDisabled);
  });

  test('unresolved work context is denied (workPlaneNotReady)', () {
    final result = policy(contextFor: (_) => null).evaluate(
      session: session(),
      memberId: null,
      cli: CliTool.claude,
      acp: false,
    );

    expect(result.allowed, isFalse);
    expect(result.denial, RewindDenial.workPlaneNotReady);
  });

  test('unavailable capability is denied (gitMissing)', () {
    final result = policy(capability: RewindCapability.unavailable).evaluate(
      session: session(),
      memberId: null,
      cli: CliTool.claude,
      acp: false,
    );

    expect(result.allowed, isFalse);
    expect(result.denial, RewindDenial.gitMissing);
  });

  test('ssh windows remote is denied (unsupportedBackend)', () {
    final windows = RuntimeTarget.ssh('profile', label: 'SSH').copyWith(
      remoteOs: RemoteOs.windows,
    );
    final result = policy(target: windows).evaluate(
      session: session(),
      memberId: null,
      cli: CliTool.claude,
      acp: false,
    );

    expect(result.allowed, isFalse);
    expect(result.denial, RewindDenial.unsupportedBackend);
  });

  test('ssh posix remote with git available is allowed', () {
    final posix = RuntimeTarget.ssh('profile', label: 'SSH').copyWith(
      remoteOs: RemoteOs.posix,
    );
    final result = policy(target: posix).evaluate(
      session: session(),
      memberId: null,
      cli: CliTool.claude,
      acp: false,
    );

    expect(result.allowed, isTrue);
    expect(result.store!.target.seatKey, 'personal');
  });

  // Regression guard for mobile enablement: on Android the work plane is an
  // ssh plane, so an ssh target with git must be eligible. Task 6 removed the
  // old mobile/remote denials; this keeps them from coming back.
  test('ssh work plane with git is eligible (mobile enablement)', () {
    final result = policy(
      target: const RuntimeTarget(id: 'ssh:phone',
        label: 'Phone'),
      capability: const RewindCapability(
        available: true,
        version: '2.43',
        pathspecFromFile: true,
      ),
    ).evaluate(
      session: session(),
      memberId: null,
      cli: CliTool.claude,
      acp: false,
    );
    expect(result.allowed, isTrue);
  });
}
