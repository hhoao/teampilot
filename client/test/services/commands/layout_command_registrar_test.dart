import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_panel_visibility.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/models/floating_workspace_tab.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/layout_command_registrar.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  group('registerLayoutCommands', () {
    late CommandBus bus;
    late LayoutCubit layout;
    late double baseline;

    setUp(() {
      bus = CommandBus();
      layout = LayoutCubit();
      baseline = 1.0;
      registerLayoutCommands(
        bus,
        layout,
        uiZoomBaseline: () => baseline,
      );
    });

    tearDown(() => layout.close());

    test('zoomIn command steps the ui zoom multiplier up', () async {
      bus.invoke(CommandIds.zoomIn);
      await Future<void>.delayed(Duration.zero);

      expect(layout.state.preferences.uiZoomScale, 'custom');
      expect(
        layout.state.preferences.uiZoomCustomMultiplier,
        closeTo(1.1, 0.0001),
      );
    });

    test('zoomOut command steps the ui zoom multiplier down', () async {
      bus.invoke(CommandIds.zoomOut);
      await Future<void>.delayed(Duration.zero);

      expect(layout.state.preferences.uiZoomScale, 'custom');
      expect(
        layout.state.preferences.uiZoomCustomMultiplier,
        closeTo(0.9, 0.0001),
      );
    });

    test(
      'zoomIn clamps differently for baseline 0.5 than 1.0 near the edge',
      () async {
        baseline = 0.5;
        for (var i = 0; i < 20; i++) {
          bus.invoke(CommandIds.zoomIn);
          await Future<void>.delayed(Duration.zero);
        }

        final atHalfBaseline =
            layout.state.preferences.uiZoomCustomMultiplier;

        await layout.zoomReset();
        baseline = 1.0;
        for (var i = 0; i < 20; i++) {
          bus.invoke(CommandIds.zoomIn);
          await Future<void>.delayed(Duration.zero);
        }

        final atUnitBaseline =
            layout.state.preferences.uiZoomCustomMultiplier;

        expect(atHalfBaseline, closeTo(kTypographyCustomMultiplierMax, 0.0001));
        expect(atUnitBaseline, closeTo(kUiZoomMax, 0.0001));
        expect(atHalfBaseline, isNot(closeTo(atUnitBaseline, 0.0001)));
      },
    );

    test('zoomReset command resets the scale id to standard', () async {
      bus.invoke(CommandIds.zoomIn);
      await Future<void>.delayed(Duration.zero);
      bus.invoke(CommandIds.zoomReset);
      await Future<void>.delayed(Duration.zero);

      expect(layout.state.preferences.uiZoomScale, 'standard');
    });

    test('toggleSidebar command flips sidebarVisible', () async {
      final initial = layout.state.preferences.sidebarVisible;

      bus.invoke(CommandIds.toggleSidebar);
      await Future<void>.delayed(Duration.zero);

      expect(layout.state.preferences.sidebarVisible, !initial);
    });

    test(
      'togglePanel without handler is a no-op on workspaceTerminalVisible',
      () async {
        final initial = layout.state.preferences.workspaceTerminalVisible;

        bus.invoke(CommandIds.togglePanel);
        await Future<void>.delayed(Duration.zero);

        expect(layout.state.preferences.workspaceTerminalVisible, initial);
      },
    );

    test('togglePanel invokes onTogglePanel create-or-focus handler', () async {
      final floating = FloatingWorkspaceCubit();
      addTearDown(floating.close);
      var calls = 0;
      final panelBus = CommandBus();
      registerLayoutCommands(
        panelBus,
        layout,
        uiZoomBaseline: () => baseline,
        onTogglePanel: () async {
          calls++;
          floating.ensureOpen();
          floating.setActiveWorkspace('ws');
          floating.ensureTab(
            const FloatingTab(
              id: 'shell:e1',
              surfaceId: 'terminal',
              title: 'Local',
              payload: 'e1',
            ),
          );
        },
      );
      final terminalVisible = layout.state.preferences.workspaceTerminalVisible;

      panelBus.invoke(CommandIds.togglePanel);
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
      expect(layout.state.preferences.workspaceTerminalVisible, terminalVisible);
      expect(floating.state.visibility, FloatingPanelVisibility.open);
      expect(
        floating.activeBucket.tabs.any((t) => t.payload == 'e1'),
        isTrue,
      );
    });

    test('toggleSecondarySidebar command flips rightToolsVisible', () async {
      final initial = layout.state.preferences.rightToolsVisible;

      bus.invoke(CommandIds.toggleSecondarySidebar);
      await Future<void>.delayed(Duration.zero);

      expect(layout.state.preferences.rightToolsVisible, !initial);
    });

    test('toggleSecondarySidebar on compose flips override not prefs', () async {
      final composeBus = CommandBus();
      var compose = true;
      registerLayoutCommands(
        composeBus,
        layout,
        uiZoomBaseline: () => baseline,
        composeLanding: () => compose,
      );
      final intent = layout.state.preferences.rightToolsVisible;

      composeBus.invoke(CommandIds.toggleSecondarySidebar);
      await Future<void>.delayed(Duration.zero);

      expect(layout.state.landingRightToolsOverride, isTrue);
      expect(layout.state.preferences.rightToolsVisible, intent);
    });
  });
}
