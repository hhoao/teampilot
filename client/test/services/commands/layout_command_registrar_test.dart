import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/layout_command_registrar.dart';

void main() {
  group('registerLayoutCommands', () {
    late CommandBus bus;
    late LayoutCubit layout;

    setUp(() {
      bus = CommandBus();
      layout = LayoutCubit();
      registerLayoutCommands(bus, layout);
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

    test('togglePanel command flips workspaceTerminalVisible', () async {
      final initial = layout.state.preferences.workspaceTerminalVisible;

      bus.invoke(CommandIds.togglePanel);
      await Future<void>.delayed(Duration.zero);

      expect(layout.state.preferences.workspaceTerminalVisible, !initial);
    });

    test('toggleSecondarySidebar command flips rightToolsVisible', () async {
      final initial = layout.state.preferences.rightToolsVisible;

      bus.invoke(CommandIds.toggleSecondarySidebar);
      await Future<void>.delayed(Duration.zero);

      expect(layout.state.preferences.rightToolsVisible, !initial);
    });
  });
}
