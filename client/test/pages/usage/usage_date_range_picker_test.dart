import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/session_usage_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/usage/widgets/usage_date_range_picker.dart';
import 'package:teampilot/services/usage/session_usage_sync_service.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

Widget _wrap(SessionUsageCubit cubit) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: BlocProvider.value(
      value: cubit,
      child: TpTheme(
        data: TpThemeData.fromColorScheme(
          ColorScheme.fromSeed(seedColor: Colors.indigo),
          scale: 1,
        ),
        child: Scaffold(
          body: BlocBuilder<SessionUsageCubit, SessionUsageState>(
            builder: (context, state) =>
                UsageDateRangePicker(state: state, cubit: cubit),
          ),
        ),
      ),
    ),
  );
}

SessionUsageCubit _cubit() => SessionUsageCubit(
  loadEvents: () async => const [],
  syncAll: () async => const UsageSyncResult(),
  loadSessions: () async => const <AppSession>[],
  loadTeams: () async => const <TeamProfile>[],
);

void main() {
  testWidgets('preset drafts preserve range semantics when confirmed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = _cubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.sessionUsageRangeTrigger));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(TpDateTimeRangePanel),
        matching: find.text('Confirm'),
      ),
    );
    await tester.pumpAndSettle();

    expect(cubit.state.range, UsageRange.all);

    cubit.setRange(UsageRange.sevenDays);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.sessionUsageRangeTrigger));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('tp-time-picker-hour')).first,
      '01',
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(TpDateTimeRangePanel),
        matching: find.text('Confirm'),
      ),
    );
    await tester.pumpAndSettle();

    expect(cubit.state.range, UsageRange.custom);
    expect(cubit.state.customStartMs, isNotNull);
    expect(
      DateTime.fromMillisecondsSinceEpoch(cubit.state.customStartMs!).hour,
      1,
    );
    expect(cubit.state.liveEnd, isTrue);
  });
}
