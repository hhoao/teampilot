import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_panel_visibility.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';

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

  test('setActiveWorkspace drives the chrome workspace id', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);

    cubit.setActiveWorkspace('ws-a');
    expect(cubit.state.activeWorkspaceId, 'ws-a');
    cubit.setActiveWorkspace('ws-b');
    expect(cubit.state.activeWorkspaceId, 'ws-b');
  });

  test('minimize(closeIfEmpty: true) hides the panel', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    cubit.ensureOpen();
    cubit.minimize(closeIfEmpty: true);
    expect(cubit.state.visibility, FloatingPanelVisibility.hidden);
  });

  test('minimize without closeIfEmpty keeps chrome alive', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    cubit.ensureOpen();
    cubit.minimize();
    expect(cubit.state.visibility, FloatingPanelVisibility.minimized);
  });

  test('disposeWorkspace resets activeWorkspaceId when it matches', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);

    cubit.setActiveWorkspace('ws-a');
    cubit.disposeWorkspace('ws-b');
    expect(cubit.state.activeWorkspaceId, 'ws-a',
        reason: 'other workspace chrome is untouched');

    cubit.disposeWorkspace('ws-a');
    expect(cubit.state.activeWorkspaceId, '');
  });

  test('attention flag follows setAttention', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    expect(cubit.state.attention, isFalse);
    cubit.setAttention(true);
    expect(cubit.state.attention, isTrue);
    cubit.ensureOpen();
    expect(cubit.state.attention, isFalse);
  });
}
