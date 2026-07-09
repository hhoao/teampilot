import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';

ChatTab _tab(String id) => ChatTab(
  info: ChatTabInfo(id: id, title: id, subtitle: ''),
  cliTeamName: id,
);

void main() {
  group('ChatTabStore bucketing', () {
    test('append routes tabs to the active workspace bucket', () {
      final store = ChatTabStore();
      store.setActiveWorkspace('A');
      store.append(_tab('a1'));
      store.append(_tab('a2'));
      store.setActiveWorkspace('B');
      store.append(_tab('b1'));

      expect(store.activeTabCount, 1);
      expect(store.activeTabs.single.info.id, 'b1');

      final restoredA = store.setActiveWorkspace('A');
      expect(store.activeTabCount, 2);
      expect(store.activeTabs.map((t) => t.info.id), ['a1', 'a2']);
      expect(restoredA, 0);
    });

    test('append stamps the tab workspaceId', () {
      final store = ChatTabStore();
      store.setActiveWorkspace('A');
      final tab = _tab('a1');
      store.append(tab);
      expect(tab.workspaceId, 'A');
    });

    test('setActiveWorkspace snapshots and restores the active index', () {
      final store = ChatTabStore();
      store.setActiveWorkspace('A');
      store.append(_tab('a1'));
      store.append(_tab('a2'));
      store.append(_tab('a3'));
      store.setActiveWorkspace('B', currentActiveIndex: 2);
      store.append(_tab('b1'));
      final restored = store.setActiveWorkspace('A', currentActiveIndex: 0);
      expect(restored, 2);
    });

    test('removeWorkspace returns and clears a bucket', () {
      final store = ChatTabStore();
      store.setActiveWorkspace('A');
      store.append(_tab('a1'));
      store.append(_tab('a2'));
      final removed = store.removeWorkspace('A');
      expect(removed.map((t) => t.info.id), ['a1', 'a2']);
      store.setActiveWorkspace('A');
      expect(store.activeTabsIsEmpty, isTrue);
    });

    test('sessionBackedCountForWorkspace ignores local scratch tabs', () {
      final store = ChatTabStore();
      store.setActiveWorkspace('A');
      store.append(_tab('sess-1'));
      store.append(_tab('local-team1'));
      expect(store.sessionBackedCountForWorkspace('A'), 1);
    });

    test('view vs runtime session lookup', () {
      final store = ChatTabStore();
      store.setActiveWorkspace('A');
      store.append(_tab('a1'));
      store.setActiveWorkspace('B');
      store.append(_tab('b1'));
      expect(store.activeIndexOfSession('a1'), -1);
      expect(store.activeIndexOfSession('b1'), 0);
      expect(store.activeTabBySessionId('a1'), isNull);
      expect(store.activeTabBySessionId('b1')?.info.id, 'b1');
      expect(store.openTabBySessionId('a1')?.info.id, 'a1');
      expect(store.openTabBySessionId('b1')?.info.id, 'b1');
      expect(store.hasOpenTabs, isTrue);
    });

    test(
      'tabsForWorkspace and savedActiveIndexFor read non-active buckets',
      () {
        final store = ChatTabStore();
        store.setActiveWorkspace('A');
        store.append(_tab('a1'));
        store.append(_tab('a2'));
        store.setActiveWorkspace('B', currentActiveIndex: 1);
        store.append(_tab('b1'));

        expect(store.tabsForWorkspace('A').map((t) => t.info.id), ['a1', 'a2']);
        expect(store.savedActiveIndexFor('A'), 1);
        expect(store.tabsForWorkspace('B').map((t) => t.info.id), ['b1']);
      },
    );
  });
}
