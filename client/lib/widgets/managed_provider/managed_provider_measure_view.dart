import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../models/managed_provider.dart';
import '../../models/provider_usage_snapshot.dart';

/// Presents a cached Managed Provider usage result without performing any I/O.
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

  @override
  Widget build(BuildContext context) {
    final current = snapshot;
    final status = current?.status;
    final error = current?.lastErrorMessage;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                current == null
                    ? 'No usage queried yet'
                    : _statusLabel(status!),
                style: TpTextStyles.of(context).smColored(
                  status == ProviderUsageStatus.error
                      ? cs.error
                      : cs.onSurfaceVariant,
                ),
              ),
            ),
            if (status == ProviderUsageStatus.stale)
              const TpStatusBadge(
                label: 'Stale',
                icon: Icons.schedule_outlined,
                tone: TpStatusBadgeTone.warning,
              ),
            if (status == ProviderUsageStatus.error)
              const TpStatusBadge(
                label: 'Error',
                icon: Icons.error_outline,
                tone: TpStatusBadgeTone.warning,
              ),
            if (onRefresh != null)
              IconButton(
                key: const Key('managed-provider-test-query'),
                tooltip: 'Test query',
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
        if (status == ProviderUsageStatus.error)
          Container(
            key: const Key('managed-provider-query-error'),
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              error?.trim().isNotEmpty == true
                  ? error!
                  : 'Unable to query provider usage.',
              style: TpTextStyles.of(context).smColored(cs.onErrorContainer),
            ),
          ),
        if (current != null && current.measures.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final measure in current.measures)
                  _MeasureChip(
                    measure: measure,
                    display: provider.displayConfig,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  static String _statusLabel(ProviderUsageStatus status) => switch (status) {
    ProviderUsageStatus.ready => 'Cached usage',
    ProviderUsageStatus.stale => 'Cached usage · needs refresh',
    ProviderUsageStatus.error => 'Last query failed',
    ProviderUsageStatus.loading => 'Loading usage',
    ProviderUsageStatus.unsupported => 'Query unsupported',
    ProviderUsageStatus.unknown => 'Unknown usage status',
  };
}

class _MeasureChip extends StatelessWidget {
  const _MeasureChip({required this.measure, required this.display});

  final ProviderUsageMeasure measure;
  final ManagedProviderDisplayConfig display;

  @override
  Widget build(BuildContext context) {
    var value = measure.remaining ?? measure.used ?? measure.total ?? '—';
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        suffix.isEmpty ? value : '$value $suffix',
        style: TpTextStyles.of(context).mdSemibold,
      ),
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
