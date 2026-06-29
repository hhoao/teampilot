import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../cubits/mcp_cubit.dart';
import '../../cubits/mcp_discovery_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_catalog_listing.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import '../../widgets/empty_state_block.dart';
import 'mcp_discovery_helpers.dart';
import 'mcp_preset_listings.dart';
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
    return McpWorkspaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _McpDiscoveryHeader(),
          _McpDiscoverySearchField(
            controller: _searchCtl,
            onChanged: _onSearchChanged,
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
  const _McpDiscoveryHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocSelector<McpDiscoveryCubit, McpDiscoveryState,
        ({McpDiscoverySource source, bool loading})>(
      selector: (discovery) => (source: discovery.source, loading: discovery.loading),
      builder: (context, header) {
        final canRefresh = header.source != McpDiscoverySource.builtin;
        return McpCardHeader(
          title: l10n.mcpDiscoverySectionTitle,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 200,
                child: AppDropdownField<McpDiscoverySource>(
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
              IconButton(
                onPressed: !canRefresh || header.loading
                    ? null
                    : () => context.read<McpDiscoveryCubit>().refreshRemote(),
                icon: header.loading && canRefresh
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.refresh, size: context.appIconSizes.md),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _McpDiscoverySearchField extends StatelessWidget {
  const _McpDiscoverySearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<McpDiscoveryCubit, McpDiscoveryState, McpDiscoverySource>(
      selector: (discovery) => discovery.source,
      builder: (context, source) {
        if (!mcpDiscoveryShowsSearch(source)) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: onChanged,
              decoration: InputDecoration(
                hintText: context.l10n.mcpRegistrySearchHint,
                prefixIcon: Icon(Icons.search, size: context.appIconSizes.md),
                isDense: true,
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
    return BlocSelector<McpDiscoveryCubit, McpDiscoveryState,
        _McpDiscoveryCatalogSlice>(
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
      ),
      builder: (context, catalog) {
        if (catalog.remoteDisabled) {
          return _McpDiscoveryDisabledHint(onGoRegistries: onGoRegistries);
        }

        final l10n = context.l10n;
        final items = _resolveCatalogItems(catalog, l10n);

        return BlocSelector<McpCubit, McpState, ({Set<String> installedIds, Set<String> busyIds})>(
          selector: (mcp) => (
            installedIds: mcp.servers.map((s) => s.id).toSet(),
            busyIds: mcp.busyIds,
          ),
          builder: (context, installState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (catalog.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      catalog.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: catalog.loading &&
                          items.isEmpty &&
                          catalog.source != McpDiscoverySource.builtin &&
                          catalog.source != McpDiscoverySource.all
                      ? const Center(child: CircularProgressIndicator())
                      : items.isEmpty
                      ? EmptyStateBlock(
                          centered: true,
                          icon: Icons.search_off_outlined,
                          title: l10n.mcpCatalogEmpty,
                        )
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: items.length +
                              (catalog.hasMore ? 1 : 0),
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
                              installed: installState.installedIds
                                  .contains(listing.id),
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
  return switch (catalog.source) {
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
    McpDiscoverySource.smithery || McpDiscoverySource.official => catalog.remoteItems,
  };
}

class _McpDiscoveryDisabledHint extends StatelessWidget {
  const _McpDiscoveryDisabledHint({required this.onGoRegistries});

  final VoidCallback onGoRegistries;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return EmptyStateBlock(
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
