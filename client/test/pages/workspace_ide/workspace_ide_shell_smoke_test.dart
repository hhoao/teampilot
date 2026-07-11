import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/pages/workspace_ide/workspace_ide_shell.dart';

void main() {
  const bottomKey = ValueKey('workspace-terminal-smoke');
  const centerKey = ValueKey('center-smoke');
  const rightKey = ValueKey('right-smoke');

  Future<LayoutCubit> pumpShell(
    WidgetTester tester, {
    Size size = const Size(1400, 900),
  }) async {
    final layout = LayoutCubit();
    // Default wide viewport so the policy docks all intent-visible panes;
    // callers pass a narrow size to exercise the overlay path.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(layout.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<LayoutCubit>.value(
          value: layout,
          child: const Scaffold(
            body: WorkspaceIdeShell(
              left: SizedBox(child: Text('left')),
              center: ColoredBox(key: centerKey, color: Colors.transparent),
              right: ColoredBox(key: rightKey, color: Colors.transparent),
              bottom: ColoredBox(key: bottomKey, color: Colors.black),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return layout;
  }

  testWidgets('four builders mount under the IDE shell', (tester) async {
    await pumpShell(tester);
    expect(find.text('left'), findsOneWidget);
    expect(find.byKey(centerKey), findsOneWidget);
    expect(find.byKey(rightKey), findsOneWidget);
    expect(find.byKey(bottomKey), findsOneWidget);
  });

  testWidgets('toggling right tools keeps the bottom terminal element identity', (
    tester,
  ) async {
    final layout = await pumpShell(tester);

    final bottomBefore = tester.element(find.byKey(bottomKey));
    final centerBefore = tester.element(find.byKey(centerKey));

    // Hide right tools, then show again — bottom + center must not reparent.
    await layout.setRightToolsVisible(false);
    await tester.pumpAndSettle();
    expect(find.byKey(bottomKey), findsOneWidget);
    expect(
      identical(tester.element(find.byKey(bottomKey)), bottomBefore),
      isTrue,
      reason: 'bottom terminal was reparented/disposed on right-tools hide',
    );

    await layout.setRightToolsVisible(true);
    await tester.pumpAndSettle();
    expect(
      identical(tester.element(find.byKey(bottomKey)), bottomBefore),
      isTrue,
      reason: 'bottom terminal was reparented/disposed on right-tools show',
    );
    expect(
      identical(tester.element(find.byKey(centerKey)), centerBefore),
      isTrue,
      reason: 'center workbench was reparented on right-tools toggle',
    );
  });

  testWidgets('narrow viewport presents left as an overlay, not docked', (
    tester,
  ) async {
    // Narrow width (< WorkspacePanePolicy.narrowBreakpointWidth) forces the
    // side regions into overlays; sidebar intent defaults to visible.
    await pumpShell(tester, size: const Size(600, 900));

    // The single mounted `left` is the overlay copy (docked pane renders
    // nothing for the sides on narrow), and center/bottom still mount.
    expect(find.text('left'), findsOneWidget);
    expect(find.byKey(centerKey), findsOneWidget);
    expect(find.byKey(bottomKey), findsOneWidget);
  });

  testWidgets('dismissing the narrow left overlay clears sidebar intent', (
    tester,
  ) async {
    final layout = await pumpShell(tester, size: const Size(600, 900));
    // Isolate the left overlay so the scrim tap can only dismiss the sidebar
    // (default sidebarWidth 260 → scrim covers the right side of the viewport).
    await layout.setRightToolsVisible(false);
    await tester.pumpAndSettle();
    expect(layout.state.preferences.sidebarVisible, isTrue);
    expect(find.text('left'), findsOneWidget);

    await tester.tapAt(const Offset(500, 450));
    await tester.pumpAndSettle();

    expect(layout.state.preferences.sidebarVisible, isFalse);
    expect(find.text('left'), findsNothing);
  });

  testWidgets('narrow overlay toggle keeps the bottom terminal identity', (
    tester,
  ) async {
    final layout = await pumpShell(tester, size: const Size(600, 900));
    final bottomBefore = tester.element(find.byKey(bottomKey));

    await layout.setSidebarVisible(false);
    await tester.pumpAndSettle();
    await layout.setSidebarVisible(true);
    await tester.pumpAndSettle();

    expect(
      identical(tester.element(find.byKey(bottomKey)), bottomBefore),
      isTrue,
      reason: 'bottom terminal was reparented when overlay toggled on narrow',
    );
  });

  testWidgets('side panes stop before crushing the center workbench', (
    tester,
  ) async {
    final layout = await pumpShell(tester, size: const Size(1000, 900));
    await layout.setWorkspaceTerminalVisible(false);
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
