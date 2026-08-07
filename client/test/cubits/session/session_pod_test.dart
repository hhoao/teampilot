import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_workbench_view.dart';
import 'package:teampilot/cubits/session/session_phase.dart';
import 'package:teampilot/cubits/session/session_pod.dart';

void main() {
  test('SessionPod copyWith transitions phase and bumps revision only on change', () {
    const pod = SessionPod(sessionId: 's1', workspaceId: 'w1');
    expect(pod.phase, SessionPhase.idle);

    final running = pod.copyWith(phase: SessionPhase.running);
    expect(running.phase, SessionPhase.running);
    expect(running.revision, pod.revision + 1);

    final same = running.copyWith(phase: SessionPhase.running);
    expect(same.revision, running.revision, reason: 'no-op transition keeps revision');
  });

  test('per-session isolation: changing one pod leaves another untouched', () {
    const a = SessionPod(sessionId: 'a', workspaceId: 'w');
    const b = SessionPod(sessionId: 'b', workspaceId: 'w');
    final a2 = a.copyWith(phase: SessionPhase.error, launchError: 'boom');
    expect(b.phase, SessionPhase.idle);
    expect(b.launchError, isNull);
    expect(a2.launchError, 'boom');
  });

  test('clearLaunchError nulls the error without a phase change bump', () {
    final errored = const SessionPod(sessionId: 'a', workspaceId: 'w')
        .copyWith(phase: SessionPhase.error, launchError: 'boom');
    final cleared = errored.copyWith(clearLaunchError: true);
    expect(cleared.launchError, isNull);
    expect(cleared.revision, errored.revision + 1);
  });

  test('view transitions are tracked', () {
    const pod = SessionPod(sessionId: 'a', workspaceId: 'w');
    final terminal = pod.copyWith(view: SessionWorkbenchView.terminal);
    expect(terminal.view, SessionWorkbenchView.terminal);
    expect(terminal.revision, pod.revision + 1);
  });

  test('isLaunching covers provisioning and connecting only', () {
    expect(SessionPhase.provisioning.isLaunching, isTrue);
    expect(SessionPhase.connecting.isLaunching, isTrue);
    expect(SessionPhase.running.isLaunching, isFalse);
    expect(SessionPhase.error.isLaunching, isFalse);
  });
}
