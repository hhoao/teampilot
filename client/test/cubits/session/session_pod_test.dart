import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_workbench_view.dart';
import 'package:teampilot/cubits/session/session_phase.dart';
import 'package:teampilot/cubits/session/session_pod.dart';

void main() {
  test('SessionPod runtime mutators bump revision and notify', () {
    var notifications = 0;
    final pod = SessionPod(sessionId: 's1', workspaceId: 'w1');
    pod.addListener(() => notifications++);
    expect(pod.state.phase, SessionPhase.idle);

    pod.setPhase(SessionPhase.running);
    expect(pod.state.phase, SessionPhase.running);
    expect(pod.state.revision, 1);
    expect(notifications, 1);

    pod.setPhase(SessionPhase.running); // no-op keeps revision
    expect(pod.state.revision, 1);
    expect(notifications, 1);
  });

  test('update batches multiple mutations into one notify', () {
    var notifications = 0;
    final pod = SessionPod(sessionId: 's1', workspaceId: 'w1');
    pod.addListener(() => notifications++);

    pod.update((p) {
      p.setPhase(SessionPhase.error);
      p.setLaunchError('boom');
    });

    expect(notifications, 1, reason: 'one logical transition, one notify');
    expect(pod.state.phase, SessionPhase.error);
    expect(pod.state.launchError, 'boom');
    expect(pod.state.revision, 2);
  });

  test('update with no-op mutations fires no notify', () {
    var notifications = 0;
    final pod = SessionPod(sessionId: 's1', workspaceId: 'w1');
    pod.addListener(() => notifications++);
    pod.update((p) {
      p.setPhase(SessionPhase.idle); // already idle
    });
    expect(notifications, 0);
  });

  test('per-session isolation: mutating one pod leaves another untouched', () {
    final a = SessionPod(sessionId: 'a', workspaceId: 'w');
    final b = SessionPod(sessionId: 'b', workspaceId: 'w');
    a.setPhase(SessionPhase.error);
    a.setLaunchError('boom');
    expect(b.state.phase, SessionPhase.idle);
    expect(b.state.launchError, isNull);
    expect(a.state.launchError, 'boom');
  });

  test('setLaunchError(null) clears without notifying when already null', () {
    final pod = SessionPod(sessionId: 'a', workspaceId: 'w');
    pod.setLaunchError('boom');
    expect(pod.state.launchError, 'boom');
    pod.setLaunchError(null);
    expect(pod.state.launchError, isNull);
    pod.setLaunchError(null);
    expect(pod.state.launchError, isNull);
  });

  test('selectMember sets member id on pod state', () {
    final pod = SessionPod(sessionId: 'a', workspaceId: 'w');
    pod.selectMember('agent-7');
    expect(pod.state.selectedMemberId, 'agent-7');
  });

  test('setView switches chat↔terminal and bumps revision', () {
    final pod = SessionPod(sessionId: 'a', workspaceId: 'w');
    expect(pod.state.view, SessionWorkbenchView.chat);
    pod.setView(SessionWorkbenchView.terminal);
    expect(pod.state.view, SessionWorkbenchView.terminal);
    expect(pod.state.revision, 1);
    pod.setView(SessionWorkbenchView.terminal); // no-op
    expect(pod.state.revision, 1);
  });

  test('notifyExternalStateChanged bumps revision and notifies', () {
    var notifications = 0;
    final pod = SessionPod(sessionId: 'a', workspaceId: 'w');
    pod.setPhase(SessionPhase.running);
    pod.setView(SessionWorkbenchView.terminal);
    pod.addListener(() => notifications++);
    final before = pod.state;

    pod.notifyExternalStateChanged();

    expect(notifications, 1, reason: 'listeners re-read external state');
    expect(pod.state.revision, before.revision + 1);
    expect(pod.state.phase, before.phase, reason: 'pod fields are untouched');
    expect(pod.state.view, before.view);
    expect(pod.state, isNot(before), reason: 'selectors see a new state');
  });
}
