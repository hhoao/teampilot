import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../models/managed_provider.dart';
import '../../models/provider_usage_snapshot.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/managed_provider/managed_provider_measure_view.dart';

class ManagedProviderList extends StatelessWidget {
  const ManagedProviderList({
    required this.providers,
    required this.snapshots,
    required this.isRefreshing,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onRefresh,
    super.key,
  });

  final List<ManagedProvider> providers;
  final Map<String, ProviderUsageSnapshot> snapshots;
  final bool Function(String providerId) isRefreshing;
  final ValueChanged<ManagedProvider> onEdit;
  final ValueChanged<ManagedProvider> onToggle;
  final ValueChanged<ManagedProvider> onDelete;
  final ValueChanged<ManagedProvider> onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (providers.isEmpty) {
      return TpEmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: l10n.managedProvidersEmptyTitle,
        hint: l10n.managedProvidersEmptyHint,
      );
    }

    return ListView.separated(
      key: const Key('managed-provider-list'),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: providers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final provider = providers[index];
        final snapshot = snapshots[provider.id];
        final cs = Theme.of(context).colorScheme;
        return Container(
          key: Key('managed-provider-${provider.id}'),
          padding: const EdgeInsets.all(14),
          decoration: workspaceInsetDecoration(cs, radius: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: cs.primary.withValues(alpha: 0.12),
                    child: Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 18,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => onEdit(provider),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            provider.name,
                            style: TpTextStyles.of(context).mdBold,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${provider.kind.value} · ${provider.adapterId}',
                            style: TpTextStyles.of(
                              context,
                            ).smColored(cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Flexible(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 2,
                      runSpacing: 2,
                      children: [
                        TpStatusBadge(
                          label: provider.enabled
                              ? l10n.managedProvidersEnabled
                              : l10n.managedProvidersDisabled,
                          tone: provider.enabled
                              ? TpStatusBadgeTone.success
                              : TpStatusBadgeTone.neutral,
                        ),
                        IconButton(
                          tooltip: provider.enabled
                              ? l10n.managedProvidersDisable
                              : l10n.managedProvidersEnable,
                          onPressed: () => onToggle(provider),
                          icon: Icon(
                            provider.enabled
                                ? Icons.pause_circle_outline
                                : Icons.play_circle_outline,
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.managedProvidersEdit,
                          onPressed: () => onEdit(provider),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: l10n.managedProvidersDelete,
                          onPressed: () => onDelete(provider),
                          icon: Icon(Icons.delete_outline, color: cs.error),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ManagedProviderMeasureView(
                provider: provider,
                snapshot: snapshot,
                refreshing: isRefreshing(provider.id),
                onRefresh: () => onRefresh(provider),
              ),
            ],
          ),
        );
      },
    );
  }
}
