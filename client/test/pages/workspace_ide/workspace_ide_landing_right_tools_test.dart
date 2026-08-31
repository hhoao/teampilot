import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/pages/workspace_ide/workspace_ide_shell.dart';

/// Mirrors [RightToolsPanel]'s early return on `!preferences.rightToolsVisible`
/// so we can assert the Task 4 `effectiveRight` copyWith without full panel deps.
class _RightToolsVisibilityProbe extends StatelessWidget {
  const _RightToolsVisibilityProbe({required this.preferences});

  final LayoutPreferences preferences;

  @override
  Widget build(BuildContext context) {
    if (!preferences.rightToolsVisible) {
      return const SizedBox.shrink();
    }
    return const ColoredBox(
      key: ValueKey('probe-panel-content'),
      color: Colors.transparent,
    );
  }
}

void main() {
  const centerKey = ValueKey('landing-right-center');
  const rightKey = ValueKey('landing-right-pane');

  Future<void> pumpShell(
    WidgetTester tester, {
    required LayoutCubit layout,
    required bool composeLanding,
    Size size = const Size(1400, 900),
    Widget? right,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<LayoutCubit>.value(
          value: layout,
          child: Scaffold(
            body: WorkspaceIdeShell(
              composeLanding: composeLanding,
              left: const SizedBox(child: Text('left')),
              center: const ColoredBox(
                key: centerKey,
                color: Colors.transparent,
              ),
              right:
                  right ??
                  const ColoredBox(key: rightKey, color: Colors.transparent),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('compose landing hides right pane even when prefs visible', (
    tester,
  ) async {
    final layout = LayoutCubit();
    addTearDown(layout.close);
    await layout.setRightToolsVisible(true);
    expect(layout.state.preferences.rightToolsVisible, isTrue);

    await pumpShell(tester, layout: layout, composeLanding: true);

    expect(find.byKey(rightKey).hitTestable(), findsNothing);
    expect(layout.state.preferences.rightToolsVisible, isTrue);
    expect(layout.state.landingRightToolsOverride, isNull);
  });

  testWidgets('landing override reveals right pane without flipping prefs', (
    tester,
  ) async {
    final layout = LayoutCubit();
    addTearDown(layout.close);
    expect(layout.state.preferences.rightToolsVisible, isFalse);

    await pumpShell(tester, layout: layout, composeLanding: true);
    expect(find.byKey(rightKey).hitTestable(), findsNothing);

    layout.setLandingRightToolsOverride(true);
    await tester.pumpAndSettle();

    expect(find.byKey(rightKey).hitTestable(), findsOneWidget);
    expect(layout.state.preferences.rightToolsVisible, isFalse);
    expect(layout.state.landingRightToolsOverride, isTrue);
  });

  testWidgets('leaving compose clears override and restores prefs dock', (
    tester,
  ) async {
    final layout = LayoutCubit();
    addTearDown(layout.close);
    expect(layout.state.preferences.rightToolsVisible, isFalse);

    await pumpShell(tester, layout: layout, composeLanding: true);
    layout.setLandingRightToolsOverride(true);
    await tester.pumpAndSettle();
    expect(find.byKey(rightKey).hitTestable(), findsOneWidget);

    await pumpShell(tester, layout: layout, composeLanding: false);

    expect(layout.state.landingRightToolsOverride, isNull);
    expect(layout.state.preferences.rightToolsVisible, isFalse);
    expect(find.byKey(rightKey).hitTestable(), findsNothing);
  });

  testWidgets(
    'prefs hidden + landing override still docks and keeps panel content',
    (tester) async {
      final layout = LayoutCubit();
      addTearDown(layout.close);
      await layout.setRightToolsVisible(false);
      layout.setLandingRightToolsOverride(true);

      // Same effectiveRight formula as `_WorkspaceRightToolsPane`.
      final panelPrefs = layout.state.preferences.copyWith(
        rightToolsVisible: layout.state.landingRightToolsOverride ?? false,
      );
      expect(panelPrefs.rightToolsVisible, isTrue);

      // Raw prefs (false) would shrink panel content — the copyWith gate.
      await tester.pumpWidget(
        MaterialApp(
          home: _RightToolsVisibilityProbe(
            preferences: layout.state.preferences,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('probe-panel-content')), findsNothing);

      await pumpShell(
        tester,
        layout: layout,
        composeLanding: true,
        right: _RightToolsVisibilityProbe(preferences: panelPrefs),
      );

      expect(
        find.byKey(const ValueKey('probe-panel-content')).hitTestable(),
        findsOneWidget,
      );
    },
  );
}
