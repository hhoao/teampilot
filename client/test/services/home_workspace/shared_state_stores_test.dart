import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/home_closed_workspace_entry.dart';
import 'package:teampilot/models/workspace_tab_ref.dart';
import 'package:teampilot/pages/home_workspace/workspace_sort.dart';
import 'package:teampilot/services/home_workspace/home_closed_workspaces_store.dart';
import 'package:teampilot/services/home_workspace/home_open_workspaces_store.dart';
import 'package:teampilot/services/home_workspace/home_recent_workspaces_store.dart';
import 'package:teampilot/services/home_workspace/workspace_display_prefs_store.dart';
import 'package:teampilot/services/home_workspace/workspace_favorites_store.dart';
import 'package:teampilot/services/shared_state/hlc.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;

  setUp(() {
    fs = InMemoryFilesystem();
  });

  HlcClock clockFor(String node) => HlcClock(
    nodeId: node,
    clock: () => DateTime.fromMillisecondsSinceEpoch(1000),
  );

  WorkspaceFavoritesStore favorites(String device) => WorkspaceFavoritesStore(
    storage: fakeHomeStorage(filesystem: fs),
    fs: fs,
    pathOverride: '/tp/favorites.json',
    deviceId: device,
    clock: clockFor(device),
  );

  HomeOpenWorkspacesStore openTabs(String device) => HomeOpenWorkspacesStore(
    storage: fakeHomeStorage(filesystem: fs),
    fs: fs,
    pathOverride: '/tp/open-tabs.json',
    deviceId: device,
    clock: clockFor(device),
  );

  HomeClosedWorkspacesStore closed(String device) => HomeClosedWorkspacesStore(
    storage: fakeHomeStorage(filesystem: fs),
    fs: fs,
    pathOverride: '/tp/closed.json',
    deviceId: device,
    clock: clockFor(device),
  );

  HomeRecentWorkspacesStore recent(String device) => HomeRecentWorkspacesStore(
    storage: fakeHomeStorage(filesystem: fs),
    fs: fs,
    pathOverride: '/tp/recent.json',
    deviceId: device,
    clock: clockFor(device),
  );

  WorkspaceDisplayPrefsStore displayPrefs(String device) =>
      WorkspaceDisplayPrefsStore(
        storage: fakeHomeStorage(filesystem: fs),
        fs: fs,
        pathOverride: '/tp/display.json',
        deviceId: device,
        clock: clockFor(device),
      );

  test('favorites from two devices merge instead of overwriting', () async {
    final a = favorites('a');
    final b = favorites('b');

    expect(await a.toggle('ws1'), isTrue);
    expect(await b.toggle('ws2'), isTrue);

    expect(await a.load(), {'ws1', 'ws2'});
    expect(await b.load(), {'ws1', 'ws2'});
  });

  test('open tabs are per-device lanes', () async {
    final a = openTabs('a');
    final b = openTabs('b');

    await a.saveOrderedTabs([
      const WorkspaceTabRef(workspaceId: 'ws1'),
      const WorkspaceTabRef(workspaceId: 'ws3'),
    ]);
    await b.saveOrderedTabs([const WorkspaceTabRef(workspaceId: 'ws2')]);

    expect(await a.loadOrderedTabs(), [
      const WorkspaceTabRef(workspaceId: 'ws1'),
      const WorkspaceTabRef(workspaceId: 'ws3'),
    ]);
    expect(await b.loadOrderedTabs(), [
      const WorkspaceTabRef(workspaceId: 'ws2'),
    ]);
  });

  test('closed workspaces are per-device lanes', () async {
    final a = closed('a');
    final b = closed('b');

    await a.recordClosed(
      const HomeClosedWorkspaceEntry(workspaceId: 'ws1', displayName: 'One'),
    );
    await b.recordClosed(
      const HomeClosedWorkspaceEntry(workspaceId: 'ws2', displayName: 'Two'),
    );

    expect((await a.load()).map((e) => e.workspaceId), ['ws1']);
    expect((await b.load()).map((e) => e.workspaceId), ['ws2']);
  });

  test('recents are per-device lanes', () async {
    final a = recent('a');
    final b = recent('b');

    await a.recordVisit(const WorkspaceTabRef(workspaceId: 'ws1'));
    await b.recordVisit(const WorkspaceTabRef(workspaceId: 'ws2'));

    expect(await a.loadOrderedTabs(), [
      const WorkspaceTabRef(workspaceId: 'ws1'),
    ]);
    expect(await b.loadOrderedTabs(), [
      const WorkspaceTabRef(workspaceId: 'ws2'),
    ]);
  });

  test('display prefs merge per key', () async {
    final a = displayPrefs('a');
    final b = displayPrefs('b');

    await a.setGridView(false);
    await b.setSort(WorkspaceSort.nameAsc);

    final prefs = await a.load();
    expect(prefs.gridView, isFalse);
    expect(prefs.sort, WorkspaceSort.nameAsc);
  });

  test('legacy favorites migrate into the OR-Set', () async {
    fs.files['/tp/favorites.json'] = '{"workspaceIds":["ws1"]}';
    final store = favorites('a');

    expect(await store.load(), {'ws1'});
    expect(await store.toggle('ws2'), isTrue);
    expect(await store.load(), {'ws1', 'ws2'});
  });

  test('legacy open tabs migrate into this device lane', () async {
    fs.files['/tp/open-tabs.json'] =
        '{"tabs":[{"workspaceId":"ws1"},{"workspaceId":"ws2"}]}';

    expect(await openTabs('a').loadOrderedTabs(), [
      const WorkspaceTabRef(workspaceId: 'ws1'),
      const WorkspaceTabRef(workspaceId: 'ws2'),
    ]);
  });

  test('legacy closed workspaces migrate and keep topology', () async {
    fs.files['/tp/closed.json'] =
        '{"entries":[{"workspaceId":"ws1","displayName":"One",'
        '"primaryPath":"/tmp/one","closedAt":5}]}';

    final loaded = await closed('a').load();
    expect(loaded.single.workspaceId, 'ws1');
    expect(loaded.single.primaryPath, '/tmp/one');
  });

  test('legacy display prefs migrate', () async {
    fs.files['/tp/display.json'] = '{"gridView":false,"sort":"nameAsc"}';

    final prefs = await displayPrefs('a').load();
    expect(prefs.gridView, isFalse);
    expect(prefs.sort, WorkspaceSort.nameAsc);
  });
}
