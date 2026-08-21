import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/install_job/install_cancel_policy.dart';
import 'package:teampilot/models/install_job/install_job_key.dart';
import 'package:teampilot/models/install_job/install_job_spec.dart';
import 'package:teampilot/models/progress_activity.dart';
import 'package:teampilot/services/install/install_job_registry.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/widgets/workspace_status_bar/progress_activities_status_item.dart';
import 'package:teampilot/widgets/workspace_status_bar/workspace_status_bar.dart';

class _FakeNotificationRecorder implements NotificationRecorder {
  @override
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
  }) {}
}

ProgressActivity _activity({
  String id = 'activity-1',
  String title = 'Importing files',
  String? workspaceId,
  double? fraction,
}) {
  final at = DateTime(2026, 7, 30, 12);
  return ProgressActivity(
    id: id,
    kind: ProgressActivityKind.fileTreeImport,
    title: title,
    workspaceId: workspaceId,
    phase: ProgressActivityPhase.running,
    fraction: fraction,
    createdAt: at,
    updatedAt: at,
  );
}

Widget _host({
  required ProgressActivityCubit cubit,
  InstallJobRegistry? installJobRegistry,
  required Widget child,
}) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  final body = BlocProvider<ProgressActivityCubit>.value(
    value: cubit,
    child: Scaffold(body: child),
  );
  final app = MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: ThemeData(colorScheme: scheme),
    home: TpTheme(
      data: TpThemeData.fromColorScheme(scheme, scale: 1),
      child: body,
    ),
  );
  return installJobRegistry == null
      ? app
      : RepositoryProvider<InstallJobRegistry>.value(
          value: installJobRegistry,
          child: app,
        );
}

void main() {
  testWidgets('no activities → no progress-activities-pill', (tester) async {
    final cubit = ProgressActivityCubit(
      historyRecorder: _FakeNotificationRecorder(),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: cubit,
        child: WorkspaceStatusBar(
          items: [ProgressActivitiesStatusItem(workspaceId: 'ws-1')],
        ),
      ),
    );

    expect(find.byKey(const Key('progress-activities-pill')), findsNothing);
  });

  testWidgets('single activity → shows short title and percent', (tester) async {
    final cubit = ProgressActivityCubit(
      historyRecorder: _FakeNotificationRecorder(),
    );
    addTearDown(cubit.close);
    cubit.start(_activity(fraction: 0.42, workspaceId: 'ws-1'));

    await tester.pumpWidget(
      _host(
        cubit: cubit,
        child: WorkspaceStatusBar(
          items: [ProgressActivitiesStatusItem(workspaceId: 'ws-1')],
        ),
      ),
    );

    expect(find.byKey(const Key('progress-activities-pill')), findsOneWidget);
    expect(find.text('Importing files'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
  });

  testWidgets('single indeterminate activity → shows spinner not percent', (
    tester,
  ) async {
    final cubit = ProgressActivityCubit(
      historyRecorder: _FakeNotificationRecorder(),
    );
    addTearDown(cubit.close);
    cubit.start(_activity(workspaceId: 'ws-1'));

    await tester.pumpWidget(
      _host(
        cubit: cubit,
        child: WorkspaceStatusBar(
          items: [ProgressActivitiesStatusItem(workspaceId: 'ws-1')],
        ),
      ),
    );

    expect(find.byKey(const Key('progress-activities-pill')), findsOneWidget);
    expect(find.text('Importing files'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('multiple activities → shows many-activities label', (
    tester,
  ) async {
    final cubit = ProgressActivityCubit(
      historyRecorder: _FakeNotificationRecorder(),
    );
    addTearDown(cubit.close);
    cubit.start(
      _activity(id: 'a', title: 'Import A', workspaceId: 'ws-1'),
    );
    cubit.start(
      _activity(id: 'b', title: 'Import B', workspaceId: 'ws-1'),
    );

    await tester.pumpWidget(
      _host(
        cubit: cubit,
        child: WorkspaceStatusBar(
          items: [ProgressActivitiesStatusItem(workspaceId: 'ws-1')],
        ),
      ),
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.byKey(const Key('progress-activities-pill')), findsOneWidget);
    expect(find.text(l10n.progressActivitiesMany(2)), findsOneWidget);
    expect(find.text('Import A'), findsNothing);
  });

  testWidgets('filters out activities from other workspaces', (tester) async {
    final cubit = ProgressActivityCubit(
      historyRecorder: _FakeNotificationRecorder(),
    );
    addTearDown(cubit.close);
    cubit.start(_activity(workspaceId: 'ws-other'));

    await tester.pumpWidget(
      _host(
        cubit: cubit,
        child: WorkspaceStatusBar(
          items: [ProgressActivitiesStatusItem(workspaceId: 'ws-1')],
        ),
      ),
    );

    expect(find.byKey(const Key('progress-activities-pill')), findsNothing);
  });

  testWidgets('tap single activity → opens detail dialog', (tester) async {
    final cubit = ProgressActivityCubit(
      historyRecorder: _FakeNotificationRecorder(),
    );
    addTearDown(cubit.close);
    cubit.start(_activity(workspaceId: 'ws-1'));

    await tester.pumpWidget(
      _host(
        cubit: cubit,
        child: WorkspaceStatusBar(
          items: [ProgressActivitiesStatusItem(workspaceId: 'ws-1')],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('progress-activities-pill')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Importing files'), findsWidgets);
    expect(cubit.state.activities.single.detailOpen, isTrue);
  });

  testWidgets('tap multi pill → opens popover list', (tester) async {
    final cubit = ProgressActivityCubit(
      historyRecorder: _FakeNotificationRecorder(),
    );
    addTearDown(cubit.close);
    cubit.start(
      _activity(id: 'a', title: 'Import A', workspaceId: 'ws-1'),
    );
    cubit.start(
      _activity(id: 'b', title: 'Import B', workspaceId: 'ws-1'),
    );

    await tester.pumpWidget(
      _host(
        cubit: cubit,
        child: WorkspaceStatusBar(
          items: [ProgressActivitiesStatusItem(workspaceId: 'ws-1')],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('progress-activities-pill')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Import A'), findsOneWidget);
    expect(find.text('Import B'), findsOneWidget);
  });

  testWidgets('cancel from status bar detail routes to InstallJobRegistry', (
    tester,
  ) async {
    final cubit = ProgressActivityCubit(
      historyRecorder: _FakeNotificationRecorder(),
    );
    addTearDown(cubit.close);
    final registry = InstallJobRegistry(progressCubit: cubit);
    addTearDown(registry.dispose);
    const key = InstallJobKey(
      kind: InstallJobKind.toolchain,
      target: 'git',
    );
    unawaited(
      registry.enqueue(
        InstallJobSpec<void>(
          key: key,
          title: 'Installing Git',
          cancelPolicy: InstallCancelPolicy.cooperative,
          run: (_) => Completer<void>().future,
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      _host(
        cubit: cubit,
        installJobRegistry: registry,
        child: WorkspaceStatusBar(
          items: [ProgressActivitiesStatusItem(workspaceId: null)],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('progress-activities-pill')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(
      cubit.state.activities.single.phase,
      ProgressActivityPhase.cancelling,
    );
  });
}
