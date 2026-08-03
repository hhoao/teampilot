import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_sidebar.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';
import 'package:teampilot/utils/ui/app_keys.dart';
import 'package:teampilot/widgets/notification/notification_bell_button.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Future<void> pumpMobileHomeSidebar(WidgetTester tester) async {
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
        child: TpSidebarProvider(
          mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
          openMobile: true,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: theme,
            home: Scaffold(
              body: TpSidebar(
                collapsible: TpSidebarCollapsible.offcanvas,
                child: const HomeSidebar(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mobile home sidebar footer shows providers only', (
    tester,
  ) async {
    await pumpMobileHomeSidebar(tester);

    expect(find.byKey(AppKeys.homeWorkspaceProvidersButton), findsOneWidget);
    expect(find.byType(NotificationBellButton), findsNothing);
    expect(find.byTooltip('Settings'), findsNothing);
  });

  testWidgets(
    'mobile nav ListView ignores MediaQuery safe-area top padding',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const safeTop = 48.0;
      final theme = ThemeData(useMaterial3: true);
      await tester.pumpWidget(
        TpTheme(
          data: TpThemeData.fromColorScheme(
            theme.colorScheme,
            scale: 1.0,
          ),
          child: TpSidebarProvider(
            mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
            openMobile: true,
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: theme,
              builder: (context, child) {
                final mq = MediaQuery.of(context);
                return MediaQuery(
                  data: mq.copyWith(
                    padding: mq.padding.copyWith(top: safeTop),
                  ),
                  child: child!,
                );
              },
              home: Scaffold(
                body: TpSidebar(
                  collapsible: TpSidebarCollapsible.offcanvas,
                  child: const HomeSidebar(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final allWorkspaces = tester.getBottomLeft(find.text('All workspaces'));
      final myTeams = tester.getTopLeft(find.text('My Teams'));
      // Divider + spacing is ~20px; must not include the 48px safe-area inset.
      expect(myTeams.dy - allWorkspaces.dy, lessThan(safeTop));
    },
  );
}
