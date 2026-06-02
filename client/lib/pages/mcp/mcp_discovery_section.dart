import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../cubits/mcp_cubit.dart';
import '../../cubits/mcp_discovery_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_catalog_listing.dart';
import '../../utils/debounce/debounce.dart';
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
    if (context.read<McpDiscoveryCubit>().state.source ==
        McpDiscoverySource.builtin) {
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
    final l10n = context.l10n;
    final mcpState = context.watch<McpCubit>().state;
    final installedIds = mcpState.servers.map((s) => s.id).toSet();

    return BlocBuilder<McpDiscoveryCubit, McpDiscoveryState>(
      builder: (context, discovery) {
        final items = discovery.source == McpDiscoverySource.builtin
            ? filterMcpBuiltinListings(
                mcpBuiltinListings(l10n),
                discovery.query,
              )
            : discovery.remoteItems;

        return McpWorkspaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              McpCardHeader(
                title: l10n.mcpDiscoverySectionTitle,
                trailing: IconButton(
                  onPressed: discovery.source == McpDiscoverySource.builtin ||
                          discovery.loading
                      ? null
                      : () => context.read<McpDiscoveryCubit>().refreshRemote(),
                  icon: discovery.loading &&
                          discovery.source != McpDiscoverySource.builtin
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 20),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(l10n.mcpDiscoverySourceBuiltin),
                    selected: discovery.source == McpDiscoverySource.builtin,
                    onSelected: (_) => context
                        .read<McpDiscoveryCubit>()
                        .setSource(McpDiscoverySource.builtin),
                  ),
                  ChoiceChip(
                    label: Text(l10n.mcpRegistrySmithery),
                    selected: discovery.source == McpDiscoverySource.smithery,
                    onSelected: (_) => context
                        .read<McpDiscoveryCubit>()
                        .setSource(McpDiscoverySource.smithery),
                  ),
                  ChoiceChip(
                    label: Text(l10n.mcpRegistryOfficial),
                    selected: discovery.source == McpDiscoverySource.official,
                    onSelected: (_) => context
                        .read<McpDiscoveryCubit>()
                        .setSource(McpDiscoverySource.official),
                  ),
                ],
              ),
              if (discovery.source != McpDiscoverySource.builtin) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtl,
                  onChanged: _onSearchChanged,
                  onSubmitted: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: l10n.mcpRegistrySearchHint,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (discovery.remoteDisabled)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.mcpRepoDisabledHint),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: widget.onGoRegistries,
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        label: Text(l10n.mcpEmptyGoRegistries),
                      ),
                    ),
                  ],
                )
              else ...[
                if (discovery.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      discovery.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: discovery.loading &&
                          items.isEmpty &&
                          discovery.source != McpDiscoverySource.builtin
                      ? const Center(child: CircularProgressIndicator())
                      : items.isEmpty
                      ? Center(child: Text(l10n.mcpCatalogEmpty))
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: items.length +
                              (discovery.source != McpDiscoverySource.builtin &&
                                      discovery.hasMore
                                  ? 1
                                  : 0),
                          itemBuilder: (context, index) {
                            if (index >= items.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Center(
                                  child: OutlinedButton(
                                    onPressed: discovery.loading
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
                              installed: installedIds.contains(listing.id),
                              busy: mcpState.busyIds.contains(listing.id),
                              onAdd: () => widget.onAddListing(listing),
                              onOpenHomepage: listing.homepage == null
                                  ? null
                                  : () => _openUrl(listing.homepage!),
                            );
                          },
                        ),
                ),
              ],
            ],
          ),
        );
      },
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
