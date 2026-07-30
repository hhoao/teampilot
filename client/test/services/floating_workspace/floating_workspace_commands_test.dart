import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_panel_visibility.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/floating_workspace/floating_workspace_commands.dart';

void main() {
  group('registerFloatingWorkspaceCommands', () {
    late CommandBus bus;
    late FloatingWorkspaceCubit floating;

    setUp(() {
      bus = CommandBus();
      floating = FloatingWorkspaceCubit();
      registerFloatingWorkspaceCommands(bus, floating);
    });

    tearDown(() => floating.close());

    test('toggle flips visibility via cubit', () async {
      expect(floating.state.visibility, FloatingPanelVisibility.hidden);

      bus.invoke(CommandIds.floatingToggle);
      await Future<void>.delayed(Duration.zero);
      expect(floating.state.visibility, FloatingPanelVisibility.open);

      bus.invoke(CommandIds.floatingToggle);
      await Future<void>.delayed(Duration.zero);
      expect(floating.state.visibility, FloatingPanelVisibility.minimized);
    });

    test('maximize opens maximized when closed; toggles when open', () async {
      bus.invoke(CommandIds.floatingMaximize);
      await Future<void>.delayed(Duration.zero);
      expect(floating.state.visibility, FloatingPanelVisibility.open);
      expect(floating.state.isMaximized, isTrue);

      bus.invoke(CommandIds.floatingMaximize);
      await Future<void>.delayed(Duration.zero);
      expect(floating.state.isMaximized, isFalse);
    });

    test('minimize sets minimized visibility', () async {
      floating.ensureOpen();
      bus.invoke(CommandIds.floatingMinimize);
      await Future<void>.delayed(Duration.zero);
      expect(floating.state.visibility, FloatingPanelVisibility.minimized);
    });

    test('newTerminal ensureOpen and invokes callback', () async {
      var calls = 0;
      final callbackBus = CommandBus();
      final cubit = FloatingWorkspaceCubit();
      addTearDown(cubit.close);
      registerFloatingWorkspaceCommands(
        callbackBus,
        cubit,
        onNewTerminal: () async {
          calls++;
        },
      );

      callbackBus.invoke(CommandIds.floatingNewTerminal);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.visibility, FloatingPanelVisibility.open);
      expect(calls, 1);
    });

    test('openFile ensureOpen when callback is null', () async {
      bus.invoke(CommandIds.floatingOpenFile);
      await Future<void>.delayed(Duration.zero);
      expect(floating.state.visibility, FloatingPanelVisibility.open);
    });

    test('openFile ensureOpen and invokes callback', () async {
      var calls = 0;
      final callbackBus = CommandBus();
      final cubit = FloatingWorkspaceCubit();
      addTearDown(cubit.close);
      registerFloatingWorkspaceCommands(
        callbackBus,
        cubit,
        onOpenFile: () async {
          calls++;
        },
      );

      callbackBus.invoke(CommandIds.floatingOpenFile);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.visibility, FloatingPanelVisibility.open);
      expect(calls, 1);
    });
  });
}
