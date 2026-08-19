import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../models/managed_provider.dart';
import '../../models/provider_usage_snapshot.dart';
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
    if (providers.isEmpty) {
      return const TpEmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'No managed providers',
        hint:
            'Add a provider to track balances and quotas independently from CLI providers.',
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
              _ProviderHeader(
                provider: provider,
                colorScheme: cs,
                onEdit: onEdit,
                onToggle: onToggle,
                onDelete: onDelete,
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

class _ProviderHeader extends StatelessWidget {
  const _ProviderHeader({
    required this.provider,
    required this.colorScheme,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final ManagedProvider provider;
  final ColorScheme colorScheme;
  final ValueChanged<ManagedProvider> onEdit;
  final ValueChanged<ManagedProvider> onToggle;
  final ValueChanged<ManagedProvider> onDelete;

  Widget _identity(BuildContext context) => InkWell(
    onTap: () => onEdit(provider),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(provider.name, style: TpTextStyles.of(context).mdBold),
        const SizedBox(height: 2),
        Text(
          '${provider.kind.value} · ${provider.adapterId}',
          style: TpTextStyles.of(
            context,
          ).smColored(colorScheme.onSurfaceVariant),
        ),
      ],
    ),
  );

  Widget _avatar() => CircleAvatar(
    radius: 17,
    backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
    child: Icon(
      Icons.account_balance_wallet_outlined,
      size: 18,
      color: colorScheme.primary,
    ),
  );

  Widget _status() => TpStatusBadge(
    label: provider.enabled ? 'Enabled' : 'Disabled',
    tone: provider.enabled
        ? TpStatusBadgeTone.success
        : TpStatusBadgeTone.neutral,
  );

  Widget _actions() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: provider.enabled ? 'Disable' : 'Enable',
        onPressed: () => onToggle(provider),
        icon: Icon(
          provider.enabled
              ? Icons.pause_circle_outline
              : Icons.play_circle_outline,
        ),
      ),
      IconButton(
        tooltip: 'Edit',
        onPressed: () => onEdit(provider),
        icon: const Icon(Icons.edit_outlined),
      ),
      IconButton(
        tooltip: 'Delete',
        onPressed: () => onDelete(provider),
        icon: Icon(Icons.delete_outline, color: colorScheme.error),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 520;
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _avatar(),
                const SizedBox(width: 10),
                Expanded(child: _identity(context)),
                _status(),
              ],
            ),
            Align(alignment: Alignment.centerRight, child: _actions()),
          ],
        );
      }
      return Row(
        children: [
          _avatar(),
          const SizedBox(width: 10),
          Expanded(child: _identity(context)),
          _status(),
          _actions(),
        ],
      );
    },
  );
}
