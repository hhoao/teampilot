import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/managed_provider_usage_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/managed_provider.dart';
import '../../models/provider_usage_snapshot.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/managed_provider_error_localization.dart';
import '../../widgets/managed_provider/managed_provider_brand_icon.dart';
import '../../widgets/managed_provider/managed_provider_measure_view.dart';

const _cardPadding = EdgeInsets.fromLTRB(16, 12, 12, 12);
const _leadingWidth = 32.0;
const _actionsGap = 8.0;
const _infoMinWidth = 96.0;
const _compactIconActionWidth = 40.0;
const _usageMinWidth = 72.0;
const _usageMaxWidth = 160.0;
const _usageCompactMaxWidth = 72.0;
const _inlineActionsMinWidth = 4 * _compactIconActionWidth + _usageMinWidth;

bool _showsInlineActions(double contentWidth) =>
    contentWidth >=
    _leadingWidth +
        _actionsGap +
        _infoMinWidth +
        _actionsGap +
        _inlineActionsMinWidth;

/// Per-card usage slice. Record value equality keeps a state emit that leaves
/// one provider untouched from rebuilding that provider's card.
typedef _CardUsage = ({ProviderUsageSnapshot? snapshot, bool refreshing});

class ManagedProviderList extends StatelessWidget {
  const ManagedProviderList({
    required this.providers,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onRefresh,
    super.key,
  });

  final List<ManagedProvider> providers;
  final ValueChanged<ManagedProvider> onEdit;
  final ValueChanged<ManagedProvider> onToggle;
  final ValueChanged<ManagedProvider> onDelete;
  final ValueChanged<ManagedProvider> onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (providers.isEmpty) {
      return TpEmptyState(
        centered: true,
        icon: Icons.account_balance_wallet_outlined,
        title: l10n.managedProviders.emptyTitle,
        hint: l10n.managedProviders.emptyHint,
      );
    }

    // Every card has the same width, so resolve the compact layout once here
    // instead of rebuilding each card during layout with its own LayoutBuilder.
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth - _cardPadding.horizontal;
        final showInlineActions = _showsInlineActions(contentWidth);
        final usageMaxWidth = showInlineActions
            ? _usageMaxWidth
            : _usageCompactMaxWidth;

        return ListView.separated(
          key: const Key('managed-provider-list'),
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 24),
          itemCount: providers.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final provider = providers[index];
            return BlocSelector<
              ManagedProviderUsageCubit,
              ManagedProviderUsageState,
              _CardUsage
            >(
              selector: (state) => (
                snapshot: state.snapshotFor(provider.id),
                refreshing: state.isRefreshingProvider(provider.id),
              ),
              builder: (context, selection) => _ManagedProviderCard(
                key: Key('managed-provider-${provider.id}'),
                provider: provider,
                snapshot: selection.snapshot,
                refreshing: selection.refreshing,
                showInlineActions: showInlineActions,
                usageMaxWidth: usageMaxWidth,
                onEdit: onEdit,
                onToggle: onToggle,
                onDelete: onDelete,
                onRefresh: onRefresh,
              ),
            );
          },
        );
      },
    );
  }
}

class _ManagedProviderCard extends StatelessWidget {
  const _ManagedProviderCard({
    super.key,
    required this.provider,
    required this.snapshot,
    required this.refreshing,
    required this.showInlineActions,
    required this.usageMaxWidth,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onRefresh,
  });

  final ManagedProvider provider;
  final ProviderUsageSnapshot? snapshot;
  final bool refreshing;
  final bool showInlineActions;
  final double usageMaxWidth;
  final ValueChanged<ManagedProvider> onEdit;
  final ValueChanged<ManagedProvider> onToggle;
  final ValueChanged<ManagedProvider> onDelete;
  final ValueChanged<ManagedProvider> onRefresh;

  bool get _hasError {
    final message = snapshot?.lastErrorMessage?.trim();
    return snapshot?.status == ProviderUsageStatus.error &&
        message != null &&
        message.isNotEmpty;
  }

  Color _enabledColor(ColorScheme cs) => provider.enabled
      ? const Color(0xFF10B981)
      : cs.onSurfaceVariant.withValues(alpha: 0.45);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final status = snapshot?.status;
    final usageLabel = ManagedProviderMeasureView.primaryMeasureLabel(
      snapshot,
      provider.displayConfig,
    );
    final usageFallback = ManagedProviderMeasureView.statusLabel(l10n, status);
    final warning =
        status == ProviderUsageStatus.error ||
        status == ProviderUsageStatus.unsupported;
    final statusLabel = provider.enabled
        ? l10n.managedProviders.enabled
        : l10n.managedProviders.disabled;

    return Container(
      decoration: workspaceCardDecoration(cs, radius: 12, borderAlpha: 0.5),
      padding: _cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => onEdit(provider),
                  borderRadius: BorderRadius.circular(6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      KeyedSubtree(
                        key: Key('managed-provider-brand-${provider.id}'),
                        child: ManagedProviderBrandMark(
                          provider: provider,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    provider.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: styles.mdSemiboldTightSnug,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _enabledColor(cs),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    statusLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: styles.mutedXs,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${l10n.managedProviderKindLabel(provider.kind)} · ${provider.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: styles.mutedSm,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _UsageTrailing(
                label: usageLabel ?? usageFallback,
                warning: warning,
                maxWidth: usageMaxWidth,
              ),
              const SizedBox(width: 4),
              if (showInlineActions)
                _Actions(
                  provider: provider,
                  refreshing: refreshing,
                  onEdit: onEdit,
                  onToggle: onToggle,
                  onDelete: onDelete,
                  onRefresh: onRefresh,
                )
              else
                _OverflowMenu(
                  provider: provider,
                  refreshing: refreshing,
                  onEdit: onEdit,
                  onToggle: onToggle,
                  onDelete: onDelete,
                  onRefresh: onRefresh,
                ),
            ],
          ),
          if (_hasError) ...[
            const SizedBox(height: 8),
            Text(
              managedProviderSnapshotErrorMessage(l10n, snapshot!),
              key: const Key('managed-provider-query-error'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: styles.smColored(cs.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _UsageTrailing extends StatelessWidget {
  const _UsageTrailing({
    required this.label,
    required this.warning,
    required this.maxWidth,
  });

  final String label;
  final bool warning;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: styles.smSemibold.copyWith(
          color: warning ? cs.error : cs.onSurface,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

enum _ProviderCardAction { refresh, toggle, edit, delete }

class _Actions extends StatelessWidget {
  const _Actions({
    required this.provider,
    required this.refreshing,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onRefresh,
  });

  final ManagedProvider provider;
  final bool refreshing;
  final ValueChanged<ManagedProvider> onEdit;
  final ValueChanged<ManagedProvider> onToggle;
  final ValueChanged<ManagedProvider> onDelete;
  final ValueChanged<ManagedProvider> onRefresh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Row(
      key: Key('managed-provider-actions-${provider.id}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        TpAnimatedIconButton(
          key: const Key('managed-provider-test-query'),
          tooltip: l10n.managedProviders.testQuery,
          icon: Icons.refresh_outlined,
          iconSize: 20,
          compact: true,
          color: cs.onSurfaceVariant,
          busy: refreshing,
          enabled: !refreshing,
          onPressed: () => onRefresh(provider),
        ),
        IconButton(
          tooltip: provider.enabled
              ? l10n.managedProviders.disable
              : l10n.managedProviders.enable,
          onPressed: () => onToggle(provider),
          icon: Icon(
            provider.enabled
                ? Icons.pause_circle_outline
                : Icons.play_circle_outline,
            size: 20,
            color: cs.onSurfaceVariant,
          ),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          tooltip: l10n.managedProviders.edit,
          onPressed: () => onEdit(provider),
          icon: Icon(Icons.edit_outlined, size: 20, color: cs.onSurfaceVariant),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          tooltip: l10n.managedProviders.delete,
          onPressed: () => onDelete(provider),
          icon: Icon(Icons.delete_outline, size: 20, color: cs.error),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.provider,
    required this.refreshing,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onRefresh,
  });

  final ManagedProvider provider;
  final bool refreshing;
  final ValueChanged<ManagedProvider> onEdit;
  final ValueChanged<ManagedProvider> onToggle;
  final ValueChanged<ManagedProvider> onDelete;
  final ValueChanged<ManagedProvider> onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpActionMenuButton(
      key: Key('managed-provider-actions-${provider.id}'),
      tooltip: l10n.log.viewerActionsMenu,
      icon: Icon(Icons.more_vert, size: context.tpIconSizes.sm),
      size: TpIconButton.kCompactSize,
      specs: [
        TpActionMenuSpec.item(
          value: _ProviderCardAction.refresh,
          icon: Icons.refresh_outlined,
          label: l10n.managedProviders.testQuery,
          enabled: !refreshing,
        ),
        TpActionMenuSpec.item(
          value: _ProviderCardAction.toggle,
          icon: provider.enabled
              ? Icons.pause_circle_outline
              : Icons.play_circle_outline,
          label: provider.enabled
              ? l10n.managedProviders.disable
              : l10n.managedProviders.enable,
        ),
        TpActionMenuSpec.item(
          value: _ProviderCardAction.edit,
          icon: Icons.edit_outlined,
          label: l10n.managedProviders.edit,
        ),
        TpActionMenuSpec.item(
          value: _ProviderCardAction.delete,
          icon: Icons.delete_outline,
          label: l10n.managedProviders.delete,
          destructive: true,
        ),
      ],
      onSelected: (value) {
        if (value is! _ProviderCardAction) return;
        switch (value) {
          case _ProviderCardAction.refresh:
            onRefresh(provider);
          case _ProviderCardAction.toggle:
            onToggle(provider);
          case _ProviderCardAction.edit:
            onEdit(provider);
          case _ProviderCardAction.delete:
            onDelete(provider);
        }
      },
    );
  }
}
