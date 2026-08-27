import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/notification_cubit.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/workspace_ide/mobile_workspace_drawer_host.dart';
import 'package:teampilot/pages/workspace_ide/workspace_ide_shell.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Future<void> pumpUntilIdle(WidgetTester tester) => pumpUntil(
    tester,
    () => !tester.binding.hasScheduledFrame,
    description: 'workspace IDE shell manage-drawer frames',
  );

  const manageKey = ValueKey('manage-overlay');

  Future<LayoutCubit> pumpShell(
    WidgetTester tester, {
    required VoidCallback onOpenWorkspaceManagement,
  }) async {
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
              child: Scaffold(
                body: WorkspaceIdeShell(
                  left: const SizedBox(child: Text('left')),
                  center: const ColoredBox(color: Colors.transparent),
                  right: const ColoredBox(color: Colors.transparent),
                  showManage: true,
                  manageOverlay: const ColoredBox(
                    key: manageKey,
                    color: Colors.red,
                  ),
                  onOpenWorkspaceManagement: onOpenWorkspaceManagement,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await pumpUntilIdle(tester);
    return layout;
  }

  testWidgets(
    'narrow manage overlay still lets the chat drawer open and receive taps',
    (tester) async {
      var manageTaps = 0;
      final layout = await pumpShell(
        tester,
        onOpenWorkspaceManagement: () => manageTaps++,
      );

      expect(find.byKey(manageKey), findsOneWidget);
      expect(find.text('left'), findsNothing);

      await layout.setRightToolsVisible(false);
      layout.clearNarrowLeftSuppressed();
      await layout.setSidebarVisible(true);
      await pumpUntilIdle(tester);

      expect(find.text('left'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MobileWorkspaceDrawerHost),
          matching: find.text('Workspace management'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Workspace management'));
      await tester.pump();
      expect(manageTaps, 1);
    },
  );
}
