import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/models/mcp_catalog_listing.dart';
import 'package:teampilot/pages/mcp/mcp_shared_widgets.dart';

void main() {
  testWidgets('MCP catalog listing uses the shared card and four metrics', (
    tester,
  ) async {
    final listing = McpCatalogListing(
      id: 'acme/server',
      title: 'Acme Server',
      description: 'A useful MCP server.',
      source: McpCatalogSource.smithery,
      serverSpec: const {'command': 'run'},
      metrics: const CatalogMetrics(adoptionCount: 42),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: McpCatalogListingTile(
            listing: listing,
            installed: false,
            busy: false,
            onAdd: () {},
            onOpenHomepage: null,
          ),
        ),
      ),
    );

    expect(find.byType(TpCatalogCardShell), findsOneWidget);
    expect(find.text('Uses'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Rating'), findsOneWidget);
    expect(find.text('Updated'), findsOneWidget);
    expect(find.text('Published'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('Add'), findsOneWidget);
  });
}
