import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  group('LayoutCubit zoom', () {
    test('zoomIn switches to custom and steps multiplier by 0.1', () async {
      final cubit = LayoutCubit();
      addTearDown(cubit.close);

      await cubit.zoomIn(baseline: 1.0);

      expect(cubit.state.preferences.uiZoomScale, 'custom');
      expect(
        cubit.state.preferences.uiZoomCustomMultiplier,
        closeTo(1.1, 0.0001),
      );
    });

    test('zoomOut switches to custom and steps multiplier by -0.1', () async {
      final cubit = LayoutCubit();
      addTearDown(cubit.close);

      await cubit.zoomOut(baseline: 1.0);

      expect(cubit.state.preferences.uiZoomScale, 'custom');
      expect(
        cubit.state.preferences.uiZoomCustomMultiplier,
        closeTo(0.9, 0.0001),
      );
    });

    test('zoomIn compounds from the current effective multiplier', () async {
      final cubit = LayoutCubit();
      addTearDown(cubit.close);

      await cubit.zoomIn(baseline: 1.0);
      await cubit.zoomIn(baseline: 1.0);

      expect(
        cubit.state.preferences.uiZoomCustomMultiplier,
        closeTo(1.2, 0.0001),
      );
    });

    test(
      'zoomIn clamps the effective zoom (baseline × multiplier) at kUiZoomMax',
      () async {
        final cubit = LayoutCubit();
        addTearDown(cubit.close);

        for (var i = 0; i < 20; i++) {
          await cubit.zoomIn(baseline: 1.0);
        }

        expect(cubit.state.preferences.uiZoomCustomMultiplier, kUiZoomMax);
      },
    );

    test(
      'zoomOut clamps the effective zoom (baseline × multiplier) at kUiZoomMin',
      () async {
        final cubit = LayoutCubit();
        addTearDown(cubit.close);

        for (var i = 0; i < 20; i++) {
          await cubit.zoomOut(baseline: 1.0);
        }

        expect(cubit.state.preferences.uiZoomCustomMultiplier, kUiZoomMin);
      },
    );

    test('zoomIn accounts for a non-1.0 baseline when clamping', () async {
      final cubit = LayoutCubit();
      addTearDown(cubit.close);

      // baseline 2.0 already puts standard (×1.0) above kUiZoomMax (1.5)
      // effective; the clamp must express the result back in multiplier
      // space (kUiZoomMax / baseline), not just cap at kUiZoomMax itself.
      await cubit.zoomIn(baseline: 2.0);

      expect(
        cubit.state.preferences.uiZoomCustomMultiplier,
        closeTo(kUiZoomMax / 2.0, 0.0001),
      );
    });

    test('zoomReset sets the scale id back to standard', () async {
      final cubit = LayoutCubit();
      addTearDown(cubit.close);

      await cubit.zoomIn(baseline: 1.0);
      await cubit.zoomReset();

      expect(cubit.state.preferences.uiZoomScale, 'standard');
    });
  });

  group('LayoutCubit view toggles', () {
    test('toggleSidebar flips sidebarVisible', () async {
      final cubit = LayoutCubit();
      addTearDown(cubit.close);
      final initial = cubit.state.preferences.sidebarVisible;

      await cubit.toggleSidebar();
      expect(cubit.state.preferences.sidebarVisible, !initial);

      await cubit.toggleSidebar();
      expect(cubit.state.preferences.sidebarVisible, initial);
    });

    test('toggleRightTools flips rightToolsVisible', () async {
      final cubit = LayoutCubit();
      addTearDown(cubit.close);
      final initial = cubit.state.preferences.rightToolsVisible;

      await cubit.toggleRightTools();
      expect(cubit.state.preferences.rightToolsVisible, !initial);

      await cubit.toggleRightTools();
      expect(cubit.state.preferences.rightToolsVisible, initial);
    });

    test('toggleWorkspaceTerminal is a no-op on workspaceTerminalVisible', () async {
      final cubit = LayoutCubit();
      addTearDown(cubit.close);
      final initial = cubit.state.preferences.workspaceTerminalVisible;

      await cubit.toggleWorkspaceTerminal();
      expect(cubit.state.preferences.workspaceTerminalVisible, initial);

      await cubit.setWorkspaceTerminalVisible(true);
      expect(cubit.state.preferences.workspaceTerminalVisible, initial);
    });
  });
}
