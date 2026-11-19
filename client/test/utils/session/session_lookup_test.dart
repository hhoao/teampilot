import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_state.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/utils/session/session_lookup.dart';
import 'package:teampilot/utils/session/session_row_content.dart';

AppSession _session(String id, {String display = ''}) => AppSession(
  sessionId: id,
  workspaceId: 'ws-1',
  display: display,
  createdAt: 1,
  updatedAt: 1,
);

ChatState _state(List<AppSession> sessions) => ChatState(sessions: sessions);

void main() {
  test('reuses the index while the sessions list identity holds', () {
    final sessions = [_session('a'), _session('b')];
    final first = SessionLookup.indexOf(sessions);
    expect(identical(SessionLookup.indexOf(sessions), first), isTrue);
    expect(first.keys, orderedEquals(['a', 'b']));
  });

  test('rebuilds the index when ChatState swaps the sessions list', () {
    final before = [_session('a', display: 'Old')];
    expect(SessionRowContent.fromChatState(_state(before), 'a').display, 'Old');

    final after = [_session('a', display: 'New'), _session('b')];
    expect(SessionRowContent.fromChatState(_state(after), 'a').display, 'New');
    expect(SessionLookup.byId(after, 'b')?.sessionId, 'b');
    expect(SessionLookup.byId(after, 'missing'), isNull);
  });
}
