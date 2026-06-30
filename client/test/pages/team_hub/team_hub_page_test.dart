import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/team_hub_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/pages/team_hub/team_hub_page.dart';
import 'package:teampilot/services/team/team_clone_service.dart';
import 'package:teampilot/services/team_hub/team_hub_source.dart';

class _FakeSource implements TeamHubSource {
  @override
  Future<List<DiscoverableTeam>> fetchTeams({bool forceRefresh = false}) async =>
      const [
        DiscoverableTeam(
          key: 'o/r/squad',
          name: 'Research Squad',
          description: 'deep research',
          category: 'AI',
          updatedAt: 1,
        ),
      ];

  @override
  Future<List<String>> categories({bool forceRefresh = false}) async => ['AI'];
}

void main() {
  testWidgets('renders cards and opens detail on tap', (tester) async {
    tester.view.physicalSize = const Size(2400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final cubit = TeamHubCubit(
      source: _FakeSource(),
      loadFavorites: () async => <String>{},
      saveFavoriteToggle: (k) async => true,
      cloneTeam: (t) async => const CloneResult(
        teamId: 'new-id',
        installed: CloneDepInstallSummary(),
        failedDeps: [],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider(
          create: (_) => LayoutCubit(),
          child: BlocProvider.value(
            value: cubit,
            child: const Scaffold(
              body: TeamHubPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Research Squad'), findsOneWidget);

    await tester.tap(find.text('Research Squad'));
    await tester.pumpAndSettle();

    expect(find.byType(FilledButton), findsWidgets);
  });
}
