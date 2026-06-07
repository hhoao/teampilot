import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';

ChatTab _tab(String id) =>
    ChatTab(info: ChatTabInfo(id: id, title: id, subtitle: ''), cliTeamName: id);

void main() {
  group('ChatTabStore bucketing', () {
    test('append routes tabs to the active project bucket', () {
      final store = ChatTabStore();
      store.setActiveProject('A');
      store.append(_tab('a1'));
      store.append(_tab('a2'));
      store.setActiveProject('B');
      store.append(_tab('b1'));

      expect(store.length, 1);
      expect(store.tabs.single.info.id, 'b1');

      final restoredA = store.setActiveProject('A');
      expect(store.length, 2);
      expect(store.tabs.map((t) => t.info.id), ['a1', 'a2']);
      // A had no saved active index yet -> 0.
      expect(restoredA, 0);
    });

    test('append stamps the tab projectId', () {
      final store = ChatTabStore();
      store.setActiveProject('A');
      final tab = _tab('a1');
      store.append(tab);
      expect(tab.projectId, 'A');
    });

    test('setActiveProject snapshots and restores the active index', () {
      final store = ChatTabStore();
      store.setActiveProject('A');
      store.append(_tab('a1'));
      store.append(_tab('a2'));
      store.append(_tab('a3'));
      // Working in A, user is on index 2; snapshot it on the way out.
      store.setActiveProject('B', currentActiveIndex: 2);
      store.append(_tab('b1'));
      final restored = store.setActiveProject('A', currentActiveIndex: 0);
      expect(restored, 2);
    });

    test('removeProject returns and clears a bucket', () {
      final store = ChatTabStore();
      store.setActiveProject('A');
      store.append(_tab('a1'));
      store.append(_tab('a2'));
      final removed = store.removeProject('A');
      expect(removed.map((t) => t.info.id), ['a1', 'a2']);
      // Active bucket is now empty.
      store.setActiveProject('A');
      expect(store.isEmpty, isTrue);
    });

    test('sessionBackedCountForProject ignores local scratch tabs', () {
      final store = ChatTabStore();
      store.setActiveProject('A');
      store.append(_tab('sess-1'));
      store.append(_tab('local-team1'));
      expect(store.sessionBackedCountForProject('A'), 1);
    });

    test('indexOfSession and bySessionId scope to the active bucket', () {
      final store = ChatTabStore();
      store.setActiveProject('A');
      store.append(_tab('a1'));
      store.setActiveProject('B');
      store.append(_tab('b1'));
      expect(store.indexOfSession('a1'), -1);
      expect(store.indexOfSession('b1'), 0);
      expect(store.bySessionId('a1'), isNull);
      expect(store.bySessionId('b1')?.info.id, 'b1');
    });
  });
}
