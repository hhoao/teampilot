import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_panel_visibility.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_state.dart';

void main() {
  test('toggle open ↔ minimized; maximize only while open', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);

    expect(cubit.state.visibility, FloatingPanelVisibility.hidden);
    cubit.toggle();
    expect(cubit.state.visibility, FloatingPanelVisibility.open);

    cubit.setMaximized(true);
    expect(cubit.state.isMaximized, isTrue);

    cubit.toggle();
    expect(cubit.state.visibility, FloatingPanelVisibility.minimized);
    expect(cubit.state.isMaximized, isTrue); // retained while minimized

    cubit.toggle();
    expect(cubit.state.visibility, FloatingPanelVisibility.open);
    expect(cubit.state.isMaximized, isTrue);
  });

  test('ensureTab is per-workspace; setActiveWorkspace swaps bucket view', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);

    cubit.setActiveWorkspace('ws-a');
    cubit.ensureOpen();
    cubit.ensureTab(
      FloatingTab(
        id: 'f1',
        surfaceId: 'filePreview',
        title: 'a.txt',
        payload: '/a.txt',
      ),
    );
    cubit.setActiveWorkspace('ws-b');
    expect(cubit.activeBucket.tabs, isEmpty);
    cubit.setActiveWorkspace('ws-a');
    expect(cubit.activeBucket.tabs.single.id, 'f1');
  });

  test('minimizeWithNoTabsGoesHidden when bucket empty', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    cubit.ensureOpen();
    cubit.minimize(closeIfEmpty: true);
    expect(cubit.state.visibility, FloatingPanelVisibility.hidden);
  });

  test('reorderTabs permutes order and keeps activeTabId', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    cubit.setActiveWorkspace('ws-a');
    cubit.ensureTab(
      FloatingTab(
        id: 'a',
        surfaceId: 'filePreview',
        title: 'a.txt',
        payload: '/a.txt',
      ),
    );
    cubit.ensureTab(
      FloatingTab(
        id: 'b',
        surfaceId: 'filePreview',
        title: 'b.txt',
        payload: '/b.txt',
      ),
    );
    cubit.ensureTab(
      FloatingTab(
        id: 'c',
        surfaceId: 'terminal',
        title: 'term',
        payload: 't1',
      ),
    );
    cubit.selectTab('b');
    expect(cubit.activeBucket.activeTabId, 'b');

    cubit.reorderTabs(0, 1);
    expect(
      cubit.activeBucket.tabs.map((t) => t.id).toList(),
      ['b', 'a', 'c'],
    );
    expect(cubit.activeBucket.activeTabId, 'b');
  });

  test('activeTabFor projects the active tab of the active workspace', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    cubit.setActiveWorkspace('ws-a');
    expect(cubit.activeTabFor('ws-a'), isNull);

    cubit.ensureTab(
      FloatingTab(
        id: 'f1',
        surfaceId: 'filePreview',
        title: 'a.txt',
        payload: '/a.txt',
      ),
    );
    expect(cubit.activeTabFor('ws-a')?.id, 'f1');
    expect(cubit.activeTabFor('ws-a')?.surfaceId, 'filePreview');
    expect(cubit.activeTabFor('ws-a')?.payload, '/a.txt');

    // ensureTab makes the latest tab active; surface/payload pass through.
    cubit.ensureTab(
      FloatingTab(id: 't1', surfaceId: 'terminal', title: 'term', payload: 'e1'),
    );
    expect(cubit.activeTabFor('ws-a')?.id, 't1');
    expect(cubit.activeTabFor('ws-a')?.surfaceId, 'terminal');

    cubit.selectTab('f1');
    expect(cubit.activeTabFor('ws-a')?.id, 'f1');

    // Inactive workspaces / no tabs → null.
    expect(cubit.activeTabFor('ws-other'), isNull);
    cubit.setActiveWorkspace('ws-b');
    expect(cubit.activeTabFor('ws-a'), isNull);
    expect(cubit.activeTabFor('ws-b'), isNull);
  });

  test('tabsChanged fires on tab mutations only, not chrome emits', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    var tabTicks = 0;
    cubit.tabsChanged.addListener(() => tabTicks++);

    cubit.ensureOpen();
    cubit.setMaximized(true);
    cubit.setActiveWorkspace('ws-a');
    expect(tabTicks, 0, reason: 'chrome emits must not fire tabsChanged');

    cubit.ensureTab(
      FloatingTab(
        id: 'f1',
        surfaceId: 'filePreview',
        title: 'a.txt',
        payload: '/a.txt',
      ),
    );
    expect(tabTicks, 1);
    cubit.selectTab('f1');
    expect(tabTicks, 1, reason: 'no-op select must not fire');
    cubit.removeTab('f1');
    expect(tabTicks, 2);
    cubit.removeTab('f1');
    expect(tabTicks, 2, reason: 'removing a missing tab must not fire');
  });
}
