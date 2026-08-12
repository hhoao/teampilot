// test/widgets/right_tools/right_tools_chat_slice_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/widgets/right_tools/right_tools_tool_views.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  group('RightToolsChatSlice.memberSelectionVersion', () {
    RightToolsChatSlice slice({
      required String selectedMemberId,
      required String? activeSessionId,
      required bool hasActiveTab,
      required bool hasTeamBus,
      required int memberSelectionVersion,
    }) => RightToolsChatSlice.fromScope(
      selectedMemberId: selectedMemberId,
      activeSessionId: activeSessionId,
      hasActiveTab: hasActiveTab,
      hasTeamBus: hasTeamBus,
      memberSelectionVersion: memberSelectionVersion,
    );

    test('slices differ when the version differs', () {
      final v1 = slice(
        selectedMemberId: 'm1',
        activeSessionId: 's1',
        hasActiveTab: true,
        hasTeamBus: false,
        memberSelectionVersion: 1,
      );
      final v2 = slice(
        selectedMemberId: 'm1',
        activeSessionId: 's1',
        hasActiveTab: true,
        hasTeamBus: false,
        memberSelectionVersion: 2,
      );
      expect(v1, isNot(equals(v2)));
    });

    test('slices are equal when the version matches', () {
      final a = slice(
        selectedMemberId: 'm1',
        activeSessionId: 's1',
        hasActiveTab: true,
        hasTeamBus: false,
        memberSelectionVersion: 1,
      );
      final b = slice(
        selectedMemberId: 'm1',
        activeSessionId: 's1',
        hasActiveTab: true,
        hasTeamBus: false,
        memberSelectionVersion: 1,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('ChatCubit memberSelectionVersion', () {
    late ChatCubit chat;
    setUp(() {
      setUpTestAppStorage();
      chat = ChatCubit(
        executableResolver: () => '/bin/true',
        automationRepository: testAutomationRepository(),
      );
    });
    tearDown(() async {
      await chat.close();
    });

    ChatTab registerTab(String id) {
      final tab = ChatTab(
        info: ChatTabInfo(id: id, title: id, subtitle: ''),
        cliTeamName: '',
        workspaceId: 'ws-1',
      );
      chat.tabStore.setActiveWorkspaceId('ws-1');
      chat.tabStore.registerSession(tab);
      return tab;
    }

    test('selectMember bumps the version only on real changes', () {
      registerTab('s1');

      expect(chat.state.memberSelectionVersion, 0);
      chat.selectMember('m-lead');
      expect(chat.state.memberSelectionVersion, 1);

      // Same member again: no-op, no bump.
      chat.selectMember('m-lead');
      expect(chat.state.memberSelectionVersion, 1);

      chat.selectMember('m-2');
      expect(chat.state.memberSelectionVersion, 2);
    });

    test('syncTeam bumps the version when it rewrites the member', () {
      const team = TeamProfile(
        id: 'team-a',
        name: 'A',
        members: [
          TeamMemberConfig(id: 'm-1', name: 'one'),
          TeamMemberConfig(id: 'team-lead', name: 'lead'),
        ],
      );
      registerTab('s1');

      chat.syncTeam(team);
      expect(chat.state.memberSelectionVersion, 1);

      // Default member already selected: no bump.
      chat.syncTeam(team);
      expect(chat.state.memberSelectionVersion, 1);
    });
  });
}
