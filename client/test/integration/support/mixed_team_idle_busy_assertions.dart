import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
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

Future<void> waitUntilNoMemberInTurn({
  required TeamBus? bus,
  ChatCubit? cubit,
  Duration timeout = const Duration(seconds: 120),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    cubit?.debugTickIdleWatch();
    if (bus == null || !bus.anyMemberInTurn) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError(
    'Timed out waiting for all members to leave bus turn:\n'
    '${formatRosterSnapshot(bus)}',
  );
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

/// Waits until no member is bus-active **and** the session spinner clears.
///
/// Nudges PTY fingerprint quiet each tick so real Claude shells can fall through
/// [TeamBus.onMemberIdle] after tool bursts (mock cannot always re-park).
Future<void> waitUntilBusCalmAndSessionIdle({
  required TeamBus? bus,
  required ChatCubit cubit,
  required String sessionId,
  TeammateBusMcpGateway? gateway,
  Duration timeout = const Duration(seconds: 180),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final tab = cubit.tabStore.openTabBySessionId(sessionId);
    if (tab != null) {
      for (final shell in tab.memberShells.values) {
        simulateFingerprintQuietGap(shell);
      }
    }
    cubit.debugTickIdleWatch();
    final busCalm = bus == null || !bus.anyMemberInTurn;
    final sessionCalm = !cubit.state.workingSessionIds.contains(sessionId);
    if (busCalm && sessionCalm) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError(
    'Timed out waiting for calm bus + session idle:\n'
    'workingSessions=${cubit.state.workingSessionIds}\n'
    '${formatRosterSnapshot(bus)}\n'
    'mcpWaitStreams=${gateway?.activeWaitStreamCountFor(sessionId) ?? 0}',
  );
}

Future<void> waitUntilMemberAvailability({
  required MemberPresenceCubit presenceCubit,
  ChatCubit? cubit,
  required String memberId,
  required MemberAvailability availability,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    cubit?.debugTickIdleWatch();
    await waitForPresencePoll(cubit: cubit);
    await pumpSchedulerFrames();
    final snap = presenceCubit.memberPresenceFor(memberId);
    if (snap.availability == availability) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError(
    'Timed out waiting for $memberId availability=$availability '
    '(got ${presenceCubit.memberPresenceFor(memberId).availability})',
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
    // Idle-at-prompt (turn done, not in bus turn) — no wait_for_message required
    // for presence; automation still gates on bus wait separately.
    if (snap?.activity.name == 'turnDoneReady' &&
        bus != null &&
        !bus.isMemberInTurn(memberId)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError(
    'Timed out waiting for $memberId idle on bus:\n${formatRosterSnapshot(bus)}',
  );
}
