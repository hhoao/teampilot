import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/pages/workspace_ide/workspace_ide_shell.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';

void main() {
  const centerKey = ValueKey('center-smoke');
  const rightKey = ValueKey('right-smoke');

  Future<LayoutCubit> pumpShell(
    WidgetTester tester, {
    Size size = const Size(1400, 900),
  }) async {
    final layout = LayoutCubit();
    // Default wide viewport so the policy docks all intent-visible panes;
    // callers pass a narrow size to exercise the mobile drawer path.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(layout.close);

    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    await tester.pumpWidget(
      TpTheme(
        data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
        child: MaterialApp(
          home: BlocProvider<LayoutCubit>.value(
            value: layout,
            child: TpSidebarProvider(
              mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
              child: const Scaffold(
                body: WorkspaceIdeShell(
                  left: SizedBox(child: Text('left')),
                  center: ColoredBox(key: centerKey, color: Colors.transparent),
                  right: ColoredBox(key: rightKey, color: Colors.transparent),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return layout;
  }

  TpSidebarScope sidebarScope(WidgetTester tester) =>
      TpSidebarScope.of(tester.element(find.byType(WorkspaceIdeShell)));

  testWidgets('three builders mount under the IDE shell', (tester) async {
    await pumpShell(tester);
    expect(find.text('left'), findsOneWidget);
    expect(find.byKey(centerKey), findsOneWidget);
    expect(find.byKey(rightKey), findsOneWidget);
  });

  testWidgets('toggling right tools keeps the center workbench identity', (
    tester,
  ) async {
    final layout = await pumpShell(tester);

    final centerBefore = tester.element(find.byKey(centerKey));

    await layout.setRightToolsVisible(false);
    await tester.pumpAndSettle();

    await layout.setRightToolsVisible(true);
    await tester.pumpAndSettle();
    expect(
      identical(tester.element(find.byKey(centerKey)), centerBefore),
      isTrue,
      reason: 'center workbench was reparented on right-tools toggle',
    );
  });

  testWidgets(
    'narrow first paint keeps left drawer closed when prefs sidebarVisible',
    (tester) async {
      final layout = await pumpShell(tester, size: const Size(600, 900));
      expect(layout.state.preferences.sidebarVisible, isTrue);
      expect(find.text('left'), findsNothing);
      expect(find.byKey(centerKey), findsOneWidget);
    },
  );

  testWidgets('opening narrow left drawer writes sidebarVisible true', (
    tester,
  ) async {
    final layout = await pumpShell(tester, size: const Size(600, 900));
    expect(find.text('left'), findsNothing);

    sidebarScope(tester).setOpenMobile(true);
    await tester.pumpAndSettle();

    expect(find.text('left'), findsOneWidget);
    expect(layout.state.preferences.sidebarVisible, isTrue);
  });

  testWidgets('dismissing narrow left drawer clears sidebar intent', (
    tester,
  ) async {
    final layout = await pumpShell(tester, size: const Size(600, 900));
    sidebarScope(tester).setOpenMobile(true);
    await tester.pumpAndSettle();
    expect(find.text('left'), findsOneWidget);

    await tester.tapAt(const Offset(500, 450));
    await tester.pumpAndSettle();

    expect(layout.state.preferences.sidebarVisible, isFalse);
    expect(find.text('left'), findsNothing);
  });

  testWidgets('narrow right overlay still works independently of left drawer', (
    tester,
  ) async {
    await pumpShell(tester, size: const Size(600, 900));
    expect(find.text('left'), findsNothing);

    final layout = tester.element(find.byType(WorkspaceIdeShell));
    final cubit = BlocProvider.of<LayoutCubit>(layout);
    await cubit.setRightToolsVisible(true);
    await tester.pumpAndSettle();

    expect(find.byKey(rightKey), findsOneWidget);
    expect(find.text('left'), findsNothing);
  });

  testWidgets('narrow drawer toggle keeps the center workbench identity', (
    tester,
  ) async {
    await pumpShell(tester, size: const Size(600, 900));
    final centerBefore = tester.element(find.byKey(centerKey));
    final scope = sidebarScope(tester);

    scope.setOpenMobile(true);
    await tester.pumpAndSettle();
    scope.setOpenMobile(false);
    await tester.pumpAndSettle();

    expect(
      identical(tester.element(find.byKey(centerKey)), centerBefore),
      isTrue,
      reason: 'center was reparented when mobile drawer toggled',
    );
  });

  testWidgets('side panes stop before crushing the center workbench', (
    tester,
  ) async {
    final layout = await pumpShell(tester, size: const Size(1000, 900));
    await tester.pumpAndSettle();

    // Grow the left pane far past the old hard max; center must keep ≥ 320.
    await layout.setSidebarWidth(900);
    await tester.pumpAndSettle();

    final centerBox = tester.getSize(find.byKey(centerKey));
    expect(
      centerBox.width,
      greaterThanOrEqualTo(LayoutPreferences.minWorkbenchMainWidth - 1),
    );
  });
}
