import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/notification_cubit.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/pages/workspace_ide/mobile_workspace_drawer_host.dart';
import 'package:teampilot/pages/workspace_ide/workspace_ide_shell.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  const centerKey = ValueKey('center-smoke');
  const rightKey = ValueKey('right-smoke');

  Future<LayoutCubit> pumpShell(
    WidgetTester tester, {
    Size size = const Size(1400, 900),
    TpThemeData? themeData,
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
        data: themeData ?? TpThemeData.fromColorScheme(scheme, scale: 1.0),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<LayoutCubit>.value(value: layout),
            BlocProvider(create: (_) => NotificationCubit()),
            BlocProvider(
              create: (context) => ProgressActivityCubit(
                historyRecorder: context.read<NotificationCubit>(),
              ),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: TpSidebarProvider(
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
    'narrow first paint suppresses left without clearing prefs',
    (tester) async {
      final layout = await pumpShell(tester, size: const Size(600, 900));
      expect(find.text('left'), findsNothing);
      expect(layout.state.preferences.sidebarVisible, isTrue);
      expect(layout.state.narrowLeftSuppressed, isTrue);
      expect(find.byKey(centerKey), findsOneWidget);
    },
  );

  testWidgets(
    'narrow first frame never docks left before settle',
    (tester) async {
      final layout = LayoutCubit();
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(layout.close);

      final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
      await tester.pumpWidget(
        TpTheme(
          data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<LayoutCubit>.value(value: layout),
              BlocProvider(create: (_) => NotificationCubit()),
              BlocProvider(
                create: (context) => ProgressActivityCubit(
                  historyRecorder: context.read<NotificationCubit>(),
                ),
              ),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: TpSidebarProvider(
                mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
                child: const Scaffold(
                  body: WorkspaceIdeShell(
                    left: SizedBox(child: Text('left')),
                    center: ColoredBox(
                      key: centerKey,
                      color: Colors.transparent,
                    ),
                    right: ColoredBox(
                      key: rightKey,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // Single frame only — must not dock left while waiting for PaneSizeReporter.
      expect(find.text('left'), findsNothing);
      expect(layout.state.narrowLeftSuppressed, isTrue);
      expect(layout.state.preferences.sidebarVisible, isTrue);
      expect(find.byKey(centerKey), findsOneWidget);
    },
  );

  testWidgets('narrow chat drawer opens after clear suppress', (tester) async {
    final layout = await pumpShell(tester, size: const Size(600, 900));
    expect(find.text('left'), findsNothing);

    await layout.setRightToolsVisible(false);
    layout.clearNarrowLeftSuppressed();
    await layout.setSidebarVisible(true);
    await tester.pumpAndSettle();

    expect(find.text('left'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MobileWorkspaceDrawerHost),
        matching: find.text('left'),
      ),
      findsOneWidget,
    );
    expect(layout.state.preferences.sidebarVisible, isTrue);
    expect(layout.state.narrowLeftSuppressed, isFalse);
  });

  testWidgets('dismissing narrow drawer clears sidebar intent', (
    tester,
  ) async {
    final layout = await pumpShell(tester, size: const Size(600, 900));
    await layout.setRightToolsVisible(false);
    layout.clearNarrowLeftSuppressed();
    await layout.setSidebarVisible(true);
    await tester.pumpAndSettle();
    expect(find.text('left'), findsOneWidget);

    await tester.tapAt(const Offset(500, 450));
    await tester.pumpAndSettle();

    expect(layout.state.preferences.sidebarVisible, isFalse);
    expect(layout.state.preferences.rightToolsVisible, isFalse);
    expect(layout.state.narrowLeftSuppressed, isFalse);
    expect(find.text('left'), findsNothing);
  });

  testWidgets('narrow tools drawer uses theme drawer fraction width', (
    tester,
  ) async {
    const viewportWidth = 600.0;
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    final themeData = TpThemeData.fromColorScheme(
      scheme,
      scale: 1.0,
      sidebar: const TpSidebarTheme(widthMobileFraction: 0.75),
    );
    final expectedWidth = themeData.sidebarTheme.resolveMobileDrawerWidth(
      viewportWidth,
    );
    expect(expectedWidth, closeTo(450, 0.5));
    expect(expectedWidth, isNot(LayoutPreferences.defaultRightToolsWidth));

    await pumpShell(
      tester,
      size: const Size(viewportWidth, 900),
      themeData: themeData,
    );
    await tester.pumpAndSettle();

    final drawerPanel = find.ancestor(
      of: find.byKey(rightKey),
      matching: find.byWidgetPredicate(
        (widget) => widget is Positioned && widget.left == 0,
      ),
    );
    expect(drawerPanel, findsOneWidget);
    expect(
      tester.getSize(drawerPanel).width,
      closeTo(expectedWidth, 0.5),
    );
    expect(find.byType(MobileWorkspaceDrawerHost), findsOneWidget);
  });

  testWidgets(
    'narrow tools drawer still works while left is suppressed',
    (tester) async {
      final layout = await pumpShell(tester, size: const Size(600, 900));
      expect(find.text('left'), findsNothing);
      expect(layout.state.narrowLeftSuppressed, isTrue);

      final rightBefore = layout.state.preferences.rightToolsVisible;
      await layout.setRightToolsVisible(true);
      await tester.pumpAndSettle();

      expect(find.byKey(rightKey), findsOneWidget);
      expect(find.text('left'), findsNothing);
      expect(layout.state.narrowLeftSuppressed, isTrue);
      expect(layout.state.preferences.rightToolsVisible, isTrue);
      expect(rightBefore, isTrue);
    },
  );

  testWidgets(
    'wide to narrow to wide with sidebarVisible docks left again',
    (tester) async {
      final layout = await pumpShell(tester, size: const Size(1400, 900));
      expect(layout.state.preferences.sidebarVisible, isTrue);
      expect(find.text('left'), findsOneWidget);

      tester.view.physicalSize = const Size(600, 900);
      await tester.pumpAndSettle();
      expect(find.text('left'), findsNothing);
      expect(layout.state.preferences.sidebarVisible, isTrue);
      expect(layout.state.narrowLeftSuppressed, isTrue);

      tester.view.physicalSize = const Size(1400, 900);
      await tester.pumpAndSettle();
      expect(find.text('left'), findsOneWidget);
      expect(layout.state.preferences.sidebarVisible, isTrue);
      expect(layout.state.narrowLeftSuppressed, isFalse);
    },
  );

  testWidgets('leave narrow and re-enter suppresses left again', (
    tester,
  ) async {
    final layout = await pumpShell(tester, size: const Size(600, 900));
    expect(layout.state.narrowLeftSuppressed, isTrue);
    expect(find.text('left'), findsNothing);

    await layout.setRightToolsVisible(false);
    layout.clearNarrowLeftSuppressed();
    await layout.setSidebarVisible(true);
    await tester.pumpAndSettle();
    expect(find.text('left'), findsOneWidget);

    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    expect(layout.state.narrowLeftSuppressed, isFalse);
    expect(find.text('left'), findsOneWidget);

    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();
    expect(find.text('left'), findsNothing);
    expect(layout.state.narrowLeftSuppressed, isTrue);
    expect(layout.state.preferences.sidebarVisible, isTrue);
  });

  testWidgets('narrow drawer toggle keeps the center workbench identity', (
    tester,
  ) async {
    final layout = await pumpShell(tester, size: const Size(600, 900));
    final centerBefore = tester.element(find.byKey(centerKey));

    await layout.setRightToolsVisible(false);
    layout.clearNarrowLeftSuppressed();
    await layout.setSidebarVisible(true);
    await tester.pumpAndSettle();
    await layout.setSidebarVisible(false);
    await tester.pumpAndSettle();

    expect(
      identical(tester.element(find.byKey(centerKey)), centerBefore),
      isTrue,
      reason: 'center was reparented when drawer toggled',
    );
  });

  testWidgets('setSidebarVisible false on narrow closes drawer', (
    tester,
  ) async {
    final layout = await pumpShell(tester, size: const Size(600, 900));
    await layout.setRightToolsVisible(false);
    layout.clearNarrowLeftSuppressed();
    await layout.setSidebarVisible(true);
    await tester.pumpAndSettle();
    expect(find.text('left'), findsOneWidget);

    await layout.setSidebarVisible(false);
    await tester.pumpAndSettle();

    expect(find.text('left'), findsNothing);
    expect(find.byType(MobileWorkspaceDrawerHost), findsOneWidget);
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
