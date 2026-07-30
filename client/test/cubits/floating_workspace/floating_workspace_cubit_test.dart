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
}
