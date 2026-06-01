
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/plugin_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/plugin.dart';
import '../../theme/app_text_styles.dart';
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
                      icon: const Icon(Icons.add, size: 16),
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
        showPluginSnack(context, l10n.pluginsMarketplaceInvalidUrl);
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
            icon: const Icon(Icons.open_in_new, size: 18),
            tooltip: marketplace.githubUrl,
            onPressed: () => openPluginUrl(marketplace.githubUrl),
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
