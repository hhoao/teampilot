import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import 'connected_recording_shell.dart';
import '../../support/post_frame_test_harness.dart';

/// Running + connected fake shell so idle-watch and presence treat it as live.
class RunningConnectedFakeShell extends TerminalSession {
  RunningConnectedFakeShell({required super.executable});

  @override
  bool get isRunning => true;

  @override
  bool get isConnecting => false;

  @override
  bool get isConnected => true;

  @override
  void dispose() {}
}

const kIdleBusyMixedTeam = TeamProfile(
  id: 'it-idle-busy-mixed',
  name: 'Idle/Busy IT',
  teamMode: TeamMode.mixed,
  members: [
    TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
    TeamMemberConfig(id: 'worker-1', name: 'developer'),
  ],
);

/// Loopback `/idle` on the teammate-bus HTTP server (same port as `/mcp`).
Uri idleEndpointFromMcp(Uri mcpEndpoint) =>
    mcpEndpoint.replace(path: '/idle');

Future<void> postMemberIdle(Uri idleEndpoint, String memberId) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(idleEndpoint);
    req.headers.set('X-Member', memberId);
    final resp = await req.close();
    await resp.drain();
  } finally {
    client.close(force: true);
  }
}

/// Opens a mixed team session tab and wires connected recording shells + running bus members.
Future<({
  String sessionId,
  ConnectedRecordingShell leadShell,
  ConnectedRecordingShell workerShell,
})> openMixedSessionWithShells({
  required ChatCubit cubit,
  required SessionRepository repo,
  required PostFrameTestHarness postFrame,
}) async {
  final workspace = await repo.createWorkspace([
    WorkspaceFolder(path: '/tmp'),
  ]);
  final session = await repo.createSession(
    workspace.workspaceId,
    sessionTeam: kIdleBusyMixedTeam.id,
    rosterMembers: kIdleBusyMixedTeam.members,
  );

  await cubit.requestOpenSession(
    SessionOpenRequest(
      session: session,
      team: kIdleBusyMixedTeam,
      member: kIdleBusyMixedTeam.members.first,
      repo: repo,
      connectImmediately: false,
    ),
  );
  await drainPendingAsyncWork();
  await postFrame.flush();

  final tab = cubit.activeTab!;
  final bus = tab.teamBus!;
  final leadShell = await ConnectedRecordingShell.connect();
  final workerShell = await ConnectedRecordingShell.connect();
  tab.memberShells['team-lead'] = leadShell.session;
  tab.memberShells['worker-1'] = workerShell.session;
  bus.markMemberRunning('team-lead');
  bus.markMemberRunning('worker-1');
  cubit.pushPresenceTarget();
  await postFrame.flush();
  await pumpSchedulerFrames();

  return (
    sessionId: session.sessionId,
    leadShell: leadShell,
    workerShell: workerShell,
  );
}

void bindPresenceForPolling({
  required ChatCubit chatCubit,
  required MemberPresenceCubit presenceCubit,
}) {
  chatCubit.bindPresenceCubit(presenceCubit);
  presenceCubit.attachPresenceUi();
  presenceCubit.syncPresenceTeam(kIdleBusyMixedTeam);
}

Future<void> waitForPresencePoll({ChatCubit? cubit}) async {
  cubit?.debugTickIdleWatch();
  await Future<void>.delayed(const Duration(milliseconds: 150));
}

/// [MemberPresenceCubit] schedules via [SchedulerBinding], not [PostFrameTestHarness].
Future<void> pumpSchedulerFrames({int frames = 2}) async {
  for (var i = 0; i < frames; i++) {
    SchedulerBinding.instance.handleBeginFrame(Duration.zero);
    SchedulerBinding.instance.handleDrawFrame();
    await pumpEventQueue();
  }
}

/// Arms [TerminalActivityTracker] past the boot-quiet window for deterministic tests.
void armActivityTracker(TerminalSession shell) {
  shell.activityTracker.reset();
  shell.activityTracker.isWorking;
  shell.activityTracker.markActive();
}

/// Backdates the per-turn fingerprint baseline so [isQuietAfterTurnPtyActivity]
/// is true on the next idle-watch tick.
void simulateFingerprintQuietGap(
  TerminalSession shell, {
  Duration ago = const Duration(seconds: 5),
}) {
  shell.activityTracker.notePtyBytes(
    Uint8List.fromList('fingerprint-quiet\n'.codeUnits),
    DateTime.now().subtract(ago),
  );
}
