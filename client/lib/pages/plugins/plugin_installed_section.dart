import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/plugin_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/plugin.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/github_source_url.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/github_details_button.dart';
import '../../widgets/plugins/plugin_cli_support_disclosure.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import '../../widgets/empty_state_block.dart';
import 'plugin_management_cards.dart';

class PluginInstalledSection extends StatelessWidget {
  const PluginInstalledSection({super.key, required this.state, required this.onGoDiscovery});
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
          PluginManagementCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PluginCardHeader(
                  title: l10n.pluginsInstalledCount(state.installed.length),
                  trailing: CardHeaderActionRow(
                    children: [
                      if (state.updates.isNotEmpty)
                        FilledButton.tonalIcon(
                          onPressed: state.toolbarBusy
                              ? null
                              : throttledOnPressed(
                                  'plugin_update_all',
                                  cubit.updateAll,
                                ),
                          icon: Icon(Icons.upgrade, size: context.appIconSizes.md),
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
                        icon: Icon(Icons.folder_open_outlined, size: context.appIconSizes.md),
                        label: Text(l10n.pluginsImportFromDisk),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.toolbarBusy
                            ? null
                            : throttledAsync(
                                'plugin_install_zip',
                                () => _onInstallZip(context),
                              ),
                        icon: Icon(Icons.archive_outlined, size: context.appIconSizes.md),
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
                            : Icon(Icons.refresh, size: context.appIconSizes.md),
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
                  EmptyStateBlock(
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
                        PluginInstalledRow(
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
      showPluginSnack(context, l10n.pluginsImportNothing);
      return;
    }
    final selected = await showDialog<List<UnmanagedPlugin>>(
      context: context,
      builder: (_) => PluginImportUnmanagedDialog(plugins: scanned),
    );
    if (selected == null || selected.isEmpty) return;
    if (!context.mounted) return;
    await context.read<PluginCubit>().importUnmanaged(selected);
  }
}

class PluginImportUnmanagedDialog extends StatefulWidget {
  const PluginImportUnmanagedDialog({super.key, required this.plugins});
  final List<UnmanagedPlugin> plugins;

  @override
  State<PluginImportUnmanagedDialog> createState() =>
      PluginImportUnmanagedDialogState();
}

class PluginImportUnmanagedDialogState extends State<PluginImportUnmanagedDialog> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.plugins.map((p) => p.directory).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppDialog(
      maxWidth: 560,
      maxHeight: 600,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.pluginsImportTitle),
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
          AppDialogActions(
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
    );
  }
}

class PluginInstalledRow extends StatelessWidget {
  const PluginInstalledRow({super.key, 
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
    final cs = Theme.of(context).colorScheme;
    final textBase = cs.onSurface;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.of(context).bodySmall.copyWith(
                      color: textBase.withValues(alpha: 0.55),
                    ),
                  ),
                ],
                PluginCliSupportDisclosure(
                  capabilities: plugin.capabilities,
                ),
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
                icon: Icon(Icons.upgrade, size: context.appIconSizes.md),
                label: Text(l10n.pluginsCardUpdate),
              ),
            TextButton.icon(
              onPressed: () => _uninstall(context, plugin, l10n, cubit),
              icon: Icon(Icons.delete_outline, size: context.appIconSizes.md),
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
    final teams = context.read<LaunchProfileCubit>().state.teams;
    final impacted = teams
        .where((t) => t.pluginIds.contains(plugin.id))
        .toList();
    final ok = await pluginConfirmDialog(
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
