
import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/plugin_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/plugin.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_dialog.dart';
import '../../utils/skill_repo_parse.dart';
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.pluginsNavMarketplaces,
                        style: AppTextStyles.of(
                          context,
                        ).sectionTitle.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _onAdd(context, cubit),
                      icon: Icon(Icons.add, size: context.appIconSizes.md),
                      label: Text(l10n.pluginsMarketplaceAdd),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (state.marketplaces.isEmpty)
                  PluginEmptyBlock(
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

class _AddPluginMarketplaceDialogState extends State<_AddPluginMarketplaceDialog> {
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
    return AppDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(
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
          AppDialogActions(
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
                        style: AppTextStyles.of(
                          context,
                        ).bodyStrong.copyWith(color: textBase),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  marketplace.githubUrl,
                  style: AppTextStyles.of(
                    context,
                  ).caption.copyWith(color: textBase.withValues(alpha: 0.4)),
                ),
                Text(
                  'branch: ${marketplace.branch}',
                  style: AppTextStyles.of(
                    context,
                  ).caption.copyWith(color: textBase.withValues(alpha: 0.35)),
                ),
              ],
            ),
          ),
          Switch(
            value: marketplace.enabled,
            onChanged: (v) => cubit.toggleMarketplaceEnabled(marketplace, v),
          ),
          IconButton(
            icon: Icon(Icons.open_in_new, size: context.appIconSizes.md),
            tooltip: marketplace.githubUrl,
            onPressed: () => openPluginUrl(marketplace.githubUrl),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: context.appIconSizes.md),
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
