import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/launch/connect/launch_flow.dart';
import 'package:teampilot/services/chat/launch/connect/launch_flow_host_adapter.dart';

void main() {
  late List<String> begun;
  late List<String> finished;
  late Set<String> connecting;
  late Map<String, Set<String>> pendingBySession;
  late LaunchFlowHostAdapter adapter;

  setUp(() {
    begun = <String>[];
    finished = <String>[];
    connecting = <String>{};
    pendingBySession = <String, Set<String>>{};
    adapter = LaunchFlowHostAdapter(
      beginSessionConnect: (sessionId) {
        begun.add(sessionId);
        connecting.add(sessionId);
      },
      isSessionConnecting: connecting.contains,
      finishSessionConnect: (sessionId) {
        finished.add(sessionId);
        connecting.remove(sessionId);
      },
      pendingMembersForSession: (sessionId) => pendingBySession[sessionId],
    );
  });

  test('queued records pending member and begins connect', () {
    pendingBySession['session-1'] = <String>{};

    adapter.onLaunchFlow(
      const LaunchFlowEvent(
        sessionId: 'session-1',
        memberId: 'member-1',
        phase: LaunchFlowPhase.queued,
      ),
    );

    expect(pendingBySession['session-1'], <String>{'member-1'});
    expect(begun, <String>['session-1']);
  });

  test('settled removes pending member and finishes if connecting', () {
    pendingBySession['session-1'] = <String>{'member-1'};
    connecting.add('session-1');

    adapter.onLaunchFlow(
      const LaunchFlowEvent(
        sessionId: 'session-1',
        memberId: 'member-1',
        phase: LaunchFlowPhase.settled,
      ),
    );

    expect(pendingBySession['session-1'], isEmpty);
    expect(finished, <String>['session-1']);
  });

  test('settled does not finish when session is not connecting', () {
    pendingBySession['session-1'] = <String>{'member-1'};

    adapter.onLaunchFlow(
      const LaunchFlowEvent(
        sessionId: 'session-1',
        memberId: 'member-1',
        phase: LaunchFlowPhase.settled,
      ),
    );

    expect(pendingBySession['session-1'], isEmpty);
    expect(finished, isEmpty);
  });

  test('queued still begins when no pending set exists', () {
    adapter.onLaunchFlow(
      const LaunchFlowEvent(
        sessionId: 'session-1',
        memberId: 'member-1',
        phase: LaunchFlowPhase.queued,
      ),
    );

    expect(begun, <String>['session-1']);
    expect(pendingBySession, isEmpty);
  });
}
