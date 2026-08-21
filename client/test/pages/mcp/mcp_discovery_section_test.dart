import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/models/mcp_catalog_listing.dart';
import 'package:teampilot/pages/mcp/mcp_shared_widgets.dart';

void main() {
  testWidgets('MCP catalog listing uses fixed four-row layout', (tester) async {
    final listing = McpCatalogListing(
      id: 'acme/server',
      title: 'Acme Server',
      description: 'A useful MCP server.',
      source: McpCatalogSource.smithery,
      serverSpec: const {'command': 'run'},
      tags: const ['tools'],
      metrics: const CatalogMetrics(adoptionCount: 42, rating: 4.2),
      homepage: 'https://example.com',
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
            body: McpCatalogListingTile(
              listing: listing,
              installed: false,
              busy: false,
              onAdd: () {},
              onOpenHomepage: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TpCatalogCardShell), findsNothing);
    expect(find.byType(TpCatalogListCard), findsOneWidget);
    expect(find.byType(TpCatalogMetadataRow), findsOneWidget);
    expect(find.text('Acme Server'), findsOneWidget);
    expect(find.text('A useful MCP server.'), findsOneWidget);
    expect(find.text('tools'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('4.2'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    expect(find.text('Updated'), findsNothing);
    expect(find.text('Published'), findsNothing);

    final card = tester.widget<TpCatalogListCard>(
      find.byType(TpCatalogListCard),
    );
    expect(card, isNotNull);
    final extent = TpCatalogListCard.listItemExtent(
      tester.element(find.byType(TpCatalogListCard)),
    );
    expect(tester.getSize(find.byType(TpCatalogListCard)).height, extent);
  });
}
