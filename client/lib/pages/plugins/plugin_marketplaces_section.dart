import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/plugin_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/plugin.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/github/skill_repo_parse.dart';
import '../../widgets/catalog/catalog_registry_row_actions.dart';
import 'plugin_management_cards.dart';

class PluginMarketplacesSection extends StatelessWidget {
  const PluginMarketplacesSection({super.key, required this.state});
  final PluginState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<PluginCubit>();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PluginManagementCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TpCardHeader(
                  title: l10n.pluginsNavMarketplaces,
                  trailing: FilledButton.tonalIcon(
                    onPressed: () => _onAdd(context, cubit),
                    icon: Icon(Icons.add, size: context.tpIconSizes.md),
                    label: Text(l10n.pluginsMarketplaceAdd),
                  ),
                ),
                const SizedBox(height: 12),
                if (state.marketplaces.isEmpty)
                  TpEmptyState(
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
                        PluginMarketplaceRow(marketplace: m),
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
    final draft = await showDialog<({String url, String branch})>(
      context: context,
      builder: (ctx) => const _AddPluginMarketplaceDialog(),
    );
    if (draft == null) return;
    final parsed = parseGithubRepoUrl(draft.url.trim());
    if (parsed == null) {
      if (context.mounted) {
        showPluginSnack(context, l10n.pluginsMarketplaceInvalidUrl);
      }
      return;
    }
    if (!context.mounted) return;
    await cubit.addMarketplace(
      PluginMarketplace(
        owner: parsed.owner,
        name: parsed.name,
        branch: draft.branch.trim().isNotEmpty ? draft.branch.trim() : 'main',
      ),
    );
  }
}

class _AddPluginMarketplaceDialog extends StatefulWidget {
  const _AddPluginMarketplaceDialog();

  @override
  State<_AddPluginMarketplaceDialog> createState() =>
      _AddPluginMarketplaceDialogState();
}

class _AddPluginMarketplaceDialogState
    extends State<_AddPluginMarketplaceDialog> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _branchCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController();
    _branchCtrl = TextEditingController(text: 'main');
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _branchCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop((url: _urlCtrl.text, branch: _branchCtrl.text));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: l10n.pluginsMarketplaceAdd,
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 16),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _urlCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.pluginsMarketplaceUrlHint,
                  labelText: l10n.pluginsMarketplaceUrl,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _branchCtrl,
                decoration: InputDecoration(
                  labelText: l10n.pluginsMarketplaceBranch,
                ),
              ),
            ],
          ),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: _submit,
                child: Text(l10n.pluginsMarketplaceAdd),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PluginMarketplaceRow extends StatelessWidget {
  const PluginMarketplaceRow({super.key, required this.marketplace});
  final PluginMarketplace marketplace;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<PluginCubit>();
    final cs = Theme.of(context).colorScheme;
    final textBase = cs.onSurface;
    final title = marketplace.displayName ?? marketplace.fullName;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TpHover(
        backgroundColor: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        onTap: () => _edit(context, cubit),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: workspaceInsetDecoration(cs, radius: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      marketplace.githubUrl,
                      style: TpTextStyles.of(
                        context,
                      ).mdSemiboldColored(textBase),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@$title · ${marketplace.branch}',
                      style: TpTextStyles.of(
                        context,
                      ).xsColored(textBase.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
              ),
              CatalogRegistryEditButton(
                onPressed: () => _edit(context, cubit),
                tooltip: l10n.edit,
              ),
              Switch(
                value: marketplace.enabled,
                onChanged: (v) =>
                    cubit.toggleMarketplaceEnabled(marketplace, v),
              ),
              IconButton(
                icon: Icon(Icons.open_in_new, size: context.tpIconSizes.md),
                tooltip: marketplace.githubUrl,
                onPressed: () => openPluginUrl(marketplace.githubUrl),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: context.tpIconSizes.md,
                  color: cs.error,
                ),
                tooltip: l10n.pluginsMarketplaceRemove,
                onPressed: () => _remove(context, l10n, cubit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, PluginCubit cubit) async {
    final draft = await showDialog<({String branch, String? displayName})>(
      context: context,
      builder: (ctx) => _EditPluginMarketplaceDialog(marketplace: marketplace),
    );
    if (draft == null || !context.mounted) return;
    await cubit.updateMarketplace(
      marketplace.copyWith(
        branch: draft.branch,
        displayName: draft.displayName,
        clearDisplayName:
            draft.displayName == null || draft.displayName!.isEmpty,
      ),
    );
  }

  Future<void> _remove(
    BuildContext context,
    AppLocalizations l10n,
    PluginCubit cubit,
  ) async {
    final ok = await pluginConfirmDialog(
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

class _EditPluginMarketplaceDialog extends StatefulWidget {
  const _EditPluginMarketplaceDialog({required this.marketplace});

  final PluginMarketplace marketplace;

  @override
  State<_EditPluginMarketplaceDialog> createState() =>
      _EditPluginMarketplaceDialogState();
}

class _EditPluginMarketplaceDialogState
    extends State<_EditPluginMarketplaceDialog> {
  late final TextEditingController _branchCtrl;
  late final TextEditingController _displayNameCtrl;

  @override
  void initState() {
    super.initState();
    _branchCtrl = TextEditingController(text: widget.marketplace.branch);
    _displayNameCtrl = TextEditingController(
      text: widget.marketplace.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _branchCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final branch = _branchCtrl.text.trim();
    Navigator.of(context).pop((
      branch: branch.isEmpty ? 'main' : branch,
      displayName: _displayNameCtrl.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: l10n.edit,
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 16),
          Text(
            widget.marketplace.githubUrl,
            style: TpTextStyles.of(context).smColored(
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _displayNameCtrl,
            decoration: InputDecoration(
              labelText: l10n.pluginsMarketplaceDisplayName,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _branchCtrl,
            decoration: InputDecoration(
              labelText: l10n.pluginsMarketplaceBranch,
            ),
          ),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(onPressed: _submit, child: Text(l10n.save)),
            ],
          ),
        ],
      ),
    );
  }
}
