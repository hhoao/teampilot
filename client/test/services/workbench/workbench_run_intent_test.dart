import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/floating_workspace_tab.dart';
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

    test('terminal surface + activate → null (floating surface owns shell)', () {
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
        isNull,
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

    test('trims latestRunSessionId', () {
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

  group('resolveFloatingTabForTerminalRunIntent', () {
    test('activateToolWindow false → null', () {
      expect(
        resolveFloatingTabForTerminalRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.terminal,
            activateToolWindow: false,
            focusToolWindow: true,
            terminalEntryId: 'e1',
          ),
          entryTitle: 'Local',
        ),
        isNull,
      );
    });

    test('run surface → null', () {
      expect(
        resolveFloatingTabForTerminalRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.run,
            activateToolWindow: true,
            focusToolWindow: false,
          ),
          entryTitle: 'Local',
        ),
        isNull,
      );
    });

    test('terminal surface + entry id → floating shell tab', () {
      expect(
        resolveFloatingTabForTerminalRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.terminal,
            activateToolWindow: true,
            focusToolWindow: true,
            terminalEntryId: 'e1',
          ),
          entryTitle: 'Local',
        ),
        const FloatingTab(
          id: 'shell:e1',
          surfaceId: 'terminal',
          title: 'Local',
          payload: 'e1',
        ),
      );
    });

    test('empty entry title falls back to entry id', () {
      expect(
        resolveFloatingTabForTerminalRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.terminal,
            activateToolWindow: true,
            focusToolWindow: false,
            terminalEntryId: 'e1',
          ),
          entryTitle: '',
        ),
        const FloatingTab(
          id: 'shell:e1',
          surfaceId: 'terminal',
          title: 'e1',
          payload: 'e1',
        ),
      );
    });

    test('empty or whitespace terminalEntryId → null', () {
      expect(
        resolveFloatingTabForTerminalRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.terminal,
            activateToolWindow: true,
            focusToolWindow: false,
          ),
          entryTitle: 'Local',
        ),
        isNull,
      );
      expect(
        resolveFloatingTabForTerminalRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.terminal,
            activateToolWindow: true,
            focusToolWindow: false,
            terminalEntryId: '   ',
          ),
          entryTitle: 'Local',
        ),
        isNull,
      );
    });

    test('trims terminalEntryId and entryTitle', () {
      expect(
        resolveFloatingTabForTerminalRunIntent(
          const RunUiIntent(
            surface: RunToolSurface.terminal,
            activateToolWindow: true,
            focusToolWindow: false,
            terminalEntryId: '  e1  ',
          ),
          entryTitle: '  Local  ',
        ),
        const FloatingTab(
          id: 'shell:e1',
          surfaceId: 'terminal',
          title: 'Local',
          payload: 'e1',
        ),
      );
    });
  });
}
