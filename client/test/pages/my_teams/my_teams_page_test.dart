import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/pages/my_teams/my_teams_page.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/hub_publish/hub_publish_record_store.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

const _roster = [
  TeamRosterSlot(id: 'lead', expertKey: 'teampilot/builtin/team-lead'),
  TeamRosterSlot(id: 'dev', expertKey: 'teampilot/builtin/developer'),
];

class _SpyLaunchProfileCubit extends LaunchProfileCubit {
  _SpyLaunchProfileCubit({
    required super.repository,
    required super.sessionRepository,
    required super.executableResolver,
  });

  final deletedTeamIds = <String>[];

  @override
  Future<void> deleteTeam(String id) async {
    deletedTeamIds.add(id);
  }
}

TeamProfile _teamAlpha() => TeamProfile(
  id: 'team-alpha',
  name: 'Alpha Squad',
  cli: CliTool.claude,
  teamMode: TeamMode.native,
  roster: _roster,
  createdAt: DateTime(2026, 1, 15).millisecondsSinceEpoch,
);

TeamProfile _teamBeta() => TeamProfile(
  id: 'team-beta',
  name: 'Beta Crew',
  cli: CliTool.flashskyai,
  teamMode: TeamMode.mixed,
  roster: const [
    TeamRosterSlot(id: 'lead', expertKey: 'teampilot/builtin/team-lead'),
  ],
  createdAt: DateTime(2026, 2, 20).millisecondsSinceEpoch,
);

_SpyLaunchProfileCubit _loadedCubit() {
  final cubit = _SpyLaunchProfileCubit(
    repository: testLaunchProfileRepository(
      Directory.systemTemp.createTempSync('my_teams_page_'),
    ),
    sessionRepository: SessionRepository(),
    executableResolver: () => 'flashskyai',
  );
  cubit.emit(
    cubit.state.copyWith(
      identities: [_teamAlpha(), _teamBeta()],
      selectedTeamId: 'team-alpha',
      isLoading: false,
    ),
  );
  return cubit;
}

void _largeTestSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('lists teams, shows New Team, and deletes on confirm', (
    tester,
  ) async {
    _largeTestSurface(tester);

    final cubit = _loadedCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<LaunchProfileCubit>.value(
          value: cubit,
          child: const Scaffold(body: MyTeamsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alpha Squad'), findsOneWidget);
    expect(find.text('Beta Crew'), findsOneWidget);
    expect(find.text('New Team'), findsOneWidget);

    await tester.tap(find.byKey(const Key('my-teams-delete-team-beta')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(cubit.deletedTeamIds, ['team-beta']);
  });

  testWidgets('tap card invokes onOpenTeam with team id', (tester) async {
    _largeTestSurface(tester);

    final cubit = _loadedCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    final openedIds = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<LaunchProfileCubit>.value(
          value: cubit,
          child: Scaffold(
            body: MyTeamsPage(onOpenTeam: openedIds.add),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Beta Crew'));
    await tester.pumpAndSettle();

    expect(openedIds, ['team-beta']);
  });

  testWidgets('initialTeamId auto-opens matching team via onOpenTeam', (
    tester,
  ) async {
    _largeTestSurface(tester);

    final cubit = _loadedCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    final openedIds = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<LaunchProfileCubit>.value(
          value: cubit,
          child: Scaffold(
            body: MyTeamsPage(
              initialTeamId: 'team-alpha',
              onOpenTeam: openedIds.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(openedIds, ['team-alpha']);
  });

  testWidgets('deep link team query auto-opens via onOpenTeam', (tester) async {
    _largeTestSurface(tester);

    final cubit = _loadedCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    final openedIds = <String>[];

    await tester.pumpWidget(
      MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          initialLocation: '/home-v2?global=myTeams&team=team-beta',
          routes: [
            GoRoute(
              path: '/home-v2',
              builder: (context, state) => BlocProvider<LaunchProfileCubit>.value(
                value: cubit,
                child: Scaffold(
                  body: MyTeamsPage(onOpenTeam: openedIds.add),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(openedIds, ['team-beta']);
  });

  testWidgets('shows PR open badge when HubPublishRecord matches team', (
    tester,
  ) async {
    _largeTestSurface(tester);

    final cubit = _loadedCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });

    final fs = InMemoryFilesystem();
    final records = HubPublishRecordStore(fs: fs, pathOverride: '/p.json');
    await records.upsert(
      HubPublishRecord(
        kind: HubPublishKind.team,
        registryFullName: 'hhoao/teampilot-resources/team-hub',
        slug: 'alpha-squad',
        prUrl: 'https://github.com/hhoao/teampilot/pull/9',
        publishedAtMs: 1,
        localId: 'team-alpha',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<LaunchProfileCubit>.value(
          value: cubit,
          child: Scaffold(
            body: MyTeamsPage(records: records),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hub-publish-badge-team-team-alpha')), findsOneWidget);
    expect(find.text('PR open'), findsOneWidget);
    expect(find.byKey(const Key('hub-publish-badge-team-team-beta')), findsNothing);
  });
}
