import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import 'bus_roster_assertions.dart';
import 'mixed_team_integration_harness.dart';
import 'session_idle_busy_harness.dart';

/// Binds [MemberPresenceCubit] for L2 mixed-team PTY idle/busy assertions.
void bindMixedTeamPresence({
  required ChatCubit chatCubit,
  required MemberPresenceCubit presenceCubit,
}) {
  chatCubit.bindPresenceCubit(presenceCubit);
  presenceCubit.attachPresenceUi();
  presenceCubit.syncPresenceTeam(kItMixedClaudeTeam);
}

Future<void> tickIdleAndPresence({
  required ChatCubit cubit,
  required MemberPresenceCubit presenceCubit,
}) async {
  cubit.debugTickIdleWatch();
  await waitForPresencePoll(cubit: cubit);
  await pumpSchedulerFrames();
}

Future<void> waitUntilSessionIdle({
  required ChatCubit cubit,
  required String sessionId,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    cubit.debugTickIdleWatch();
    if (!cubit.state.workingSessionIds.contains(sessionId)) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError(
    'Timed out waiting for session $sessionId to leave workingSessionIds '
    '(still: ${cubit.state.workingSessionIds})',
  );
}

Future<void> waitUntilMemberWorkload({
  required MemberPresenceCubit presenceCubit,
  ChatCubit? cubit,
  required String memberId,
  required MemberWorkload workload,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    cubit?.debugTickIdleWatch();
    await waitForPresencePoll(cubit: cubit);
    await pumpSchedulerFrames();
    final snap = presenceCubit.memberPresenceFor(memberId);
    if (snap.workload == workload) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError(
    'Timed out waiting for $memberId workload=$workload '
    '(got ${presenceCubit.memberPresenceFor(memberId).workload})',
  );
}

void expectSessionIdle(ChatCubit cubit, String sessionId) {
  cubit.debugTickIdleWatch();
  expect(
    cubit.state.workingSessionIds,
    isNot(contains(sessionId)),
    reason: 'mixed session should not show sidebar working spinner',
  );
}

Future<void> waitUntilWorkerIdleOnBus({
  required TeamBus? bus,
  required String workspaceId,
  required String sessionId,
  String memberId = 'worker-1',
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final snap = memberSnapshot(bus, memberId);
    if (snap?.waitingForMessage == true) return;
    if (snap?.activity.name == 'turnDoneBusWait') return;
    if (snap?.activity.name == 'turnDoneReady') return;
    // Do not treat idle_notification mail as parked: PTY quiet can fire
    // onMemberIdle during tool gaps while the member is still bus-active.
    if (snap?.claudeIsActive == false) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError(
    'Timed out waiting for $memberId idle on bus:\n${formatRosterSnapshot(bus)}',
  );
}
