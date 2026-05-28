import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/mcp_presets.dart';
import '../../cubits/mcp_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_catalog_listing.dart';
import '../../models/mcp_registry_source.dart';
import '../../services/mcp/mcp_catalog_mapper.dart';
import '../../services/mcp/mcp_registry_browse_service.dart';
import '../../services/mcp/mcp_registry_config_service.dart';
import '../../services/mcp/smithery_mcp_service.dart';
import '../../utils/debounce/debounce.dart';
import 'mcp_shared_widgets.dart';

enum _DiscoverySource { builtin, smithery, official }

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
  final _configService = McpRegistryConfigService();
  final _smithery = SmitheryMcpService();
  final _registry = McpRegistryBrowseService();

  _DiscoverySource _source = _DiscoverySource.builtin;
  McpRegistrySourcesConfig? _registryConfig;
  String _query = '';
  bool _loading = false;
  String? _error;
  List<McpCatalogListing> _remoteItems = const [];
  int _smitheryPage = 1;
  int _smitheryTotalPages = 1;
  String? _registryCursor;
  String? _registryNextCursor;

  @override
  void initState() {
    super.initState();
    _loadRegistryConfig();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _smithery.close();
    _registry.close();
    super.dispose();
  }

  Future<void> _loadRegistryConfig() async {
    final config = await _configService.load();
    if (!mounted) return;
    setState(() => _registryConfig = config);
    if (_source != _DiscoverySource.builtin) {
      _loadRemote(reset: true);
    }
  }

  List<McpCatalogListing> get _builtinListings {
    final l10n = context.l10n;
    return mcpPresets(descriptionFor: (id) => _presetDescription(l10n, id))
        .map(McpCatalogMapper.fromPreset)
        .toList();
  }

  List<McpCatalogListing> get _displayItems {
    if (_source == _DiscoverySource.builtin) {
      final q = _query.trim().toLowerCase();
      if (q.isEmpty) return _builtinListings;
      return _builtinListings.where((e) {
        return e.title.toLowerCase().contains(q) ||
            e.id.toLowerCase().contains(q) ||
            e.description.toLowerCase().contains(q);
      }).toList();
    }
    return _remoteItems;
  }

  McpRegistrySourceConfig? get _activeRemoteSource {
    final config = _registryConfig;
    if (config == null) return null;
    return switch (_source) {
      _DiscoverySource.smithery =>
        config.byKind(McpRegistrySourceKind.smithery),
      _DiscoverySource.official =>
        config.byKind(McpRegistrySourceKind.officialRegistry),
      _ => null,
    };
  }

  Future<void> _loadRemote({bool reset = true}) async {
    final source = _activeRemoteSource;
    if (source == null || !source.enabled) {
      setState(() {
        _remoteItems = const [];
        _error = null;
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _remoteItems = const [];
        _smitheryPage = 1;
        _registryCursor = null;
        _registryNextCursor = null;
      }
    });

    try {
      if (_source == _DiscoverySource.smithery) {
        final page = reset ? 1 : _smitheryPage;
        final result = await _smithery.search(
          _query,
          baseUrl: source.baseUrl,
          apiToken: source.apiToken,
          page: page,
        );
        if (!mounted) return;
        setState(() {
          _remoteItems = reset ? result.items : [..._remoteItems, ...result.items];
          _smitheryPage = result.page;
          _smitheryTotalPages = result.totalPages;
        });
      } else {
        final cursor = reset ? null : _registryCursor;
        final result = await _registry.search(
          _query,
          baseUrl: source.baseUrl,
          cursor: cursor,
        );
        if (!mounted) return;
        setState(() {
          _remoteItems = reset ? result.items : [..._remoteItems, ...result.items];
          _registryCursor = cursor;
          _registryNextCursor = result.nextCursor;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSourceChanged(_DiscoverySource next) {
    setState(() => _source = next);
    if (next == _DiscoverySource.builtin) {
      setState(() {
        _remoteItems = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    _loadRemote(reset: true);
  }

  void _onSearchChanged(String value) {
    _query = value;
    if (_source == _DiscoverySource.builtin) {
      setState(() {});
      return;
    }
    Debounces.debounce(
      'mcp_discovery_search',
      const Duration(milliseconds: 400),
      () {
        if (mounted) _loadRemote();
      },
    );
  }

  bool get _hasMore => _source == _DiscoverySource.smithery
      ? _smitheryPage < _smitheryTotalPages
      : (_registryNextCursor != null && _registryNextCursor!.isNotEmpty);

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _source == _DiscoverySource.builtin) return;
    if (_source == _DiscoverySource.smithery) {
      setState(() => _smitheryPage++);
    } else {
      setState(() => _registryCursor = _registryNextCursor);
    }
    await _loadRemote(reset: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<McpCubit>().state;
    final installedIds = state.servers.map((s) => s.id).toSet();
    final remoteSource = _activeRemoteSource;
    final remoteDisabled = _source != _DiscoverySource.builtin &&
        (remoteSource == null || !remoteSource.enabled);
    final items = _displayItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        McpWorkspaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              McpCardHeader(
                title: l10n.mcpDiscoverySectionTitle,
                trailing: IconButton(
                  onPressed: _source == _DiscoverySource.builtin || _loading
                      ? null
                      : () => _loadRemote(),
                  icon: _loading && _source != _DiscoverySource.builtin
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
                    selected: _source == _DiscoverySource.builtin,
                    onSelected: (_) => _onSourceChanged(_DiscoverySource.builtin),
                  ),
                  ChoiceChip(
                    label: Text(l10n.mcpRegistrySmithery),
                    selected: _source == _DiscoverySource.smithery,
                    onSelected: (_) => _onSourceChanged(_DiscoverySource.smithery),
                  ),
                  ChoiceChip(
                    label: Text(l10n.mcpRegistryOfficial),
                    selected: _source == _DiscoverySource.official,
                    onSelected: (_) => _onSourceChanged(_DiscoverySource.official),
                  ),
                ],
              ),
              if (_source != _DiscoverySource.builtin) ...[
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
            ],
          ),
        ),
        if (remoteDisabled)
          McpWorkspaceCard(
            child: Column(
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
            ),
          )
        else ...[
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _loading && items.isEmpty && _source != _DiscoverySource.builtin
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? Center(child: Text(l10n.mcpCatalogEmpty))
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: items.length +
                        (_source != _DiscoverySource.builtin && _hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= items.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: OutlinedButton(
                              onPressed: _loading ? null : _loadMore,
                              child: Text(l10n.mcpRegistryLoadMore),
                            ),
                          ),
                        );
                      }
                      final listing = items[index];
                      return McpCatalogListingTile(
                        listing: listing,
                        installed: installedIds.contains(listing.id),
                        busy: state.busyIds.contains(listing.id),
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
    );
  }
}

String _presetDescription(dynamic l10n, String id) => switch (id) {
  'fetch' => l10n.mcpPresetDescFetch,
  'time' => l10n.mcpPresetDescTime,
  'memory' => l10n.mcpPresetDescMemory,
  'sequential-thinking' => l10n.mcpPresetDescSequentialThinking,
  'context7' => l10n.mcpPresetDescContext7,
  _ => '',
};

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
