import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/notification_cubit.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/progress_activity.dart';
import 'package:teampilot/repositories/notification_repository.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/widgets/notification/notification_center_panel.dart';

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

ProgressActivity _ongoingActivity() {
  final at = DateTime(2026, 7, 30, 12);
  return ProgressActivity(
    id: 'ongoing-1',
    kind: ProgressActivityKind.fileTreeImport,
    title: 'Importing files',
    phase: ProgressActivityPhase.running,
    cancellable: true,
    createdAt: at,
    updatedAt: at,
  );
}

Widget _host({
  required NotificationCubit notificationCubit,
  required ProgressActivityCubit progressCubit,
  required Widget child,
}) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(colorScheme: scheme),
    home: TpTheme(
      data: TpThemeData.fromColorScheme(scheme, scale: 1),
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: notificationCubit),
          BlocProvider.value(value: progressCubit),
        ],
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('clear all removes history but keeps ongoing activities', (
    tester,
  ) async {
    final fs = InMemoryFilesystem();
    final notificationCubit = NotificationCubit(
      repository: NotificationRepository(
        fs: fs,
        storePath: '/notifications.json',
      ),
    );
    addTearDown(notificationCubit.close);

    notificationCubit.record(
      message: 'Import finished',
      variant: TpToastVariant.success,
      title: 'History item',
    );
    await tester.pump();

    final progressCubit = ProgressActivityCubit(
      historyRecorder: _FakeNotificationRecorder(),
    );
    addTearDown(progressCubit.close);
    progressCubit.start(_ongoingActivity());

    await tester.pumpWidget(
      _host(
        notificationCubit: notificationCubit,
        progressCubit: progressCubit,
        child: NotificationCenterPanel(onClose: () {}),
      ),
    );
    await tester.pump();

    expect(find.text('History item'), findsOneWidget);
    expect(find.text('Importing files'), findsOneWidget);
    expect(find.text('Ongoing'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('History item'), findsNothing);
    expect(find.text('Importing files'), findsOneWidget);
    expect(find.text('History'), findsNothing);
    expect(find.text('Ongoing'), findsOneWidget);
  });

  testWidgets('mark all read and clear stay disabled when only ongoing exist', (
    tester,
  ) async {
    final notificationCubit = NotificationCubit(
      repository: NotificationRepository(
        fs: InMemoryFilesystem(),
        storePath: '/notifications.json',
      ),
    );
    addTearDown(notificationCubit.close);

    final progressCubit = ProgressActivityCubit(
      historyRecorder: _FakeNotificationRecorder(),
    );
    addTearDown(progressCubit.close);
    progressCubit.start(_ongoingActivity());

    await tester.pumpWidget(
      _host(
        notificationCubit: notificationCubit,
        progressCubit: progressCubit,
        child: NotificationCenterPanel(onClose: () {}),
      ),
    );
    await tester.pump();

    final markAllRead = tester.widget<IconButton>(find.byType(IconButton));
    final clearAll = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Clear'),
    );
    expect(markAllRead.onPressed, isNull);
    expect(clearAll.onPressed, isNull);
  });
}
