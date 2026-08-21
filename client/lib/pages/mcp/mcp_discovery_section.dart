import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../cubits/mcp_cubit.dart';
import '../../cubits/mcp_discovery_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/catalog/catalog_types.dart';
import '../../models/mcp_catalog_listing.dart';
import '../../services/catalog/catalog_sort_comparator.dart';
import '../../utils/debounce/debounce.dart';
import 'mcp_discovery_helpers.dart';
import 'mcp_preset_listings.dart';
import '../../widgets/workspace_library_card.dart';
import 'mcp_shared_widgets.dart';

/// Browse MCP servers from built-in presets and configured remote catalogs.
class McpDiscoverySection extends StatefulWidget {
  const McpDiscoverySection({
    required this.onAddListing,
    required this.onGoRegistries,
    super.key,
  });

  final void Function(McpCatalogListing listing) onAddListing;
  final VoidCallback onGoRegistries;

  @override
  State<McpDiscoverySection> createState() => _McpDiscoverySectionState();
}

class _McpDiscoverySectionState extends State<McpDiscoverySection> {
  final _searchCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<McpDiscoveryCubit>().initialize();
  }

  @override
  void dispose() {
    Debounces.cancel('mcp_discovery_search');
    _searchCtl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final source = context.read<McpDiscoveryCubit>().state.source;
    if (source == McpDiscoverySource.builtin ||
        source == McpDiscoverySource.all) {
      context.read<McpDiscoveryCubit>().setQuery(value);
      return;
    }
    Debounces.debounce(
      'mcp_discovery_search',
      const Duration(milliseconds: 400),
      () {
        if (!mounted) return;
        context.read<McpDiscoveryCubit>().setQuery(value);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WorkspaceLibraryCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _McpDiscoveryHeader(
            searchController: _searchCtl,
            onSearchChanged: _onSearchChanged,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _McpDiscoveryCatalogBody(
              onAddListing: widget.onAddListing,
              onGoRegistries: widget.onGoRegistries,
            ),
          ),
        ],
      ),
    );
  }
}

class _McpDiscoveryHeader extends StatelessWidget {
  const _McpDiscoveryHeader({
    required this.searchController,
    required this.onSearchChanged,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocSelector<
      McpDiscoveryCubit,
      McpDiscoveryState,
      ({
        McpDiscoverySource source,
        bool loading,
        CatalogSortKey sort,
        List<CatalogSourceFailure> failures,
      })
    >(
      selector: (discovery) => (
        source: discovery.source,
        loading: discovery.loading,
        sort: discovery.discoverySort,
        failures: discovery.discoveryFailures,
      ),
      builder: (context, header) {
        final canRefresh = header.source != McpDiscoverySource.builtin;
        return TpCatalogDiscoveryHeader(
          title: l10n.mcpDiscoverySectionTitle,
          showSearch: mcpDiscoveryShowsSearch(header.source),
          searchController: searchController,
          searchHint: l10n.mcpRegistrySearchHint,
          onSearchChanged: onSearchChanged,
          failures: [
            for (final failure in header.failures)
              TpCatalogFailureView(
                sourceLabel: failure.sourceLabel,
                message: failure.message,
              ),
          ],
          onRefresh: !canRefresh
              ? null
              : () => context.read<McpDiscoveryCubit>().refreshRemote(),
          refreshing: header.loading && canRefresh,
          refreshTooltip: l10n.catalogRefreshAccessibilityLabel,
          filters: [
            SizedBox(
              width: 180,
              child: TpSelect<McpDiscoverySource>(
                key: ValueKey(header.source),
                items: mcpDiscoverySourceOrder,
                itemLabel: (source) => mcpDiscoverySourceLabel(l10n, source),
                initialItem: header.source,
                onChanged: (next) {
                  if (next == null) return;
                  context.read<McpDiscoveryCubit>().setSource(next);
                },
              ),
            ),
            SizedBox(
              width: 170,
              child: TpCatalogSortControl<CatalogSortKey>(
                key: ValueKey(header.sort),
                items: CatalogSortKey.values,
                initialItem: header.sort,
                itemLabel: (sort) => _mcpSortLabel(context, sort),
                onChanged: (sort) {
                  if (sort != null) {
                    context.read<McpDiscoveryCubit>().setDiscoverySort(sort);
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

typedef _McpDiscoveryCatalogSlice = ({
  McpDiscoverySource source,
  String query,
  List<McpCatalogListing> remoteItems,
  List<McpCatalogListing> smitheryItems,
  List<McpCatalogListing> officialItems,
  bool loading,
  String? errorMessage,
  bool hasMore,
  bool remoteDisabled,
  CatalogSortKey sort,
  List<CatalogSourceFailure> failures,
});

class _McpDiscoveryCatalogBody extends StatelessWidget {
  const _McpDiscoveryCatalogBody({
    required this.onAddListing,
    required this.onGoRegistries,
  });

  final void Function(McpCatalogListing listing) onAddListing;
  final VoidCallback onGoRegistries;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      McpDiscoveryCubit,
      McpDiscoveryState,
      _McpDiscoveryCatalogSlice
    >(
      selector: (discovery) => (
        source: discovery.source,
        query: discovery.query,
        remoteItems: discovery.remoteItems,
        smitheryItems: discovery.smitheryItems,
        officialItems: discovery.officialItems,
        loading: discovery.loading,
        errorMessage: discovery.errorMessage,
        hasMore: discovery.hasMore,
        remoteDisabled: discovery.remoteDisabled,
        sort: discovery.discoverySort,
        failures: discovery.discoveryFailures,
      ),
      builder: (context, catalog) {
        if (catalog.remoteDisabled) {
          return _McpDiscoveryDisabledHint(onGoRegistries: onGoRegistries);
        }

        final l10n = context.l10n;
        final items = _resolveCatalogItems(catalog, l10n);

        return BlocSelector<
          McpCubit,
          McpState,
          ({Set<String> installedIds, Set<String> busyIds})
        >(
          selector: (mcp) => (
            installedIds: mcp.servers.map((s) => s.id).toSet(),
            busyIds: mcp.busyIds,
          ),
          builder: (context, installState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (catalog.errorMessage != null && items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      catalog.errorMessage!,
                      style: TpTextStyles.of(
                        context,
                      ).mdColored(Theme.of(context).colorScheme.error),
                    ),
                  ),
                Expanded(
                  child:
                      catalog.loading &&
                          items.isEmpty &&
                          catalog.source != McpDiscoverySource.builtin &&
                          catalog.source != McpDiscoverySource.all
                      ? const Center(child: CircularProgressIndicator())
                      : items.isEmpty
                      ? TpEmptyState(
                          centered: true,
                          icon: Icons.search_off_outlined,
                          title: l10n.mcpCatalogEmpty,
                        )
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: items.length + (catalog.hasMore ? 1 : 0),
                          itemExtentBuilder: (index, _) {
                            if (index >= items.length) return 64;
                            return TpCatalogListCard.listItemExtent(context);
                          },
                          itemBuilder: (context, index) {
                            if (index >= items.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Center(
                                  child: OutlinedButton(
                                    onPressed: catalog.loading
                                        ? null
                                        : () => context
                                              .read<McpDiscoveryCubit>()
                                              .loadMore(),
                                    child: Text(l10n.mcpRegistryLoadMore),
                                  ),
                                ),
                              );
                            }
                            final listing = items[index];
                            return McpCatalogListingTile(
                              listing: listing,
                              installed: installState.installedIds.contains(
                                listing.id,
                              ),
                              busy: installState.busyIds.contains(listing.id),
                              onAdd: () => onAddListing(listing),
                              onOpenHomepage: listing.homepage == null
                                  ? null
                                  : () => _openUrl(listing.homepage!),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

List<McpCatalogListing> _resolveCatalogItems(
  _McpDiscoveryCatalogSlice catalog,
  AppLocalizations l10n,
) {
  final items = switch (catalog.source) {
    McpDiscoverySource.builtin => filterMcpBuiltinListings(
      mcpBuiltinListings(l10n),
      catalog.query,
    ),
    McpDiscoverySource.all => mergeMcpDiscoveryAll(
      builtin: filterMcpBuiltinListings(
        mcpBuiltinListings(l10n),
        catalog.query,
      ),
      smithery: catalog.smitheryItems,
      official: catalog.officialItems,
      query: catalog.query,
    ),
    McpDiscoverySource.smithery ||
    McpDiscoverySource.official => catalog.remoteItems,
  };
  final sorted = List<McpCatalogListing>.from(items);
  sorted.sort(
    (a, b) => CatalogSortComparator.compare(
      _McpPageCatalogEntry(a),
      _McpPageCatalogEntry(b),
      catalog.sort,
    ),
  );
  return sorted;
}

String _mcpSortLabel(BuildContext context, CatalogSortKey sort) {
  final l10n = context.l10n;
  return switch (sort) {
    CatalogSortKey.adoption => l10n.catalogSortAdoption,
    CatalogSortKey.rating => l10n.catalogSortRating,
    CatalogSortKey.updated => l10n.catalogSortUpdated,
    CatalogSortKey.published => l10n.catalogSortPublished,
    CatalogSortKey.name => l10n.catalogSortName,
  };
}

class _McpPageCatalogEntry implements CatalogEntry {
  _McpPageCatalogEntry(this.listing);

  final McpCatalogListing listing;

  @override
  String get id => listing.id;

  @override
  CatalogResourceKind get kind => CatalogResourceKind.mcp;

  @override
  String get name => listing.title;

  @override
  String get description => listing.description;

  @override
  String? get sourceLabel => listing.source.name;

  @override
  String? get author => null;

  @override
  List<String> get tags => listing.tags;

  @override
  CatalogMetrics get metrics => listing.metrics;
}

class _McpDiscoveryDisabledHint extends StatelessWidget {
  const _McpDiscoveryDisabledHint({required this.onGoRegistries});

  final VoidCallback onGoRegistries;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpEmptyState(
      icon: Icons.cloud_off_outlined,
      title: l10n.mcpRepoDisabledHint,
      actionLabel: l10n.mcpEmptyGoRegistries,
      onAction: onGoRegistries,
    );
  }
}

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
