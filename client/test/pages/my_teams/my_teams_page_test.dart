import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/pages/my_teams/my_teams_page.dart';
import 'package:teampilot/repositories/session_repository.dart';

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

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('lists teams, shows New Team, and deletes on confirm', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final teamAlpha = TeamProfile(
      id: 'team-alpha',
      name: 'Alpha Squad',
      cli: CliTool.claude,
      teamMode: TeamMode.native,
      roster: _roster,
      createdAt: DateTime(2026, 1, 15).millisecondsSinceEpoch,
    );
    final teamBeta = TeamProfile(
      id: 'team-beta',
      name: 'Beta Crew',
      cli: CliTool.flashskyai,
      teamMode: TeamMode.mixed,
      roster: const [
        TeamRosterSlot(id: 'lead', expertKey: 'teampilot/builtin/team-lead'),
      ],
      createdAt: DateTime(2026, 2, 20).millisecondsSinceEpoch,
    );

    final cubit = _SpyLaunchProfileCubit(
      repository: testLaunchProfileRepository(
        Directory.systemTemp.createTempSync('my_teams_page_'),
      ),
      sessionRepository: SessionRepository(),
      executableResolver: () => 'flashskyai',
    );
    cubit.emit(
      cubit.state.copyWith(
        identities: [teamAlpha, teamBeta],
        selectedTeamId: teamAlpha.id,
        isLoading: false,
      ),
    );
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
}
