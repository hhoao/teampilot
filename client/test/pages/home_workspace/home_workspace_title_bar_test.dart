import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/notification_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_title_bar.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';
import 'package:teampilot/utils/ui/app_keys.dart';
import 'package:teampilot/widgets/notification/notification_bell_button.dart';

import '../../support/post_frame_test_harness.dart';

Widget _wrapTitleBar({
  required ChatCubit chatCubit,
  WorkbenchCubit? workbenchCubit,
  LayoutCubit? layoutCubit,
  required Widget child,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<ChatCubit>.value(value: chatCubit),
      if (workbenchCubit != null)
        BlocProvider<WorkbenchCubit>.value(value: workbenchCubit)
      else
        BlocProvider(create: (_) => WorkbenchCubit()),
      BlocProvider(create: (_) => NotificationCubit()),
      BlocProvider(
        create: (context) => ProgressActivityCubit(
          historyRecorder: context.read<NotificationCubit>(),
        ),
      ),
      if (layoutCubit != null)
        BlocProvider<LayoutCubit>.value(value: layoutCubit)
      else
        BlocProvider(create: (_) => LayoutCubit()),
      BlocProvider(create: (_) => ShortcutCubit()),
    ],
    child: child,
  );
}

void main() {
  late ChatCubit chatCubit;

  setUp(() {
    setUpTestAppStorage();
    chatCubit = testChatCubit(executableResolver: () => 'claude');
  });
  tearDown(() async {
    if (!chatCubit.isClosed) {
      await chatCubit.close();
    }
    tearDownTestAppStorage();
  });

  testWidgets('title bar renders workspace tabs', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _wrapTitleBar(
          chatCubit: chatCubit,
          child: const HomeTitleBar(
            tabs: [
              HomeWorkspaceTab(id: 'ws-a', name: 'Solo'),
              HomeWorkspaceTab(id: 'ws-b', name: 'Shared'),
            ],
            activeTabKey: 'ws-a',
          ),
        ),
      ),
    );

    expect(find.text('Solo'), findsOneWidget);
    expect(find.text('Shared'), findsOneWidget);
    expect(find.byType(HomeTitleBar), findsOneWidget);
    expect(find.byType(WorkspaceShellPaneVisibilityToggles), findsOneWidget);
    expect(find.byKey(AppKeys.sidebarVisibilityButton), findsOneWidget);
    expect(find.byKey(AppKeys.rightToolsVisibilityButton), findsOneWidget);
  });

  testWidgets('pane visibility toggles hidden on home view', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _wrapTitleBar(
          chatCubit: chatCubit,
          child: const HomeTitleBar(
            tabs: [HomeWorkspaceTab(id: 'ws-a', name: 'Solo')],
            activeTabKey: null,
          ),
        ),
      ),
    );

    expect(find.byType(WorkspaceShellPaneVisibilityToggles), findsNothing);
  });

  testWidgets('title bar content clears top view padding', (tester) async {
    const statusTop = 48.0;
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: statusTop);
    tester.view.viewPadding = const FakeViewPadding(top: statusTop);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _wrapTitleBar(
          chatCubit: chatCubit,
          child: const Scaffold(
            body: Column(
              children: [
                HomeTitleBar(
                  tabs: [HomeWorkspaceTab(id: 'ws-a', name: 'Default')],
                  activeTabKey: 'ws-a',
                ),
                Expanded(child: SizedBox.expand()),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Default'), findsOneWidget);
    final tabTop = tester.getTopLeft(find.text('Default')).dy;
    expect(tabTop, greaterThanOrEqualTo(statusTop));
    expect(
      tester.getSize(find.byType(HomeTitleBar)).height,
      closeTo(kHomeTitleBarHeight + statusTop, 0.5),
    );
  });

  testWidgets('title bar does not overflow at phone width with workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      TpTheme(
        data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
        child: _wrapTitleBar(
          chatCubit: chatCubit,
          child: TpSidebarProvider(
            mobileBreakpoint: 900,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: theme,
              home: const Scaffold(
                body: HomeTitleBar(
                  tabs: [
                    HomeWorkspaceTab(id: 'ws-a', name: 'Solo Workspace'),
                  ],
                  activeTabKey: 'ws-a',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(HomeTitleBar), findsOneWidget);
  });

  testWidgets('mobile title bar pins bell and settings on the right', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      TpTheme(
        data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
        child: _wrapTitleBar(
          chatCubit: chatCubit,
          child: TpSidebarProvider(
            mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: theme,
              home: const Scaffold(
                body: HomeTitleBar(
                  tabs: [HomeWorkspaceTab(id: 'ws-a', name: 'Solo')],
                  activeTabKey: 'ws-a',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(WorkspaceShellPaneVisibilityToggles), findsNothing);
    expect(find.byType(NotificationBellButton), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byIcon(Icons.menu_open), findsOneWidget);
  });

  testWidgets(
    'mobile drawer uses active workspace key when chat scope is stale',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final workbench = WorkbenchCubit()..enterLanding('ws-a');
      final layout = LayoutCubit();
      addTearDown(workbench.close);
      addTearDown(layout.close);
      chatCubit.setActiveWorkspace('ws-b');
      await layout.setSidebarVisible(false);

      final theme = ThemeData(useMaterial3: true);
      await tester.pumpWidget(
        TpTheme(
          data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
          child: _wrapTitleBar(
            chatCubit: chatCubit,
            workbenchCubit: workbench,
            layoutCubit: layout,
            child: TpSidebarProvider(
              mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: theme,
                home: const Scaffold(
                  body: HomeTitleBar(
                    tabs: [HomeWorkspaceTab(id: 'ws-a', name: 'Solo')],
                    activeTabKey: 'ws-a',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(layout.state.landingRightToolsOverride, isFalse);
      expect(layout.state.preferences.sidebarVisible, isTrue);
      expect(layout.state.preferences.rightToolsVisible, isFalse);
    },
  );

  testWidgets(
    'mobile workspace hamburger shows selected menu_open when drawer open',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final theme = ThemeData(useMaterial3: true);
      late LayoutCubit layout;
      await tester.pumpWidget(
        TpTheme(
          data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
          child: _wrapTitleBar(
            chatCubit: chatCubit,
            child: Builder(
              builder: (context) {
                layout = context.read<LayoutCubit>();
                return TpSidebarProvider(
                  mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
                  child: MaterialApp(
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    theme: theme,
                    home: const Scaffold(
                      body: HomeTitleBar(
                        tabs: [HomeWorkspaceTab(id: 'ws-a', name: 'Solo')],
                        activeTabKey: 'ws-a',
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      layout.openMobileWorkspaceDrawer();
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.menu_open), findsOneWidget);
      final button = tester.widget<TpIconButton>(
        find.ancestor(
          of: find.byIcon(Icons.menu_open),
          matching: find.byType(TpIconButton),
        ),
      );
      expect(button.selected, isTrue);
    },
  );

  testWidgets(
    'mobile home hamburger shows selected menu_open when sidebar open',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final theme = ThemeData(useMaterial3: true);
      await tester.pumpWidget(
        TpTheme(
          data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
          child: _wrapTitleBar(
            chatCubit: chatCubit,
            child: TpSidebarProvider(
              mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: theme,
                home: const Scaffold(
                  body: HomeTitleBar(
                    tabs: [HomeWorkspaceTab(id: 'ws-a', name: 'Solo')],
                    activeTabKey: null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scopeContext = tester.element(find.byType(HomeTitleBar));
      TpSidebarScope.of(scopeContext).setOpenMobile(true);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.menu_open), findsOneWidget);
      final button = tester.widget<TpIconButton>(
        find.ancestor(
          of: find.byIcon(Icons.menu_open),
          matching: find.byType(TpIconButton),
        ),
      );
      expect(button.selected, isTrue);
    },
  );

  testWidgets('mobile drawer trigger matches title-bar tab chip height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      TpTheme(
        data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
        child: _wrapTitleBar(
          chatCubit: chatCubit,
          child: TpSidebarProvider(
            mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: theme,
              home: const Scaffold(
                body: HomeTitleBar(
                  tabs: [HomeWorkspaceTab(id: 'ws-a', name: 'Solo')],
                  activeTabKey: 'ws-a',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Default prefs treat the workspace drawer as open → menu_open.
    final menuButton = find.ancestor(
      of: find.byIcon(Icons.menu_open),
      matching: find.byType(TpIconButton),
    );
    expect(menuButton, findsOneWidget);
    final expected = homeTitleBarControlSize(tester.element(menuButton));
    expect(tester.getSize(menuButton), Size(expected, expected));
  });

  testWidgets('mobile home drawer trigger matches title-bar tab chip height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      TpTheme(
        data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
        child: _wrapTitleBar(
          chatCubit: chatCubit,
          child: TpSidebarProvider(
            mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: theme,
              home: const Scaffold(
                body: HomeTitleBar(
                  tabs: [HomeWorkspaceTab(id: 'ws-a', name: 'Solo')],
                  activeTabKey: null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final menuButton = find.ancestor(
      of: find.byIcon(Icons.menu),
      matching: find.byType(TpIconButton),
    );
    expect(menuButton, findsOneWidget);
    final expected = homeTitleBarControlSize(tester.element(menuButton));
    expect(tester.getSize(menuButton), Size(expected, expected));
  });

  testWidgets('tab context menu offers Close All and fires onCloseAllTabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var closeAllRequested = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _wrapTitleBar(
          chatCubit: chatCubit,
          child: HomeTitleBar(
            tabs: const [
              HomeWorkspaceTab(id: 'ws-a', name: 'Solo'),
              HomeWorkspaceTab(id: 'ws-b', name: 'Shared'),
            ],
            activeTabKey: 'ws-a',
            onCloseTab: (_) {},
            onCloseAllTabs: () => closeAllRequested = true,
          ),
        ),
      ),
    );

    // Right-click a tab chip to open its context menu.
    await tester.tap(find.text('Solo'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Close All'), findsOneWidget);

    await tester.tap(find.text('Close All'));
    await tester.pumpAndSettle();

    expect(closeAllRequested, isTrue);
  });
}
