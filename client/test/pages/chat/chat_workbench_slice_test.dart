import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';

void main() {
  group('ChatState.isActiveSessionConnecting', () {
    test('false when active session cleared but connecting id remains', () {
      const state = ChatState(
        tabs: [
          ChatTabInfo(id: 'session-a', title: 'Chat', subtitle: '/tmp'),
        ],
        activeSessionId: null,
        sessionConnectingId: 'session-a',
      );

      expect(state.isActiveSessionConnecting, isFalse);
    });

    test('false when a pending materialization is in flight', () {
      const state = ChatState(
        tabs: [
          ChatTabInfo(id: 'session-a', title: 'Chat', subtitle: '/tmp'),
        ],
        activeSessionId: 'session-a',
        sessionConnectingId: 'pending',
      );

      // A 'pending' connect belongs to a session that does not exist yet; it
      // must not light up an unrelated active conversation.
      expect(state.isActiveSessionConnecting, isFalse);
    });

    test('true only when the connecting id matches the active session', () {
      const state = ChatState(
        tabs: [
          ChatTabInfo(id: 'session-a', title: 'Chat', subtitle: '/tmp'),
        ],
        activeSessionId: 'session-a',
        sessionConnectingId: 'session-a',
      );

      expect(state.isActiveSessionConnecting, isTrue);
    });
  });
}
