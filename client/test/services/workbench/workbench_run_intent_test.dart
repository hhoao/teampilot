import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/run/run_ui_intent.dart';
import 'package:teampilot/services/workbench/workbench_run_intent.dart';

void main() {
  group('resolveWorkbenchTabForRunIntent', () {
    test('activateToolWindow false → null even with latestRunSessionId', () {
      expect(
        resolveWorkbenchTabForRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.run,
            activateToolWindow: false,
            focusToolWindow: false,
          ),
          latestRunSessionId: 'r9',
        ),
        isNull,
      );
      expect(
        resolveWorkbenchTabForRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.terminal,
            activateToolWindow: false,
            focusToolWindow: true,
            terminalEntryId: 'e1',
          ),
          latestRunSessionId: 'r9',
        ),
        isNull,
      );
    });

    test('run surface + activate → WorkbenchTabId.run(latest)', () {
      expect(
        resolveWorkbenchTabForRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.run,
            activateToolWindow: true,
            focusToolWindow: false,
          ),
          latestRunSessionId: 'r9',
        ),
        WorkbenchTabId.run('r9'),
      );
    });

    test('terminal surface + activate + terminalEntryId → shell(id)', () {
      expect(
        resolveWorkbenchTabForRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.terminal,
            activateToolWindow: true,
            focusToolWindow: true,
            terminalEntryId: 'e1',
          ),
          latestRunSessionId: null,
        ),
        WorkbenchTabId.shell('e1'),
      );
    });

    test('empty or whitespace terminalEntryId → null', () {
      expect(
        resolveWorkbenchTabForRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.terminal,
            activateToolWindow: true,
            focusToolWindow: false,
          ),
          latestRunSessionId: null,
        ),
        isNull,
      );
      expect(
        resolveWorkbenchTabForRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.terminal,
            activateToolWindow: true,
            focusToolWindow: false,
            terminalEntryId: '',
          ),
          latestRunSessionId: null,
        ),
        isNull,
      );
      expect(
        resolveWorkbenchTabForRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.terminal,
            activateToolWindow: true,
            focusToolWindow: false,
            terminalEntryId: '   ',
          ),
          latestRunSessionId: null,
        ),
        isNull,
      );
    });

    test('null or empty latestRunSessionId on run surface → null', () {
      expect(
        resolveWorkbenchTabForRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.run,
            activateToolWindow: true,
            focusToolWindow: false,
          ),
          latestRunSessionId: null,
        ),
        isNull,
      );
      expect(
        resolveWorkbenchTabForRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.run,
            activateToolWindow: true,
            focusToolWindow: false,
          ),
          latestRunSessionId: '',
        ),
        isNull,
      );
      expect(
        resolveWorkbenchTabForRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.run,
            activateToolWindow: true,
            focusToolWindow: false,
          ),
          latestRunSessionId: '   ',
        ),
        isNull,
      );
    });

    test('trims terminalEntryId and latestRunSessionId', () {
      expect(
        resolveWorkbenchTabForRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.terminal,
            activateToolWindow: true,
            focusToolWindow: false,
            terminalEntryId: '  e1  ',
          ),
          latestRunSessionId: null,
        ),
        WorkbenchTabId.shell('e1'),
      );
      expect(
        resolveWorkbenchTabForRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.run,
            activateToolWindow: true,
            focusToolWindow: false,
          ),
          latestRunSessionId: '  r9  ',
        ),
        WorkbenchTabId.run('r9'),
      );
    });
  });
}
