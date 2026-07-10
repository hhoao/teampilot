import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/pages/workspace_ide/workspace_ide_shell.dart';

void main() {
  const bottomKey = ValueKey('workspace-terminal-smoke');
  const centerKey = ValueKey('center-smoke');
  const rightKey = ValueKey('right-smoke');

  Future<LayoutCubit> pumpShell(WidgetTester tester) async {
    final layout = LayoutCubit();
    // Wide viewport so the policy docks all intent-visible panes.
    tester.view.physicalSize = const Size(1400, 900);
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
}
