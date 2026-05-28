import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cubits/plugin_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/plugin.dart';
import '../services/app/platform_utils.dart';
import '../utils/app_keys.dart';
import '../utils/debounce/debounce.dart';
import '../utils/github_source_url.dart';
import '../utils/skill_repo_parse.dart';
import '../widgets/github_details_button.dart';
import '../widgets/dropdown/flashsky_dropdown_field.dart';
import '../widgets/settings/workspace_hub_shell.dart';
import '../theme/app_text_styles.dart';
import '../theme/workspace_surface_layers.dart';

enum PluginSection { installed, discovery, marketplaces }

extension PluginSectionRoute on PluginSection {
  String routeSegment() => name;

  String title(AppLocalizations l10n) => switch (this) {
    PluginSection.installed => l10n.pluginsNavInstalled,
    PluginSection.discovery => l10n.pluginsNavDiscovery,
    PluginSection.marketplaces => l10n.pluginsNavMarketplaces,
  };
}

class PluginManagementHubPage extends StatelessWidget {
  const PluginManagementHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WorkspaceHubPage(
      pageKey: AppKeys.pluginsHub,
      title: l10n.pluginsTitle,
      subtitle: l10n.pluginsSubtitle,
      entries: [
        for (final section in PluginSection.values)
          WorkspaceHubEntry(
            title: section.title(l10n),
            icon: _pluginSectionIcon(section),
            onTap: throttledTap(
              'plugin_hub_${section.name}',
              () => context.push('/plugins/${section.routeSegment()}'),
            ),
          ),
      ],
    );
  }
}

IconData _pluginSectionIcon(PluginSection section) => switch (section) {
  PluginSection.installed => Icons.extension_outlined,
  PluginSection.discovery => Icons.travel_explore_outlined,
  PluginSection.marketplaces => Icons.store_outlined,
};

class PluginManagementPage extends StatelessWidget {
  const PluginManagementPage({required this.section, super.key});

  final PluginSection section;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return BlocConsumer<PluginCubit, PluginState>(
      listenWhen: (a, b) =>
          a.errorMessage != b.errorMessage && b.errorMessage != null,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.errorMessage!),
            duration: const Duration(seconds: 4),
          ),
        );
        context.read<PluginCubit>().clearError();
      },
      builder: (context, state) {
        final body = switch (section) {
          PluginSection.installed => _InstalledSection(
            state: state,
            onGoDiscovery: () => _goSection(context, PluginSection.discovery),
          ),
          PluginSection.discovery => _DiscoverySection(
            state: state,
            onGoMarketplaces: () =>
                _goSection(context, PluginSection.marketplaces),
          ),
          PluginSection.marketplaces => _MarketplacesSection(state: state),
        };

        if (useAndroidHubNavigation(context)) {
          return WorkspaceSectionPage(
            pageKey: AppKeys.pluginsWorkspace,
            child: body,
          );
        }

        return Container(
          color: cs.workspacePage,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WorkspaceHubTitleBar(
                title: l10n.pluginsTitle,
                subtitle: l10n.pluginsSubtitle,
              ),
              Expanded(
                child: WorkspaceSplitShell(
                  bodyAnimationKey: ValueKey('plugins-body-${section.name}'),
                  nav: _PluginNavPanel(
                    section: section,
                    l10n: l10n,
                    onSelect: (s) => _goSection(context, s),
                  ),
                  body: body,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _goSection(BuildContext context, PluginSection target) {
    if (useAndroidHubNavigation(context)) {
      context.push('/plugins/${target.routeSegment()}');
    } else {
      context.go('/plugins/${target.routeSegment()}');
    }
  }
}

class _PluginNavPanel extends StatelessWidget {
  const _PluginNavPanel({
    required this.section,
    required this.l10n,
    required this.onSelect,
  });

  final PluginSection section;
  final AppLocalizations l10n;
  final ValueChanged<PluginSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return WorkspaceHubNavList(
      sidebarStyle: true,
      entries: [
        for (final value in PluginSection.values)
          WorkspaceHubEntry(
            title: value.title(l10n),
            icon: _pluginSectionIcon(value),
            selected: section == value,
            onTap: throttledTap(
              'plugin_nav_${value.name}',
              () => onSelect(value),
            ),
          ),
      ],
    );
  }
}

class _PluginCard extends StatelessWidget {
  const _PluginCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: workspaceCardDecoration(cs, radius: 12),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.of(context).sectionTitle.copyWith(
              fontWeight: FontWeight.w800,
              color: textBase,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

Future<bool> _pluginConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  List<String>? detailLines,
  String? detailHeading,
}) async {
  final l10n = context.l10n;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          if (detailLines != null && detailLines.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (detailHeading != null)
              Text(
                detailHeading,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            for (final line in detailLines)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $line'),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void _showPluginSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
  );
}

Future<void> _openPluginUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ============================================================================
// Installed section
// ============================================================================

class _InstalledSection extends StatelessWidget {
  const _InstalledSection({required this.state, required this.onGoDiscovery});
  final PluginState state;
  final VoidCallback onGoDiscovery;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<PluginCubit>();
    final updates = {for (final u in state.updates) u.id: u};

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PluginCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CardHeader(
                  title: l10n.pluginsInstalledCount(state.installed.length),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      if (state.updates.isNotEmpty)
                        FilledButton.tonalIcon(
                          onPressed: state.toolbarBusy
                              ? null
                              : throttledOnPressed(
                                  'plugin_update_all',
                                  cubit.updateAll,
                                ),
                          icon: const Icon(Icons.upgrade, size: 16),
                          label: Text(
                            l10n.pluginsUpdateAll(state.updates.length),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: state.toolbarBusy
                            ? null
                            : throttledAsync(
                                'plugin_import_disk',
                                () => _onImportFromDisk(context),
                              ),
                        icon: const Icon(Icons.folder_open_outlined, size: 16),
                        label: Text(l10n.pluginsImportFromDisk),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.toolbarBusy
                            ? null
                            : throttledAsync(
                                'plugin_install_zip',
                                () => _onInstallZip(context),
                              ),
                        icon: const Icon(Icons.archive_outlined, size: 16),
                        label: Text(l10n.pluginsInstallFromZip),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.toolbarBusy || state.updatesLoading
                            ? null
                            : throttledOnPressed(
                                'plugin_check_updates',
                                cubit.checkUpdates,
                              ),
                        icon: state.updatesLoading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh, size: 16),
                        label: Text(
                          state.updatesLoading
                              ? l10n.pluginsCheckingUpdates
                              : l10n.pluginsCheckUpdates,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (state.installed.isEmpty)
                  _EmptyPluginBlock(
                    icon: Icons.extension_outlined,
                    title: l10n.pluginsNoInstalled,
                    hint: l10n.pluginsNoInstalledHint,
                    actionLabel: l10n.pluginsGoDiscovery,
                    onAction: onGoDiscovery,
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final p in state.installed)
                        _InstalledPluginRow(
                          plugin: p,
                          updateInfo: updates[p.id],
                          busy: state.busyIds.contains(p.id),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onInstallZip(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    if (!context.mounted) return;
    await context.read<PluginCubit>().installFromZip(File(path));
  }

  Future<void> _onImportFromDisk(BuildContext context) async {
    final cubit = context.read<PluginCubit>();
    final l10n = context.l10n;
    final scanned = await cubit.scanUnmanaged();
    if (!context.mounted) return;
    if (scanned.isEmpty) {
      _showPluginSnack(context, l10n.pluginsImportNothing);
      return;
    }
    final selected = await showDialog<List<UnmanagedPlugin>>(
      context: context,
      builder: (_) => _ImportUnmanagedPluginsDialog(plugins: scanned),
    );
    if (selected == null || selected.isEmpty) return;
    if (!context.mounted) return;
    await context.read<PluginCubit>().importUnmanaged(selected);
  }
}

class _ImportUnmanagedPluginsDialog extends StatefulWidget {
  const _ImportUnmanagedPluginsDialog({required this.plugins});
  final List<UnmanagedPlugin> plugins;

  @override
  State<_ImportUnmanagedPluginsDialog> createState() =>
      _ImportUnmanagedPluginsDialogState();
}

class _ImportUnmanagedPluginsDialogState
    extends State<_ImportUnmanagedPluginsDialog> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.plugins.map((p) => p.directory).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.pluginsImportTitle,
                style: AppTextStyles.of(context).body.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.plugins.length,
                  itemBuilder: (context, i) {
                    final plugin = widget.plugins[i];
                    final checked = _selected.contains(plugin.directory);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (v) {
                        setState(() {
                          if (v ?? false) {
                            _selected.add(plugin.directory);
                          } else {
                            _selected.remove(plugin.directory);
                          }
                        });
                      },
                      title: Text(plugin.name),
                      subtitle: Text(
                        plugin.description ?? plugin.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton(
                    onPressed: () {
                      final selected = widget.plugins
                          .where((p) => _selected.contains(p.directory))
                          .toList(growable: false);
                      Navigator.of(context).pop(selected);
                    },
                    child: Text(l10n.pluginsImportFromDisk),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPluginBlock extends StatelessWidget {
  const _EmptyPluginBlock({
    required this.icon,
    required this.title,
    required this.hint,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String hint;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Column(
      children: [
        const SizedBox(height: 10),
        Icon(icon, size: 40, color: cs.primary.withValues(alpha: 0.6)),
        const SizedBox(height: 12),
        Text(
          title,
          style: AppTextStyles.of(context).subtitle.copyWith(
            fontWeight: FontWeight.w700,
            color: textBase,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: AppTextStyles.of(context).body.copyWith(
            color: textBase.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _InstalledPluginRow extends StatelessWidget {
  const _InstalledPluginRow({
    required this.plugin,
    this.updateInfo,
    this.busy = false,
  });

  final Plugin plugin;
  final PluginUpdateInfo? updateInfo;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<PluginCubit>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
      ),
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
                        style: AppTextStyles.of(context).bodyStrong.copyWith(
                          color: textBase,
                        ),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.of(context).bodySmall.copyWith(
                      color: textBase.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            GithubDetailsButton(
              url: plugin.githubBrowseUrl,
              label: l10n.pluginsCardDetails,
            ),
            if (updateInfo != null)
              TextButton.icon(
                onPressed: () => cubit.updatePlugin(plugin),
                icon: const Icon(Icons.upgrade, size: 16),
                label: Text(l10n.pluginsCardUpdate),
              ),
            TextButton.icon(
              onPressed: () => _uninstall(context, plugin, l10n, cubit),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: Text(l10n.pluginsCardUninstall),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _uninstall(
    BuildContext context,
    Plugin plugin,
    AppLocalizations l10n,
    PluginCubit cubit,
  ) async {
    final teams = context.read<TeamCubit>().state.teams;
    final impacted = teams
        .where((t) => t.pluginIds.contains(plugin.id))
        .toList();
    final ok = await _pluginConfirm(
      context,
      title: plugin.name,
      message: l10n.pluginsUninstallConfirm(plugin.name, impacted.length),
      detailHeading: impacted.isNotEmpty
          ? l10n.pluginsUninstallImpactList
          : null,
      detailLines: impacted.map((t) => t.name).toList(growable: false),
      confirmLabel: l10n.pluginsCardUninstall,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await cubit.uninstall(plugin);
  }
}

// ============================================================================
// Discovery section
// ============================================================================

class _DiscoverySection extends StatefulWidget {
  const _DiscoverySection({
    required this.state,
    required this.onGoMarketplaces,
  });
  final PluginState state;
  final VoidCallback onGoMarketplaces;

  @override
  State<_DiscoverySection> createState() => _DiscoverySectionState();
}

class _DiscoverySectionState extends State<_DiscoverySection> {
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
    return _DiscoveryBody(
      state: widget.state,
      installed: widget.state.installed,
      onGoMarketplaces: widget.onGoMarketplaces,
    );
  }
}

class _DiscoveryBody extends StatefulWidget {
  const _DiscoveryBody({
    required this.state,
    required this.installed,
    required this.onGoMarketplaces,
  });

  final PluginState state;
  final List<Plugin> installed;
  final VoidCallback onGoMarketplaces;

  @override
  State<_DiscoveryBody> createState() => _DiscoveryBodyState();
}

class _DiscoveryBodyState extends State<_DiscoveryBody> {
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
        child: _PluginCard(
          child: _EmptyPluginBlock(
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
        _PluginCard(
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
                        prefixIcon: const Icon(Icons.search, size: 18),
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
                        : const Icon(Icons.refresh, size: 18),
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
                  _MarketplaceDropdown(
                    marketplaces: marketplaces,
                    value: _marketplaceFilter,
                    l10n: l10n,
                    onChanged: (v) => setState(() => _marketplaceFilter = v),
                  ),
                  _StatusDropdown(
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
        child: _PluginCard(
          child: _EmptyPluginBlock(
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
        return _DiscoverablePluginCard(
          plugin: d,
          installed: d.isInstalledAmong(widget.installed),
          busy: widget.state.busyIds.contains(d.key),
        );
      },
    );
  }
}

class _MarketplaceDropdown extends StatelessWidget {
  const _MarketplaceDropdown({
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
    return FlashskyDropdownField<String>(
      items: keys,
      itemLabel: (k) => labels[k] ?? k,
      initialItem: value ?? '',
      onChanged: (v) => onChanged(v == '' ? null : v),
    );
  }
}

class _StatusDropdown extends StatelessWidget {
  const _StatusDropdown({
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
    return FlashskyDropdownField<String>(
      items: keys,
      itemLabel: (k) => labels[k] ?? k,
      initialItem: value,
      onChanged: onChanged,
    );
  }
}

class _DiscoverablePluginCard extends StatelessWidget {
  const _DiscoverablePluginCard({
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

    return _PluginCard(
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
                        style: AppTextStyles.of(context).bodyStrong.copyWith(
                          color: textBase,
                        ),
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
                    style: AppTextStyles.of(context).caption.copyWith(
                      color: textBase.withValues(alpha: 0.35),
                    ),
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

// ============================================================================
// Marketplaces section
// ============================================================================

class _MarketplacesSection extends StatelessWidget {
  const _MarketplacesSection({required this.state});
  final PluginState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<PluginCubit>();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PluginCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.pluginsNavMarketplaces,
                        style: AppTextStyles.of(context).sectionTitle.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _onAdd(context, cubit),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(l10n.pluginsMarketplaceAdd),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (state.marketplaces.isEmpty)
                  _EmptyPluginBlock(
                    icon: Icons.store_outlined,
                    title: l10n.pluginsMarketplacesEmpty,
                    hint: l10n.pluginsNoInstalledHint,
                    actionLabel: l10n.pluginsMarketplaceAdd,
                    onAction: () {},
                  )
                else
                  Column(
                    children: [
                      for (final m in state.marketplaces)
                        _MarketplaceRow(marketplace: m),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onAdd(BuildContext context, PluginCubit cubit) async {
    final l10n = context.l10n;
    final urlCtrl = TextEditingController();
    final branchCtrl = TextEditingController(text: 'main');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.pluginsMarketplaceAdd),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlCtrl,
              decoration: InputDecoration(
                hintText: l10n.pluginsMarketplaceUrlHint,
                labelText: l10n.pluginsMarketplaceUrl,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: branchCtrl,
              decoration: InputDecoration(
                labelText: l10n.pluginsMarketplaceBranch,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.pluginsMarketplaceAdd),
          ),
        ],
      ),
    );

    if (result != true) return;
    final parsed = parseGithubRepoUrl(urlCtrl.text.trim());
    if (parsed == null) {
      if (context.mounted) {
        _showPluginSnack(context, l10n.pluginsMarketplaceInvalidUrl);
      }
      return;
    }
    if (!context.mounted) return;
    await cubit.addMarketplace(
      PluginMarketplace(
        owner: parsed.owner,
        name: parsed.name,
        branch: branchCtrl.text.trim().isNotEmpty
            ? branchCtrl.text.trim()
            : 'main',
      ),
    );
  }
}

class _MarketplaceRow extends StatelessWidget {
  const _MarketplaceRow({required this.marketplace});
  final PluginMarketplace marketplace;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<PluginCubit>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
      ),
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
                        marketplace.displayName ?? marketplace.fullName,
                        style: AppTextStyles.of(context).bodyStrong.copyWith(
                          color: textBase,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  marketplace.githubUrl,
                    style: AppTextStyles.of(context).caption.copyWith(
                      color: textBase.withValues(alpha: 0.4),
                    ),
                ),
                Text(
                  'branch: ${marketplace.branch}',
                  style: AppTextStyles.of(context).caption.copyWith(
                    color: textBase.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: marketplace.enabled,
            onChanged: (v) => cubit.toggleMarketplaceEnabled(marketplace, v),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new, size: 18),
            tooltip: marketplace.githubUrl,
            onPressed: () => _openPluginUrl(marketplace.githubUrl),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: l10n.pluginsMarketplaceRemove,
            onPressed: () => _remove(context, l10n, cubit),
          ),
        ],
      ),
    );
  }

  Future<void> _remove(
    BuildContext context,
    AppLocalizations l10n,
    PluginCubit cubit,
  ) async {
    final ok = await _pluginConfirm(
      context,
      title: l10n.pluginsMarketplaceRemove,
      message: l10n.pluginsMarketplaceRemoveConfirm(marketplace.githubUrl),
      confirmLabel: l10n.pluginsMarketplaceRemove,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await cubit.removeMarketplace(marketplace.owner, marketplace.name);
  }
}
