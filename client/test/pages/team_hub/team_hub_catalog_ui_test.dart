import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/pages/team_hub/team_hub_cards.dart';

void main() {
  testWidgets('team card uses fixed four-row layout without browse action', (
    tester,
  ) async {
    final team = DiscoverableTeam(
      key: 'o/r/team',
      name: 'Team',
      description: 'Description',
      category: 'AI',
      author: 'Alice Very Long Author Name That Should Ellipsize',
      updatedAt: 100,
      metrics: const CatalogMetrics(
        adoptionCount: 10,
        rating: 4.5,
        updatedAtMs: 100,
        publishedAtMs: 90,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(
            ColorScheme.fromSeed(seedColor: Colors.blue),
            scale: 1.0,
          ),
          child: Scaffold(
            body: TeamHubCard(
              team: team,
              favorited: false,
              busy: false,
              onTap: () {},
              onToggleFavorite: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TpCatalogCardShell), findsNothing);
    expect(find.byType(TpCatalogMetadataRow), findsOneWidget);
    expect(find.text('Browse all teams'), findsNothing);
    expect(find.text('Team'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.textContaining('1970'), findsNothing);
  });

  testWidgets('team card shows none when description is empty', (tester) async {
    final team = DiscoverableTeam(
      key: 'o/r/empty',
      name: 'Empty',
      description: '   ',
      category: '',
      updatedAt: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(
            ColorScheme.fromSeed(seedColor: Colors.blue),
            scale: 1.0,
          ),
          child: Scaffold(
            body: TeamHubCard(
              team: team,
              favorited: false,
              busy: false,
              onTap: () {},
              onToggleFavorite: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('无'), findsOneWidget);
  });
}
