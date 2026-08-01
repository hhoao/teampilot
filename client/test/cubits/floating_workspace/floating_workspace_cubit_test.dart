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
    expect(cubit.state.activeBucket.tabs, isEmpty);
    cubit.setActiveWorkspace('ws-a');
    expect(cubit.state.activeBucket.tabs.single.id, 'f1');
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
    expect(cubit.state.activeBucket.activeTabId, 'b');

    cubit.reorderTabs(0, 2);
    expect(
      cubit.state.activeBucket.tabs.map((t) => t.id).toList(),
      ['b', 'a', 'c'],
    );
    expect(cubit.state.activeBucket.activeTabId, 'b');
  });
}
