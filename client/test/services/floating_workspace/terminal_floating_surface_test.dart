import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/l10n/l10n_compat.dart';
import 'package:teampilot/models/floating_workspace_tab.dart';
import 'package:teampilot/models/workbench_shell_descriptor.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/services/floating_workspace/surfaces/terminal_floating_surface.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';
import 'package:teampilot/services/terminal/workspace_terminal_run_service.dart';

const _descriptor = WorkbenchShellDescriptor(
  cwd: '/tmp/proj',
  spec: WorkspaceTerminalLocalSpec('/bin/bash'),
);

class _SurfaceHost extends StatelessWidget {
  const _SurfaceHost({required this.surface, required this.tab});

  final TerminalFloatingSurface surface;
  final FloatingTab tab;

  @override
  Widget build(BuildContext context) => surface.build(context, tab);
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: appLocalizationsSupportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: child),
);

void main() {
  test('createTab titles a persisted tab from its cwd basename', () {
    final surface = TerminalFloatingSurface(
      floating: FloatingWorkspaceCubit(),
      registry: WorkspaceTerminalRegistry(),
      runService: WorkspaceTerminalRunService(),
      descriptorFor: (_, id) => id == 'persisted' ? _descriptor : null,
    );
    final tab = surface.createTab(workspaceId: 'ws', payload: 'persisted');
    expect(tab.title, 'proj');
  });

  testWidgets('a restored tab shows the placeholder and restores once', (
    tester,
  ) async {
    final floating = FloatingWorkspaceCubit()..setActiveWorkspace('ws');
    final registry = WorkspaceTerminalRegistry();
    var calls = 0;
    final surface = TerminalFloatingSurface(
      floating: floating,
      registry: registry,
      runService: WorkspaceTerminalRunService(),
      descriptorFor: (_, id) => id == 'persisted' ? _descriptor : null,
      restoreTab:
          ({
            required String workspaceId,
            required String tabId,
            required WorkbenchShellDescriptor descriptor,
          }) async {
            calls++;
          },
    );
    final tab = surface.createTab(workspaceId: 'ws', payload: 'persisted');

    await tester.pumpWidget(_app(_SurfaceHost(surface: surface, tab: tab)));
    await tester.pump();
    await tester.pump();

    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Restoring terminal…'), findsOneWidget);
  });

  testWidgets('a failed restore shows retry and can re-run', (tester) async {
    final floating = FloatingWorkspaceCubit()..setActiveWorkspace('ws');
    var calls = 0;
    final surface = TerminalFloatingSurface(
      floating: floating,
      registry: WorkspaceTerminalRegistry(),
      runService: WorkspaceTerminalRunService(),
      descriptorFor: (_, id) => id == 'persisted' ? _descriptor : null,
      restoreTab:
          ({
            required String workspaceId,
            required String tabId,
            required WorkbenchShellDescriptor descriptor,
          }) async {
            calls++;
            throw StateError('boom');
          },
    );
    final tab = surface.createTab(workspaceId: 'ws', payload: 'persisted');

    await tester.pumpWidget(_app(_SurfaceHost(surface: surface, tab: tab)));
    await tester.pump();
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(calls, 2);
  });
}
