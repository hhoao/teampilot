import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/pages/plugins/plugin_discovery_section.dart';

void main() {
  DiscoverablePlugin plugin() => const DiscoverablePlugin(
    key: 'owner/marketplace/plugin',
    name: 'catalog-plugin',
    description: 'A discoverable plugin',
    version: '1.2.3',
    source: 'plugins/catalog-plugin',
    marketplaceOwner: 'owner',
    marketplaceName: 'marketplace',
    marketplaceBranch: 'main',
    metrics: CatalogMetrics(
      adoptionCount: 1234,
      rating: 4.5,
      updatedAtMs: 1723507200000,
      publishedAtMs: 1723420800000,
    ),
  );

  PluginState state({List<CatalogSourceFailure> failures = const []}) =>
      PluginState(
        marketplaces: const [
          PluginMarketplace(owner: 'owner', name: 'marketplace'),
        ],
        discoverable: [plugin()],
        discoveryFailures: failures,
      );

  Widget wrap(PluginState state) {
    final cubit = PluginCubit.test(state);
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TpTheme(
        data: TpThemeData.fromColorScheme(
          ThemeData.light().colorScheme,
          scale: 1.0,
        ),
        child: Scaffold(
          body: BlocProvider<PluginCubit>.value(
            value: cubit,
            child: SizedBox(
              height: 800,
              child: PluginDiscoveryBody(
                state: cubit.state,
                installed: const [],
                onGoMarketplaces: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders sort control, warning, and compact catalog metrics', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        state(
          failures: const [
            CatalogSourceFailure(
              sourceId: 'broken',
              sourceLabel: 'Broken marketplace',
              message: 'network unavailable',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TpCatalogSortControl<CatalogSortKey>), findsOneWidget);
    expect(find.byType(TpCatalogSourceWarning), findsOneWidget);
    expect(find.byType(TpCatalogDiscoveryHeader), findsOneWidget);
    expect(find.byType(TpCatalogListCard), findsOneWidget);
    expect(find.text('catalog-plugin'), findsOneWidget);
    expect(find.text('1,234'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('Updated'), findsNothing);
    expect(find.text('Published'), findsNothing);
  });

  testWidgets('shows blocking error only when no discovery result exists', (
    tester,
  ) async {
    final empty = PluginState(
      marketplaces: const [
        PluginMarketplace(owner: 'owner', name: 'marketplace'),
      ],
      discoveryFailures: const [
        CatalogSourceFailure(
          sourceId: 'broken',
          sourceLabel: 'Broken marketplace',
          message: 'network unavailable',
        ),
      ],
      errorMessage: 'Could not load plugin marketplaces.',
    );
    await tester.pumpWidget(wrap(empty));
    await tester.pumpAndSettle();

    expect(find.text('Could not load plugin marketplaces.'), findsOneWidget);
    expect(find.text('No plugins discovered'), findsNothing);
  });
}
