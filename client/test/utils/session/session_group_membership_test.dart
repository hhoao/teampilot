import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_group.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/utils/session/session_group_membership.dart';

final _workspace = Workspace(
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp/ws-1')],
  createdAt: 1,
);

AppSession _s(
  String id, {
  String display = '',
  String workspaceId = 'ws-1',
  bool archived = false,
}) => AppSession(
  sessionId: id,
  workspaceId: workspaceId,
  display: display,
  createdAt: 1,
  updatedAt: 1,
  archived: archived,
);

SessionGroup _group(List<String> ids) =>
    SessionGroup(id: 'g1', name: 'Group', sessionIds: ids);

void main() {
  test('membership ignores display and extra sessions', () {
    final group = _group(['a', 'b']);
    final a = SessionGroupMembership.from(
      chatState: ChatState(
        sessions: [
          _s('a', display: 'old'),
          _s('b', display: 'beta'),
          _s('c', display: 'other'),
        ],
      ),
      group: group,
      workspace: _workspace,
    );
    final b = SessionGroupMembership.from(
      chatState: ChatState(
        sessions: [
          _s('a', display: 'renamed'),
          _s('b', display: 'beta'),
          _s('c', display: 'other'),
        ],
        workingSessionIds: {'a'},
      ),
      group: group,
      workspace: _workspace,
    );
    expect(a, b);
    expect(a.sessionIds, ['a', 'b']);
  });

  test('membership drops other-workspace and unknown ids', () {
    final membership = SessionGroupMembership.from(
      chatState: ChatState(
        sessions: [
          _s('a'),
          _s('x', workspaceId: 'ws-other'),
        ],
      ),
      group: _group(['a', 'x', 'missing']),
      workspace: _workspace,
    );
    expect(membership.sessionIds, ['a']);
  });

  test('membership excludes archived sessions', () {
    final membership = SessionGroupMembership.from(
      chatState: ChatState(
        sessions: [_s('active'), _s('archived', archived: true)],
      ),
      group: _group(['active', 'archived']),
      workspace: _workspace,
    );

    expect(membership.sessionIds, ['active']);
  });
}
