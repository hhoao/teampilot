import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/session_usage_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_global_section.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_route.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_sidebar.dart';
import 'package:teampilot/services/usage/session_usage_sync_service.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

SessionUsageCubit _emptyCubit() => SessionUsageCubit(
  loadEvents: () async => const <SessionUsageEvent>[],
  syncAll: () async => const UsageSyncResult(),
  loadSessions: () async => const <AppSession>[],
  loadTeams: () async => const <TeamProfile>[],
);

Widget _app({required Widget child}) => TpTheme(
  data: TpThemeData.fromColorScheme(
    ColorScheme.fromSeed(seedColor: Colors.indigo),
    scale: 1,
  ),
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

void main() {
  test('usage segment round-trips through the home route', () {
    expect(HomeGlobalView.fromSegment('usage'), HomeGlobalView.usage);
    expect(HomeGlobalView.usage.homeLocation, '/home-v2?global=usage');
    expect(
      HomeWorkspaceRoute.homeGlobalView('/home-v2?global=usage'),
      HomeGlobalView.usage,
    );
  });

  testWidgets('sidebar row selects the usage global view', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    HomeGlobalView? selected;
    await tester.pumpWidget(
      _app(child: HomeSidebar(onSelectGlobalView: (view) => selected = view)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Token usage'));
    expect(selected, HomeGlobalView.usage);
  });

  testWidgets('usage deep link builds the usage pane', (tester) async {
    final cubit = _emptyCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      _app(
        child: BlocProvider.value(
          value: cubit,
          child: const HomeGlobalSection(view: HomeGlobalView.usage),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.sessionUsagePage), findsOneWidget);
    expect(find.text('Token usage'), findsOneWidget);
  });
}
