import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/router/app_router.dart';

import '../support/desktop_app_harness.dart';
import '../support/post_frame_test_harness.dart';

void main() {
  setUpAll(setUpDesktopAppHarness);
  tearDownAll(tearDownDesktopAppHarness);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setUpTestAppStorage();
    resetAppRouterLocationForWidgetTests();
  });

  tearDown(() {
    tearDownTestAppStorage();
    resetAppRouterLocationForWidgetTests();
  });

  Future<void> pumpNarrowHubRoute(
    WidgetTester tester, {
    required String route,
    double width = 400,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final teamCubit = await createTeamCubitInTest(tester);
    addTearDown(teamCubit.close);

    final sessionCubit =
        (await tester.runAsync(testSessionPreferencesCubit))!;
    final providerCubit =
        (await tester.runAsync(() async {
          final dir = await Directory.systemTemp.createTemp('providers_widget_');
          return AppProviderCubit(
            repository: AppProviderRepository(basePath: dir.path),
          );
        }))!;

    appRouter.go(route);
    await tester.pumpWidget(
      buildTestApp(
        teamCubit: teamCubit,
        sessionPreferencesCubit: sessionCubit,
        appProviderCubit: providerCubit,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('narrow hub root shows trigger and Home nav in drawer', (
    tester,
  ) async {
    await pumpNarrowHubRoute(tester, route: '/providers');

    expect(find.byType(TpSidebarTrigger), findsOneWidget);
    expect(find.text('Automations'), findsNothing);

    await tester.tap(find.byType(TpSidebarTrigger));
    await tester.pumpAndSettle();

    expect(find.text('Automations'), findsOneWidget);
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('MCP'), findsOneWidget);
  });

  testWidgets('hub detail hides trigger, shows back, disables edge open', (
    tester,
  ) async {
    await pumpNarrowHubRoute(tester, route: '/config/layout', width: 800);

    expect(find.byType(TpSidebarTrigger), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byType(TpMobileLeading), findsOneWidget);

    final backRect = tester.getRect(find.byType(BackButton));
    expect(backRect.left, greaterThanOrEqualTo(TpMobileChrome.leadingInset));
    expect(find.text('Automations'), findsNothing);

    final gesture = await tester.startGesture(const Offset(2, 400));
    await gesture.moveBy(const Offset(200, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Automations'), findsNothing);
  });
}
