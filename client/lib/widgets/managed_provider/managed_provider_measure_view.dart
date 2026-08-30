import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/managed_provider.dart';
import '../../models/provider_usage_snapshot.dart';
import '../../utils/managed_provider_error_localization.dart';
import '../../services/provider_usage/adapters/official_subscription_parse.dart';

/// Formats and presents cached Managed Provider usage without performing I/O.
class ManagedProviderMeasureView extends StatelessWidget {
  const ManagedProviderMeasureView({
    required this.provider,
    this.snapshot,
    this.refreshing = false,
    this.onRefresh,
    super.key,
  });

  final ManagedProvider provider;
  final ProviderUsageSnapshot? snapshot;
  final bool refreshing;
  final VoidCallback? onRefresh;

  static String? primaryMeasureLabel(
    ProviderUsageSnapshot? snapshot,
    ManagedProviderDisplayConfig display,
  ) {
    final measure = snapshot?.measures.firstOrNull;
    if (measure == null) return null;
    return formatMeasure(measure, display);
  }

  static String formatMeasure(
    ProviderUsageMeasure measure,
    ManagedProviderDisplayConfig display,
  ) {
    var value = measure.remaining ?? measure.used ?? measure.total ?? '—';
    if (value != '—' && _isPercentMeasure(measure)) {
      final parsed = double.tryParse(value);
      if (parsed != null) {
        value = formatOfficialPercent(parsed);
      }
    }
    final decimalPlaces = display.decimalPlaces;
    if (decimalPlaces != null && value != '—') {
      value = _formatDecimal(value, decimalPlaces);
    }
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

  static bool _isPercentMeasure(ProviderUsageMeasure measure) {
    final unit = measure.unit?.trim().toLowerCase();
    return unit == '%' || unit == 'percent' || unit == 'percentage';
  }

  static String statusLabel(AppLocalizations l10n, ProviderUsageStatus? status) {
    if (status == null) return l10n.managedProvidersNoUsage;
    return switch (status) {
      ProviderUsageStatus.ready => l10n.managedProvidersCachedUsage,
      ProviderUsageStatus.stale => l10n.managedProvidersCachedUsage,
      ProviderUsageStatus.error => l10n.managedProvidersLastQueryFailed,
      ProviderUsageStatus.loading => l10n.managedProvidersLoadingUsage,
      ProviderUsageStatus.unsupported => l10n.managedProvidersQueryUnsupported,
      ProviderUsageStatus.unknown => l10n.managedProvidersUnknownUsage,
    };
  }

  @override
  Widget build(BuildContext context) {
    final current = snapshot;
    final status = current?.status;
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final usage = primaryMeasureLabel(current, provider.displayConfig);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                usage ?? statusLabel(l10n, status),
                style: TpTextStyles.of(context).smColored(
                  status == ProviderUsageStatus.error
                      ? cs.error
                      : cs.onSurfaceVariant,
                ),
              ),
            ),
            if (status == ProviderUsageStatus.error)
              TpStatusBadge(
                label: l10n.managedProvidersError,
                icon: Icons.error_outline,
                tone: TpStatusBadgeTone.warning,
              ),
            if (onRefresh != null)
              IconButton(
                key: const Key('managed-provider-test-query'),
                tooltip: l10n.managedProvidersTestQuery,
                onPressed: refreshing ? null : onRefresh,
                icon: refreshing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_outlined),
              ),
          ],
        ),
        if (status == ProviderUsageStatus.error &&
            current?.lastErrorMessage?.trim().isNotEmpty == true)
          Padding(
            key: const Key('managed-provider-query-error'),
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              managedProviderSnapshotErrorMessage(l10n, current!),
              style: TpTextStyles.of(context).smColored(cs.error),
            ),
          ),
        if (current != null && current.measures.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final measure in current.measures.skip(1))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      formatMeasure(measure, provider.displayConfig),
                      style: TpTextStyles.of(context).smSemibold,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

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
