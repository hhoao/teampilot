import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/notification_cubit.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_sidebar.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_title_bar.dart';
import 'package:teampilot/pages/workspace_ide/mobile_slide_panel_host.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/post_frame_test_harness.dart';

class _NarrowHomeSlideBody extends StatelessWidget {
  const _NarrowHomeSlideBody();

  @override
  Widget build(BuildContext context) {
    final scope = TpSidebarScope.maybeOf(context);
    final width = TpTheme.of(context).sidebarTheme.resolveMobileDrawerWidth(
      MediaQuery.sizeOf(context).width,
    );
    return MobileSlidePanelHost(
      open: scope?.openMobile ?? false,
      width: width,
      onDismiss: () => scope?.setOpenMobile(false),
      scrimKey: AppKeys.mobileHomeSidebarScrim,
      panel: HomeSidebar(
        onSelectLibraryView: (_) {
          TpSidebarScope.maybeOf(context)?.setOpenMobile(false);
        },
      ),
      child: const ColoredBox(color: Colors.transparent),
    );
  }
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

  Future<void> pumpHarness(
    WidgetTester tester, {
    String? activeTabKey,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      TpTheme(
        data: TpThemeData.fromColorScheme(
          theme.colorScheme,
          scale: 1.0,
        ),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ChatCubit>.value(value: chatCubit),
            BlocProvider(create: (_) => NotificationCubit()),
            BlocProvider(
              create: (context) => ProgressActivityCubit(
                historyRecorder: context.read<NotificationCubit>(),
              ),
            ),
          ],
          child: TpSidebarProvider(
            mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: theme,
              home: Scaffold(
                body: Column(
                  children: [
                    HomeTitleBar(
                      activeTabKey: activeTabKey,
                      tabs: activeTabKey == null
                          ? const []
                          : const [
                              HomeWorkspaceTab(id: 'ws-a', name: 'Solo'),
                            ],
                    ),
                    const Expanded(child: _NarrowHomeSlideBody()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('narrow home hides sidebar until trigger opens panel', (
    tester,
  ) async {
    await pumpHarness(tester);

    expect(find.text('Automations'), findsNothing);
    expect(find.byType(TpSidebarTrigger), findsOneWidget);
    expect(find.byType(MobileSlidePanelHost), findsOneWidget);

    await tester.tap(find.byType(TpSidebarTrigger));
    await tester.pumpAndSettle();

    expect(find.text('Automations'), findsOneWidget);
  });

  testWidgets('narrow home closes panel after nav selection', (tester) async {
    await pumpHarness(tester);

    await tester.tap(find.byType(TpSidebarTrigger));
    await tester.pumpAndSettle();
    expect(find.text('Automations'), findsOneWidget);

    await tester.tap(find.text('Recent'));
    await tester.pumpAndSettle();

    expect(find.text('Automations'), findsNothing);
  });

  testWidgets('narrow home closes panel on scrim tap', (tester) async {
    await pumpHarness(tester);

    await tester.tap(find.byType(TpSidebarTrigger));
    await tester.pumpAndSettle();
    expect(find.text('Automations'), findsOneWidget);

    // Panel is left ~75% width; tap the uncovered right edge of the scrim.
    await tester.tapAt(const Offset(360, 400));
    await tester.pumpAndSettle();

    expect(find.text('Automations'), findsNothing);
  });

  test('home sidebar trigger on all mobile tabs', () {
    expect(
      homeSidebarTriggerVisible(isMobile: true, activeTabKey: 'ws-a'),
      isTrue,
    );
    expect(
      homeSidebarTriggerVisible(isMobile: true, activeTabKey: null),
      isTrue,
    );
    expect(
      homeSidebarTriggerVisible(isMobile: false, activeTabKey: null),
      isFalse,
    );
  });
}
