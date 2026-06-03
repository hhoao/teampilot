import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/plugin_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/plugin.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/github_source_url.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import '../../widgets/github_details_button.dart';
import 'plugin_management_cards.dart';

class PluginDiscoverySection extends StatefulWidget {
  const PluginDiscoverySection({
    super.key,
    required this.state,
    required this.onGoMarketplaces,
  });
  final PluginState state;
  final VoidCallback onGoMarketplaces;

  @override
  State<PluginDiscoverySection> createState() => PluginDiscoverySectionState();
}

class PluginDiscoverySectionState extends State<PluginDiscoverySection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PluginCubit>().ensureDiscoveryLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PluginDiscoveryBody(
      state: widget.state,
      installed: widget.state.installed,
      onGoMarketplaces: widget.onGoMarketplaces,
    );
  }
}

class PluginDiscoveryBody extends StatefulWidget {
  const PluginDiscoveryBody({
    super.key,
    required this.state,
    required this.installed,
    required this.onGoMarketplaces,
  });

  final PluginState state;
  final List<Plugin> installed;
  final VoidCallback onGoMarketplaces;

  @override
  State<PluginDiscoveryBody> createState() => PluginDiscoveryBodyState();
}

class PluginDiscoveryBodyState extends State<PluginDiscoveryBody> {
  String? _marketplaceFilter;
  String _statusFilter = 'all';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<DiscoverablePlugin> _filtered() {
    return widget.state.discoverable.where((d) {
      if (_marketplaceFilter != null) {
        final full = '${d.marketplaceOwner}/${d.marketplaceName}';
        if (full != _marketplaceFilter) {
          return false;
        }
      }
      switch (_statusFilter) {
        case 'installed':
          if (!d.isInstalledAmong(widget.installed)) {
            return false;
          }
        case 'uninstalled':
          if (d.isInstalledAmong(widget.installed)) {
            return false;
          }
      }
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q.isNotEmpty) {
        if (!d.name.toLowerCase().contains(q) &&
            !d.description.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<PluginCubit>();
    final marketplaces = widget.state.marketplaces;

    if (marketplaces.isEmpty) {
      return SingleChildScrollView(
        child: PluginManagementCard(
          child: PluginEmptyBlock(
            icon: Icons.store_outlined,
            title: l10n.pluginsMarketplacesEmpty,
            hint: l10n.pluginsNoInstalledHint,
            actionLabel: l10n.pluginsGoDiscovery,
            onAction: widget.onGoMarketplaces,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PluginManagementCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: l10n.pluginsSearchPlaceholder,
                        prefixIcon: const Icon(Icons.search, size: AppIconSizes.md),
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: l10n.pluginsCheckUpdates,
                    onPressed: widget.state.discoveryLoading
                        ? null
                        : () => cubit.ensureDiscoveryLoaded(force: true),
                    icon:
                        widget.state.discoveryLoading ||
                            widget.state.marketplaceSyncingKeys.isNotEmpty
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: AppIconSizes.md),
                  ),
                ],
              ),
              if (widget.state.marketplaceSyncingKeys.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.pluginsDiscoverySyncing,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  PluginMarketplaceDropdown(
                    marketplaces: marketplaces,
                    value: _marketplaceFilter,
                    l10n: l10n,
                    onChanged: (v) => setState(() => _marketplaceFilter = v),
                  ),
                  PluginStatusDropdown(
                    value: _statusFilter,
                    l10n: l10n,
                    onChanged: (v) =>
                        setState(() => _statusFilter = v ?? 'all'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(child: _buildDiscoveryList(context, l10n)),
      ],
    );
  }

  Widget _buildDiscoveryList(BuildContext context, AppLocalizations l10n) {
    if (widget.state.discoveryLoading && widget.state.discoverable.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filtered();
    if (!widget.state.discoveryLoading && filtered.isEmpty) {
      return SingleChildScrollView(
        child: PluginManagementCard(
          child: PluginEmptyBlock(
            icon: Icons.travel_explore_outlined,
            title: l10n.pluginsDiscoveryEmpty,
            hint: '',
            actionLabel: l10n.pluginsGoDiscovery,
            onAction: widget.onGoMarketplaces,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final d = filtered[index];
        return PluginDiscoverableCard(
          plugin: d,
          installed: d.isInstalledAmong(widget.installed),
          busy: widget.state.busyIds.contains(d.key),
        );
      },
    );
  }
}

class PluginMarketplaceDropdown extends StatelessWidget {
  const PluginMarketplaceDropdown({
    super.key,
    required this.marketplaces,
    required this.value,
    required this.l10n,
    required this.onChanged,
  });

  final List<PluginMarketplace> marketplaces;
  final String? value;
  final AppLocalizations l10n;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final allLabel = l10n.pluginsFilterMarketplaceAll;
    final labels = <String, String>{
      '': allLabel,
      for (final m in marketplaces.where((m) => m.enabled))
        m.fullName: m.displayName ?? m.fullName,
    };
    final keys = labels.keys.toList();
    return AppDropdownField<String>(
      items: keys,
      itemLabel: (k) => labels[k] ?? k,
      initialItem: value ?? '',
      onChanged: (v) => onChanged(v == '' ? null : v),
    );
  }
}

class PluginStatusDropdown extends StatelessWidget {
  const PluginStatusDropdown({
    super.key,
    required this.value,
    required this.l10n,
    required this.onChanged,
  });

  final String value;
  final AppLocalizations l10n;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = <String, String>{
      'all': l10n.pluginsFilterAll,
      'installed': l10n.pluginsFilterInstalled,
      'uninstalled': l10n.pluginsFilterUninstalled,
    };
    final keys = labels.keys.toList();
    return AppDropdownField<String>(
      items: keys,
      itemLabel: (k) => labels[k] ?? k,
      initialItem: value,
      onChanged: onChanged,
    );
  }
}

class PluginDiscoverableCard extends StatelessWidget {
  const PluginDiscoverableCard({
    super.key,
    required this.plugin,
    required this.installed,
    required this.busy,
  });

  final DiscoverablePlugin plugin;
  final bool installed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<PluginCubit>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);

    return PluginManagementCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        plugin.name,
                        style: AppTextStyles.of(
                          context,
                        ).bodyStrong.copyWith(color: textBase),
                      ),
                    ),
                    if (plugin.version.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        'v${plugin.version}',
                        style: AppTextStyles.of(context).caption.copyWith(
                          color: textBase.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ],
                ),
                if (plugin.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    plugin.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.of(context).bodySmall.copyWith(
                      color: textBase.withValues(alpha: 0.55),
                    ),
                  ),
                ],
                if (plugin.marketplaceFullName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    plugin.marketplaceFullName,
                    style: AppTextStyles.of(
                      context,
                    ).caption.copyWith(color: textBase.withValues(alpha: 0.35)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (busy)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GithubDetailsButton(
                  url: plugin.githubBrowseUrl,
                  label: l10n.pluginsCardDetails,
                ),
                if (installed)
                  OutlinedButton(
                    onPressed: null,
                    child: Text(l10n.pluginsCardInstalled),
                  )
                else
                  FilledButton.tonal(
                    onPressed: plugin.canInstall
                        ? () => cubit.installFromDiscovery(plugin)
                        : null,
                    child: Text(l10n.pluginsCardInstall),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
