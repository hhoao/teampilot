import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/team_hub_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/pages/team_hub/team_landing_picker_sheet.dart';
import 'package:teampilot/services/team/team_clone_service.dart';
import 'package:teampilot/services/team_hub/team_hub_source.dart';

import '../../support/post_frame_test_harness.dart';

class _MockLaunchProfileCubit extends Mock implements LaunchProfileCubit {}

class _FakeSource implements TeamHubSource {
  @override
  Future<List<DiscoverableTeam>> fetchTeams({
    bool forceRefresh = false,
  }) async => const [
    DiscoverableTeam(
      key: 'o/r/squad',
      name: 'Research Squad',
      description: 'deep research',
      category: 'AI',
      updatedAt: 1,
      roster: [
        TeamRosterSlot(
          id: 'team-lead',
          expertKey: 'teampilot/builtin/team-lead',
        ),
      ],
    ),
  ];

  @override
  Future<List<String>> categories({bool forceRefresh = false}) async => ['AI'];
}

void _stubCubit(LaunchProfileCubit cubit, LaunchProfileState state) {
  when(() => cubit.state).thenReturn(state);
  when(() => cubit.stream).thenAnswer((_) => Stream<LaunchProfileState>.empty());
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Future<TeamHubCubit> pumpHubCubit() async {
    final cubit = TeamHubCubit(
      source: _FakeSource(),
      loadFavorites: () async => <String>{},
      saveFavoriteToggle: (_) async => true,
      cloneTeam: (_) async => const CloneResult(
        teamId: 'cloned-id',
        installed: CloneDepInstallSummary(),
        failedDeps: [],
      ),
    );
    await cubit.load();
    return cubit;
  }

  Future<void> pumpHost(
    WidgetTester tester, {
    required TeamHubCubit hubCubit,
    required LaunchProfileCubit launchCubit,
    required Widget home,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TeamHubCubit>.value(value: hubCubit),
          BlocProvider<LaunchProfileCubit>.value(value: launchCubit),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('confirm local team pops teamId', (tester) async {
    const local = TeamProfile(
      id: 'local-alpha',
      name: 'Alpha Local',
      description: 'my local team',
      roster: [
        TeamRosterSlot(id: 'lead', expertKey: 'teampilot/builtin/team-lead'),
      ],
    );
    final hubCubit = await pumpHubCubit();
    addTearDown(hubCubit.close);

    final launchCubit = _MockLaunchProfileCubit();
    _stubCubit(
      launchCubit,
      const LaunchProfileState(identities: [local], isLoading: false),
    );

    String? result;
    await pumpHost(
      tester,
      hubCubit: hubCubit,
      launchCubit: launchCubit,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showTeamLandingPickerSheet(
                context,
                touchRecent: (_) async {},
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(TeamLandingPickerDialog), findsOneWidget);
    expect(find.text('TeamHub'), findsWidgets);
    expect(find.text('Alpha Local'), findsOneWidget);
    expect(find.text('My Teams'), findsWidgets);

    await tester.tap(find.text('Alpha Local'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm'), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.byType(TeamLandingPickerDialog), findsNothing);
    expect(result, 'local-alpha');
  });
}
