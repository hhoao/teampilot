import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/cubits/session_usage_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/progress_activity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/services/usage/session_usage_sync_service.dart';
import 'package:teampilot/services/usage/usage_sync_control.dart';
import 'package:teampilot/widgets/workspace_status_bar/session_usage_progress_bridge.dart';

class _Recorder implements NotificationRecorder {
  @override
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
  }) {}
}

void main() {
  testWidgets('mirrors usage sync into the global progress activities', (
    tester,
  ) async {
    final progressCubit = ProgressActivityCubit(historyRecorder: _Recorder());
    final progress = StreamController<UsageSyncProgress>.broadcast();
    final done = Completer<UsageSyncResult>();
    var cancelCalls = 0;
    final cubit = SessionUsageCubit(
      loadEvents: () async => const [],
      syncAll: () async => const UsageSyncResult(),
      startSync: () => UsageSyncHandle(
        done: done.future,
        progress: progress.stream,
        cancel: () => cancelCalls++,
      ),
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(() async {
      await progress.close();
      await cubit.close();
      await progressCubit.close();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SessionUsageCubit>.value(value: cubit),
          BlocProvider<ProgressActivityCubit>.value(value: progressCubit),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SessionUsageProgressBridge(child: SizedBox()),
        ),
      ),
    );

    final syncFuture = cubit.sync();
    await tester.pump();

    expect(progressCubit.state.activities, hasLength(1));
    expect(
      progressCubit.state.activities.single.kind,
      ProgressActivityKind.sessionUsage,
    );
    expect(progressCubit.state.activities.single.title, 'Usage sync');
    expect(
      progressCubit.state.activities.single.phase,
      ProgressActivityPhase.running,
    );

    progress.add(
      const UsageSyncProgress(targetsTotal: 4, targetsDone: 2, inserted: 7),
    );
    await tester.pump();
    expect(progressCubit.state.activities.single.fraction, 0.5);
    expect(
      progressCubit.state.activities.single.subtitle,
      'Scanning 2/4 sessions · 7 new events',
    );

    done.complete(const UsageSyncResult(targetsScanned: 4, inserted: 7));
    await syncFuture;
    await tester.pumpAndSettle();

    expect(progressCubit.state.activities, isEmpty);
    expect(cancelCalls, 0);
  });
}
