import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/managed_provider_cubit.dart';
import '../../cubits/managed_provider_usage_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/managed_provider.dart';
import '../../models/provider_usage_snapshot.dart';
import '../../utils/managed_provider_error_localization.dart';
import 'managed_provider_brand_icon.dart';

/// Cached Managed Provider usage popover content.
///
/// This widget only reads Cubit state. Refresh and navigation are explicit
/// callbacks, so opening the panel never starts a query or performs I/O.
class ManagedProviderUsagePanel extends StatelessWidget {
  const ManagedProviderUsagePanel({this.onManage, this.onRefresh, super.key});

  static const double panelWidth = 360;

  final VoidCallback? onManage;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ManagedProviderCubit, ManagedProviderState>(
      buildWhen: (previous, next) =>
          previous.providers != next.providers ||
          previous.status != next.status,
      builder: (context, providerState) {
        return BlocBuilder<
          ManagedProviderUsageCubit,
          ManagedProviderUsageState
        >(
          buildWhen: (previous, next) =>
              previous.snapshots != next.snapshots ||
              previous.status != next.status ||
              previous.isRefreshing != next.isRefreshing,
          builder: (context, usageState) {
            final providers = providerState.enabledProviders;
            final l10n = context.l10n;
            final refreshing = usageState.isRefreshing;
            final refresh =
                onRefresh ??
                () => context.read<ManagedProviderUsageCubit>().refreshAll();

            return SizedBox(
              key: const Key('managed-provider-usage-panel'),
              width: panelWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PanelHeader(
                      refreshing: refreshing,
                      onRefresh: refresh,
                      onManage: onManage,
                    ),
                    if (usageState.status ==
                            ManagedProviderUsageLoadStatus.loading &&
                        usageState.snapshots.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: LinearProgressIndicator(
                          key: const Key('managed-provider-usage-loading'),
                          minHeight: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    if (providers.isEmpty)
                      _EmptyState(
                        onManage: onManage,
                        noneEnabled: providerState.providers.isNotEmpty,
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          children: [
                            for (final provider in providers)
                              _ProviderUsageRow(
                                provider: provider,
                                snapshot: usageState.snapshotFor(provider.id),
                                onTap: onManage,
                              ),
                          ],
                        ),
                      ),
                    if (usageState.status ==
                            ManagedProviderUsageLoadStatus.error &&
                        providers.isNotEmpty)
                      Padding(
                        key: const Key('managed-provider-usage-global-error'),
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          usageState.errorMessage ??
                              l10n.managedProvidersQueryFailed,
                          style: TpTextStyles.of(context).xs.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.refreshing,
    required this.onRefresh,
    required this.onManage,
  });

  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Row(
      children: [
        Icon(
          Icons.account_balance_wallet_outlined,
          size: 15,
          color: cs.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            l10n.managedProvidersTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.xs.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        TpIconButton(
          key: const Key('managed-provider-usage-refresh'),
          icon: Icons.refresh,
          tooltip: l10n.managedProvidersRetry,
          size: 28,
          iconSize: 15,
          compact: true,
          color: cs.onSurfaceVariant,
          enabled: !refreshing,
          onTap: onRefresh,
        ),
        TpIconButton(
          key: const Key('managed-provider-usage-manage'),
          icon: Icons.settings_outlined,
          tooltip: l10n.managedProvidersNav,
          size: 28,
          iconSize: 15,
          compact: true,
          color: cs.onSurfaceVariant,
          enabled: onManage != null,
          onTap: onManage,
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onManage, this.noneEnabled = false});

  final VoidCallback? onManage;
  final bool noneEnabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    return Padding(
      key: const Key('managed-provider-usage-empty'),
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            noneEnabled
                ? l10n.managedProvidersNoneEnabledTitle
                : l10n.managedProvidersEmptyTitle,
            style: styles.smSemibold,
          ),
          const SizedBox(height: 4),
          Text(
            noneEnabled
                ? l10n.managedProvidersNoneEnabledHint
                : l10n.managedProvidersEmptyHint,
            style: styles.xs.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (onManage != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TpButton(
                  key: const Key('managed-provider-usage-empty-manage'),
                  variant: TpButtonVariant.outline,
                  onPressed: onManage,
                  child: Text(
                    noneEnabled
                        ? l10n.managedProvidersNav
                        : l10n.managedProvidersAdd,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProviderUsageRow extends StatelessWidget {
  const _ProviderUsageRow({
    required this.provider,
    required this.snapshot,
    required this.onTap,
  });

  final ManagedProvider provider;
  final ProviderUsageSnapshot? snapshot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;
    final status = snapshot?.status;
    final warning =
        status == ProviderUsageStatus.stale ||
        status == ProviderUsageStatus.error ||
        status == ProviderUsageStatus.unsupported;
    final value = _primaryMeasure(snapshot, provider.displayConfig);
    final statusText = _statusText(context, status);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Semantics(
            button: onTap != null,
            label: provider.name,
            child: TpHover(
              key: Key('managed-provider-usage-row-${provider.id}'),
              onTap: onTap,
              enabled: onTap != null,
              hoverColor: cs.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(7),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KeyedSubtree(
                    key: Key('managed-provider-brand-${provider.id}'),
                    child: ManagedProviderBrandMark(
                      provider: provider,
                      size: 15,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: styles.smSemibold,
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            Text(
                              value ?? statusText,
                              style: styles.xs.copyWith(
                                color: warning
                                    ? cs.error
                                    : cs.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            if (warning)
                              Icon(
                                Icons.warning_amber_rounded,
                                key: const Key(
                                  'managed-provider-usage-warning',
                                ),
                                size: 13,
                                color: cs.error,
                              ),
                            if (snapshot?.fetchedAt != null)
                              Text(
                                _timeLabel(context, snapshot!.fetchedAt!),
                                style: styles.xs.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                        if (snapshot?.measures.isNotEmpty == true &&
                            snapshot!.measures.first.resetsAt != null)
                          Text(
                            _resetLabel(
                              context,
                              snapshot!.measures.first.resetsAt!,
                            ),
                            style: styles.xs.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        if (status == ProviderUsageStatus.error &&
                            snapshot?.lastErrorMessage?.trim().isNotEmpty ==
                                true)
                          Text(
                            managedProviderSnapshotErrorMessage(
                              context.l10n,
                              snapshot!,
                            ),
                            key: const Key('managed-provider-usage-error'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: styles.xs.copyWith(color: cs.error),
                          ),
                      ],
                    ),
                  ),
                  if (snapshot?.measures.isNotEmpty == true)
                    _ProgressIndicator(measure: snapshot!.measures.first),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: TpIconButton(
            key: Key('managed-provider-usage-enabled-${provider.id}'),
            icon: Icons.pause_circle_outline,
            tooltip: l10n.managedProvidersDisable,
            size: 28,
            iconSize: 15,
            compact: true,
            color: cs.onSurfaceVariant,
            onTap: () =>
                context.read<ManagedProviderCubit>().disable(provider.id),
          ),
        ),
      ],
    );
  }

  static String? _primaryMeasure(
    ProviderUsageSnapshot? snapshot,
    ManagedProviderDisplayConfig display,
  ) {
    final measure = snapshot?.measures.firstOrNull;
    if (measure == null) return null;
    var value = measure.remaining ?? measure.used ?? measure.total ?? '—';
    final places = display.decimalPlaces;
    if (places != null && value != '—') value = _formatDecimal(value, places);
    final suffix = [
      if (measure.currency?.trim().isNotEmpty == true) measure.currency!,
      if (measure.unit?.trim().isNotEmpty == true) measure.unit!,
      if (display.showPercent &&
          measure.currency?.trim().isNotEmpty != true &&
          measure.unit?.trim().isNotEmpty != true)
        '%',
    ].join(' ');
    return suffix.isEmpty ? value : '$value $suffix';
  }

  static String _statusText(BuildContext context, ProviderUsageStatus? status) {
    final l10n = context.l10n;
    return switch (status) {
      ProviderUsageStatus.ready => l10n.managedProvidersCachedUsage,
      ProviderUsageStatus.stale => l10n.managedProvidersCachedUsageStale,
      ProviderUsageStatus.error => l10n.managedProvidersLastQueryFailed,
      ProviderUsageStatus.loading => l10n.managedProvidersLoadingUsage,
      ProviderUsageStatus.unsupported => l10n.managedProvidersQueryUnsupported,
      ProviderUsageStatus.unknown || null => l10n.managedProvidersNoUsage,
    };
  }

  static String _timeLabel(BuildContext context, int milliseconds) {
    final time = TimeOfDay.fromDateTime(
      DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal(),
    );
    return time.format(context);
  }

  static String _resetLabel(BuildContext context, int milliseconds) =>
      '↻ ${_timeLabel(context, milliseconds)}';

  static String _formatDecimal(String value, int places) {
    if (places < 0) return value;
    final negative = value.startsWith('-');
    final unsigned = negative ? value.substring(1) : value;
    final parts = unsigned.split('.');
    final whole = parts.first;
    final fraction = parts.length > 1 ? parts[1] : '';
    final normalized = places == 0
        ? whole
        : '$whole.${fraction.padRight(places, '0').substring(0, places)}';
    return negative ? '-$normalized' : normalized;
  }
}

class _ProgressIndicator extends StatelessWidget {
  const _ProgressIndicator({required this.measure});

  final ProviderUsageMeasure measure;

  @override
  Widget build(BuildContext context) {
    final total = double.tryParse(measure.total ?? '');
    final used = double.tryParse(measure.used ?? '');
    if (total == null || used == null || total <= 0) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      key: const Key('managed-provider-usage-progress'),
      width: 42,
      child: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: LinearProgressIndicator(
          minHeight: 3,
          value: (used / total).clamp(0.0, 1.0),
        ),
      ),
    );
  }
}
