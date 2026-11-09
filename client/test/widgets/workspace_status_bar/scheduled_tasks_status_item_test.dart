import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/services/automation/scheduled_task_summary.dart';
import 'package:teampilot/widgets/workspace_status_bar/scheduled_tasks_status_item.dart';
import 'package:teampilot/widgets/workspace_status_bar/workspace_status_bar.dart';

import '../../support/post_frame_test_harness.dart';

Widget _host({required AutomationCubit cubit, required Widget child}) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  return BlocProvider<AutomationCubit>.value(
    value: cubit,
    child: MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: appLocalizationsSupportedLocales,
      locale: const Locale('en'),
      theme: ThemeData(colorScheme: scheme),
      home: TpTheme(
        data: TpThemeData.fromColorScheme(scheme, scale: 1),
        child: Scaffold(body: child),
      ),
    ),
  );
}

Automation _automation({
  required String id,
  required String name,
  String workspaceId = 'ws1',
  bool enabled = true,
  int? nextRunAtMs,
}) {
  return Automation(
    id: id,
    name: name,
    action: AutomationAction.launchPrompt,
    workspaceId: workspaceId,
    isPersonal: true,
    presetId: 'preset-1',
    message: 'ping',
    preset: AutomationSchedulePreset.daily,
    hourMinute: '09:00',
    timezone: 'UTC',
    dtstartMs: 1,
    enabled: enabled,
    nextRunAtMs: nextRunAtMs,
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('collapsed pill shows count and nearest next run', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    addTearDown(setup.cubit.close);
    // Repository reads/writes use real dart:io; under testWidgets they only
    // complete inside runAsync.
    await tester.runAsync(() async {
      await setup.repo.upsert(
        _automation(
          id: 'a1',
          name: 'Morning',
          nextRunAtMs: DateTime(2026, 7, 30, 14, 30).millisecondsSinceEpoch,
        ),
      );
      await setup.repo.upsert(
        _automation(
          id: 'a2',
          name: 'Evening',
          workspaceId: 'ws2',
          nextRunAtMs: DateTime(2026, 7, 31, 9).millisecondsSinceEpoch,
        ),
      );
      await setup.repo.upsert(
        _automation(
          id: 'off',
          name: 'Disabled',
          enabled: false,
          nextRunAtMs: DateTime(2026, 7, 29).millisecondsSinceEpoch,
        ),
      );
      await setup.cubit.loadGlobal();
    });

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        child: WorkspaceStatusBar(trailingItems: [ScheduledTasksStatusItem()]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scheduled-tasks-pill')), findsOneWidget);
    expect(
      find.text(
        '2 · '
        '${formatScheduledTaskNextRun(DateTime(2026, 7, 30, 14, 30).millisecondsSinceEpoch)}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('compact pill shows the count without the next-run time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final setup = testAutomationSetup();
    addTearDown(setup.cubit.close);
    await tester.runAsync(() async {
      await setup.repo.upsert(
        _automation(
          id: 'a1',
          name: 'Morning',
          nextRunAtMs: DateTime(2026, 7, 30, 14, 30).millisecondsSinceEpoch,
        ),
      );
      await setup.repo.upsert(
        _automation(
          id: 'a2',
          name: 'Evening',
          workspaceId: 'ws2',
          nextRunAtMs: DateTime(2026, 7, 31, 9).millisecondsSinceEpoch,
        ),
      );
      await setup.repo.upsert(
        _automation(
          id: 'off',
          name: 'Disabled',
          enabled: false,
          nextRunAtMs: DateTime(2026, 7, 29).millisecondsSinceEpoch,
        ),
      );
      await setup.cubit.loadGlobal();
    });

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        child: WorkspaceStatusBar(trailingItems: [ScheduledTasksStatusItem()]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scheduled-tasks-pill')), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining(' · '), findsNothing);
  });

  testWidgets('menu lists active tasks in next-run order and fires callbacks', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    addTearDown(setup.cubit.close);
    await tester.runAsync(() async {
      await setup.repo.upsert(
        _automation(
          id: 'a2',
          name: 'Evening',
          workspaceId: 'ws2',
          nextRunAtMs: DateTime(2026, 7, 31, 9).millisecondsSinceEpoch,
        ),
      );
      await setup.repo.upsert(
        _automation(
          id: 'a1',
          name: 'Morning',
          nextRunAtMs: DateTime(2026, 7, 30, 14, 30).millisecondsSinceEpoch,
        ),
      );
      await setup.cubit.loadGlobal();
    });

    Automation? edited;
    var managed = false;

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        child: WorkspaceStatusBar(
          trailingItems: [
            ScheduledTasksStatusItem(
              onEditAutomation: (automation) => edited = automation,
              onManage: () => managed = true,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scheduled-tasks-pill')));
    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.automations.sidebarTitle), findsOneWidget);
    expect(find.text('Morning'), findsOneWidget);
    expect(find.text('Evening'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Morning')).dy,
      lessThan(tester.getTopLeft(find.text('Evening')).dy),
    );

    await tester.tap(find.text('Morning'));
    await tester.pumpAndSettle();
    expect(edited?.id, 'a1');

    await tester.tap(find.byKey(const Key('scheduled-tasks-pill')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scheduled-tasks-manage')));
    await tester.pumpAndSettle();
    expect(managed, isTrue);
  });

  testWidgets('empty state shows zero count and no-active copy', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    addTearDown(setup.cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        child: WorkspaceStatusBar(trailingItems: [ScheduledTasksStatusItem()]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scheduled-tasks-pill')));
    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.byKey(const Key('scheduled-tasks-empty-icon')), findsOneWidget);
    expect(find.text(l10n.automations.statusBarEmpty), findsOneWidget);
  });
}
