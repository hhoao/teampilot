import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late ChatTabStore store;

  setUp(() {
    store = ChatTabStore(storage: fakeHomeStorage())
      ..setActiveWorkspaceId('w1');
  });

  test('a persisted scratch tab resolves by its real session id', () {
    // Team scratch tabs are created before the session row exists, so they are
    // registered under `local-<teamId>` and only later gain a session id.
    final tab = store.appendLocalTab(
      const TeamProfile(id: 'team-1', name: 'Team'),
      cliTeamName: 'cli-team',
    );
    expect(tab.sessionId, 'local-team-1');
    expect(store.getOpenTabBySessionId('local-team-1'), same(tab));

    tab.persistedSession = AppSession(
      sessionId: 'session-1',
      workspaceId: 'w1',
      createdAt: 1,
    );

    expect(tab.sessionId, 'session-1');
    expect(
      store.getOpenTabBySessionId('session-1'),
      same(tab),
      reason: 'session-keyed lookups (pods, bar, history) must find the tab',
    );
    expect(
      store.getOpenTabBySessionId('local-team-1'),
      same(tab),
      reason: 'the stable tab id still resolves',
    );
    expect(store.sessionsForWorkspace('w1'), ['session-1']);
  });

  test('removeSession drops the entry under its stable tab key', () {
    final tab = store.appendLocalTab(
      const TeamProfile(id: 'team-1', name: 'Team'),
      cliTeamName: 'cli-team',
    );
    tab.persistedSession = AppSession(
      sessionId: 'session-1',
      workspaceId: 'w1',
      createdAt: 1,
    );

    expect(store.removeSession('session-1'), same(tab));
    expect(store.openTabs, isEmpty);
    expect(store.getOpenTabBySessionId('local-team-1'), isNull);
  });
}
