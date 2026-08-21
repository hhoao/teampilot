import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/pages/team_hub/team_hub_cards.dart';
import 'package:teampilot/pages/team_hub/team_hub_body.dart';

void main() {
  testWidgets('team card uses compact catalog metrics without dates', (
    tester,
  ) async {
    final team = DiscoverableTeam(
      key: 'o/r/team',
      name: 'Team',
      description: 'Description',
      category: 'AI',
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

    expect(find.byType(TpCatalogCardShell), findsOneWidget);
    expect(find.byType(TpCatalogMetadataRow), findsOneWidget);
    expect(find.textContaining('1970'), findsNothing);
  });
}
