import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/progress_activity.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/widgets/progress_activity/progress_activity_detail_dialog.dart';

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
  required Widget child,
}) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  return BlocProvider.value(
    value: cubit,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(colorScheme: scheme),
      home: TpTheme(
        data: TpThemeData.fromColorScheme(scheme, scale: 1),
        child: Scaffold(body: child),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester, ProgressActivityCubit cubit) async {
  await tester.pumpWidget(
    _host(
      cubit: cubit,
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

    testWidgets('auto-pops when activity completes', (tester) async {
      final cubit = ProgressActivityCubit(
        historyRecorder: _FakeNotificationRecorder(),
      );
      addTearDown(cubit.close);
      cubit.start(_activity(detailOpen: true));

      await _openDialog(tester, cubit);
      expect(find.byType(Dialog), findsOneWidget);

      cubit.complete(
        'activity-1',
        outcome: ProgressActivityPhase.succeeded,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(Dialog), findsNothing);
      expect(cubit.state.activities, isEmpty);
    });
  });
}
