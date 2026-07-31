import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/notification_cubit.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_title_bar.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';
import 'package:teampilot/utils/ui/app_keys.dart';
import 'package:teampilot/widgets/notification/notification_bell_button.dart';

import '../../support/post_frame_test_harness.dart';

Widget _wrapTitleBar({
  required ChatCubit chatCubit,
  required Widget child,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<ChatCubit>.value(value: chatCubit),
      BlocProvider(create: (_) => NotificationCubit()),
      BlocProvider(
        create: (context) => ProgressActivityCubit(
          historyRecorder: context.read<NotificationCubit>(),
        ),
      ),
      BlocProvider(create: (_) => LayoutCubit()),
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

  testWidgets('mobile title bar hides trailing tools with workspace active', (
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
    expect(find.byType(NotificationBellButton), findsNothing);
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });
}
