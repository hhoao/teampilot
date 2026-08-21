import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/pages/expert_hub/expert_hub_cards.dart';

void main() {
  testWidgets('expert card uses fixed four-row layout without view action', (
    tester,
  ) async {
    final member = DiscoverableMember(
      key: 'o/r/expert',
      name: 'Expert',
      description: 'Description',
      category: 'AI',
      author: 'Alice Very Long Author Name That Should Ellipsize',
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
        locale: const Locale('en'),
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

    expect(find.byType(TpCatalogCardShell), findsNothing);
    expect(find.byType(TpCatalogMetadataRow), findsOneWidget);
    expect(find.text('View in Expert Hub'), findsNothing);
    expect(find.text('Expert'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.textContaining('1970'), findsNothing);
  });

  testWidgets('expert card shows none when description is empty', (
    tester,
  ) async {
    final member = DiscoverableMember(
      key: 'o/r/empty',
      name: 'Empty',
      description: '   ',
      category: '',
      source: ExpertMemberSource.builtin,
      member: const DiscoverableTeamMember(name: 'empty'),
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

    expect(find.text('无'), findsOneWidget);
  });
}
