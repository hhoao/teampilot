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
import 'package:teampilot/services/install/job_log_store.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/widgets/progress_activity/progress_activity_detail_dialog.dart';

import '../../support/in_memory_filesystem.dart';

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
  String? subtitle,
  bool cancellable = false,
  bool detailOpen = false,
  double? fraction,
}) {
  final at = DateTime(2026, 7, 30, 12);
  return ProgressActivity(
    id: id,
    kind: ProgressActivityKind.fileTreeImport,
    title: title,
    subtitle: subtitle,
    phase: ProgressActivityPhase.running,
    fraction: fraction,
    cancellable: cancellable,
    detailOpen: detailOpen,
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
  final app = MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: appLocalizationsSupportedLocales,
    theme: ThemeData(colorScheme: scheme),
    home: TpTheme(
      data: TpThemeData.fromColorScheme(scheme, scale: 1),
      child: BlocProvider.value(
        value: cubit,
        child: Scaffold(body: child),
      ),
    ),
  );
  return installJobRegistry == null
      ? app
      : RepositoryProvider<InstallJobRegistry>.value(
          value: installJobRegistry,
          child: app,
        );
}

Future<void> _openDialog(
  WidgetTester tester,
  ProgressActivityCubit cubit,
) async {
  await tester.pumpWidget(
    _host(
      cubit: cubit,
      child: Builder(
        builder: (context) => TextButton(
          onPressed: () {
            showProgressActivityDetailDialog(context, activityId: 'activity-1');
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('showProgressActivityDetailDialog', () {
    testWidgets('close keeps activity and clears detailOpen', (tester) async {
      final cubit = ProgressActivityCubit(
        historyRecorder: _FakeNotificationRecorder(),
      );
      addTearDown(cubit.close);
      cubit.start(_activity(detailOpen: true));

      await _openDialog(tester, cubit);

      expect(find.text('Importing files'), findsOneWidget);
      expect(cubit.state.activities, hasLength(1));
      expect(cubit.state.activities.single.detailOpen, isTrue);

      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(Dialog), findsNothing);
      expect(cubit.state.activities, hasLength(1));
      expect(cubit.state.activities.single.detailOpen, isFalse);
    });

    testWidgets('cancel calls requestCancel on cubit', (tester) async {
      var cancelHookInvoked = false;
      final cubit = ProgressActivityCubit(
        historyRecorder: _FakeNotificationRecorder(),
      );
      addTearDown(cubit.close);
      cubit.start(
        _activity(cancellable: true, detailOpen: true),
        onCancelRequested: () => cancelHookInvoked = true,
      );

      await _openDialog(tester, cubit);

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(cancelHookInvoked, isTrue);
      expect(
        cubit.state.activities.single.phase,
        ProgressActivityPhase.cancelling,
      );
    });

    testWidgets('cancel with jobKey routes to InstallJobRegistry', (
      tester,
    ) async {
      final cubit = ProgressActivityCubit(
        historyRecorder: _FakeNotificationRecorder(),
      );
      addTearDown(cubit.close);
      final registry = InstallJobRegistry(progressCubit: cubit);
      addTearDown(registry.dispose);
      const key = InstallJobKey(kind: InstallJobKind.toolchain, target: 'git');
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

      cubit.setDetailOpen(key.activityId, true);
      await tester.pumpWidget(
        _host(
          cubit: cubit,
          installJobRegistry: registry,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showProgressActivityDetailDialog(
                  context,
                  activityId: key.activityId,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(
        cubit.state.activities.single.phase,
        ProgressActivityPhase.cancelling,
      );
    });

    testWidgets('auto-pops when activity completes', (tester) async {
      final cubit = ProgressActivityCubit(
        historyRecorder: _FakeNotificationRecorder(),
      );
      addTearDown(cubit.close);
      cubit.start(_activity(detailOpen: true));

      await _openDialog(tester, cubit);
      expect(find.byType(Dialog), findsOneWidget);

      cubit.complete('activity-1', outcome: ProgressActivityPhase.succeeded);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(Dialog), findsNothing);
      expect(cubit.state.activities, isEmpty);
    });

    testWidgets('shows the view log action only when logToken is set', (
      tester,
    ) async {
      final cubit = ProgressActivityCubit(
        historyRecorder: _FakeNotificationRecorder(),
      );
      addTearDown(cubit.close);
      final activity = ProgressActivity(
        id: 'a1',
        kind: ProgressActivityKind.cliProvision,
        title: 'Install Claude',
        phase: ProgressActivityPhase.running,
        logToken: 'tok-1',
        createdAt: DateTime(2026, 7, 30),
        updatedAt: DateTime(2026, 7, 30),
      );
      cubit.start(activity);
      await tester.pumpWidget(_host(cubit: cubit, child: const SizedBox()));
      unawaited(
        showProgressActivityDetailDialog(
          tester.element(find.byType(Scaffold)),
          activityId: 'a1',
        ),
      );
      // The detail dialog shows an indeterminate progress bar while the
      // activity is running, so `pumpAndSettle` would never settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('View log'), findsOneWidget);
    });

    testWidgets('keeps the log dialog open when the activity completes', (
      tester,
    ) async {
      final cubit = ProgressActivityCubit(
        historyRecorder: _FakeNotificationRecorder(),
      );
      addTearDown(cubit.close);
      final store = JobLogStore(appDataRoot: '/tp', fs: InMemoryFilesystem());
      final registry = InstallJobRegistry(progressCubit: cubit, logs: store);
      addTearDown(registry.dispose);
      const key = InstallJobKey(
        kind: InstallJobKind.cliExecutable,
        target: 'claude',
      );
      final writer = store.begin(key: key, title: 'Install Claude');
      writer.line('npm install claude -g');
      final token = store.tokenFor(key);
      final at = DateTime(2026, 7, 30, 12);
      cubit.start(
        ProgressActivity(
          id: 'activity-1',
          kind: ProgressActivityKind.cliProvision,
          title: 'Install Claude',
          phase: ProgressActivityPhase.running,
          detailOpen: true,
          logToken: token,
          createdAt: at,
          updatedAt: at,
        ),
      );

      await tester.pumpWidget(
        _host(
          cubit: cubit,
          installJobRegistry: registry,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showProgressActivityDetailDialog(
                  context,
                  activityId: 'activity-1',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('View log'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('npm install claude -g'), findsOneWidget);

      cubit.complete('activity-1', outcome: ProgressActivityPhase.succeeded);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The log dialog is the route above the detail dialog: it must survive
      // the completion, while only the detail dialog underneath goes away.
      expect(find.textContaining('npm install claude -g'), findsOneWidget);
      expect(find.text('View log'), findsNothing);
      expect(find.byType(Dialog), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);

      await writer.close();
      expect(cubit.state.activities, isEmpty);
    });
  });
}
