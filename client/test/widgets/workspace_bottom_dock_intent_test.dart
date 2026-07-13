import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/run/run_ui_intent.dart';
import 'package:teampilot/widgets/workspace_bottom_dock.dart';

void main() {
  group('dockTabForActivateIntent', () {
    test('returns null when activateToolWindow is false', () {
      expect(
        dockTabForActivateIntent(
          const RunUiIntent(
            surface: RunToolSurface.terminal,
            activateToolWindow: false,
            focusToolWindow: true,
            terminalEntryId: 'e1',
          ),
        ),
        isNull,
      );
      expect(
        dockTabForActivateIntent(
          const RunUiIntent(
            surface: RunToolSurface.run,
            activateToolWindow: false,
            focusToolWindow: false,
          ),
        ),
        isNull,
      );
    });

    test('maps surface to dock tab when activateToolWindow is true', () {
      expect(
        dockTabForActivateIntent(
          const RunUiIntent(
            surface: RunToolSurface.terminal,
            activateToolWindow: true,
            focusToolWindow: false,
          ),
        ),
        WorkspaceBottomDockTab.terminal,
      );
      expect(
        dockTabForActivateIntent(
          const RunUiIntent(
            surface: RunToolSurface.run,
            activateToolWindow: true,
            focusToolWindow: true,
          ),
        ),
        WorkspaceBottomDockTab.run,
      );
    });
  });
}
