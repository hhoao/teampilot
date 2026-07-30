import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_panel_visibility.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';

void main() {
  test('ensureOpen and toggle-to-open clear attention', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);

    cubit.ensureOpen();
    cubit.minimize();
    cubit.setAttention(true);
    expect(cubit.state.attention, isTrue);
    expect(cubit.state.visibility, FloatingPanelVisibility.minimized);

    cubit.ensureOpen();
    expect(cubit.state.visibility, FloatingPanelVisibility.open);
    expect(cubit.state.attention, isFalse);

    cubit.minimize();
    cubit.setAttention(true);
    cubit.toggle(); // minimized → open
    expect(cubit.state.visibility, FloatingPanelVisibility.open);
    expect(cubit.state.attention, isFalse);
  });

  test('ensureOpen while already open still clears attention', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);

    cubit.ensureOpen();
    cubit.setAttention(true);
    cubit.ensureOpen();
    expect(cubit.state.attention, isFalse);
  });
}
