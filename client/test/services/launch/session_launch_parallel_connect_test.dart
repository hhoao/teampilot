import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/launch/session_launch_pipeline.dart';

AppSession _session(String id) => AppSession(
  sessionId: id,
  workspaceId: 'w1',
  folders: const [WorkspaceFolder(path: '/w')],
  createdAt: 1,
);

ChatTab _tab(String sessionId, {Set<String> pendingMembers = const {}}) {
  return ChatTab(
    info: ChatTabInfo(id: sessionId, title: 'S', subtitle: ''),
    cliTeamName: '',
  )..membersPendingConnect.addAll(pendingMembers);
}

void main() {
  group('shouldSerializeConnect — different sessions launch concurrently', () {
    test('another session connecting does NOT block ExistingSessionConnect', () {
      final tabStore = ChatTabStore()..setActiveWorkspaceId('w1');
      tabStore.registerSession(_tab('s1'));
      tabStore.registerSession(_tab('s2'));

      // s1 is connecting; we want to connect s2 in parallel.
      final serialize = shouldSerializeConnect(
        request: ExistingSessionConnect(session: _session('s2')),
        tabStore: tabStore,
        isSessionConnecting: (id) => id == 's1',
        isMaterializingInFlight: false,
      );

      expect(serialize, isFalse, reason: 's2 must not wait behind s1');
    });

    test('a materializing default session does NOT block a specific session',
        () {
      final tabStore = ChatTabStore()..setActiveWorkspaceId('w1');
      tabStore.registerSession(_tab('s1'));

      final serialize = shouldSerializeConnect(
        request: ExistingSessionConnect(session: _session('s1')),
        tabStore: tabStore,
        isSessionConnecting: (_) => false,
        isMaterializingInFlight: true,
      );

      expect(serialize, isFalse,
          reason: 'specific-session connect does not race materialization');
    });
  });

  group('shouldSerializeConnect — same target still serializes', () {
    test('target session already connecting is skipped', () {
      final tabStore = ChatTabStore()..setActiveWorkspaceId('w1');
      tabStore.registerSession(_tab('s1'));

      final serialize = shouldSerializeConnect(
        request: ExistingSessionConnect(session: _session('s1')),
        tabStore: tabStore,
        isSessionConnecting: (_) => true,
        isMaterializingInFlight: false,
      );

      expect(serialize, isTrue, reason: 'no double connect of the same session');
    });

    test('member already owned by the member scheduler is skipped', () {
      final tabStore = ChatTabStore()..setActiveWorkspaceId('w1');
      tabStore.registerSession(_tab('s1', pendingMembers: {'team-lead'}));

      final serialize = shouldSerializeConnect(
        request: ExistingSessionConnect(
          session: _session('s1'),
          team: TeamProfile(
            id: 'team-1',
            name: 'Team',
            cli: CliTool.claude,
          ),
          member: const TeamMemberConfig(id: 'team-lead', name: 'Lead'),
        ),
        tabStore: tabStore,
        isSessionConnecting: (_) => false,
        isMaterializingInFlight: false,
      );

      expect(serialize, isTrue,
          reason: 'member connect is already owned elsewhere');
    });

    test('pre-session materialization serializes non-specific connects', () {
      final tabStore = ChatTabStore()..setActiveWorkspaceId('w1');

      final serialize = shouldSerializeConnect(
        request: PersonalSessionConnect(workspaceId: 'w1'),
        tabStore: tabStore,
        isSessionConnecting: (_) => false,
        isMaterializingInFlight: true,
      );

      expect(serialize, isTrue,
          reason: 'two materializations would race the default-session slot');
    });
  });

  test('no in-flight connect: nothing serialized', () {
    final tabStore = ChatTabStore()..setActiveWorkspaceId('w1');
    tabStore.registerSession(_tab('s1'));

    final serialize = shouldSerializeConnect(
      request: ExistingSessionConnect(session: _session('s1')),
      tabStore: tabStore,
      isSessionConnecting: (_) => false,
      isMaterializingInFlight: false,
    );

    expect(serialize, isFalse);
  });
}
