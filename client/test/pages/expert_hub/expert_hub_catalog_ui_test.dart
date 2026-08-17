import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/pages/expert_hub/expert_hub_cards.dart';

void main() {
  testWidgets(
    'expert card uses the shared catalog card shell and four metrics',
    (tester) async {
      final member = DiscoverableMember(
        key: 'o/r/expert',
        name: 'Expert',
        description: 'Description',
        category: 'AI',
        source: ExpertMemberSource.registry,
        member: const DiscoverableTeamMember(name: 'expert'),
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
              body: ExpertHubCard(
                member: member,
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
    },
  );
}
