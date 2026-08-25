import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/managed_provider.dart';
import '../../models/provider_usage_snapshot.dart';
import 'managed_provider_reset_countdown.dart';

/// Compact quota meter: rounded progress bar with remaining % and reset time.
class ManagedProviderQuotaMeter extends StatelessWidget {
  const ManagedProviderQuotaMeter({
    required this.measure,
    required this.display,
    this.resetsAt,
    this.warning = false,
    this.now,
    super.key,
  });

  final ProviderUsageMeasure measure;
  final ManagedProviderDisplayConfig display;
  final int? resetsAt;
  final bool warning;
  final DateTime? now;

  static bool supports(
    ManagedProviderDisplayConfig display,
    ProviderUsageMeasure measure,
  ) {
    if (!_isPercentageMeasure(display, measure)) return false;
    return _remainingFraction(measure) != null;
  }

  static double? _remainingFraction(ProviderUsageMeasure measure) {
    final remaining = double.tryParse(measure.remaining ?? '');
    final total = double.tryParse(measure.total ?? '');
    final used = double.tryParse(measure.used ?? '');
    if (remaining != null) {
      if (total != null && total > 0) {
        return (remaining / total).clamp(0.0, 1.0);
      }
      if (remaining >= 0 && remaining <= 100) {
        return (remaining / 100).clamp(0.0, 1.0);
      }
    }
    if (total != null && total > 0 && used != null) {
      return ((total - used) / total).clamp(0.0, 1.0);
    }
    return null;
  }

  static bool _isPercentageMeasure(
    ManagedProviderDisplayConfig display,
    ProviderUsageMeasure measure,
  ) {
    final unit = measure.unit?.trim().toLowerCase();
    if (unit == '%' || unit == 'percent' || unit == 'percentage') {
      return true;
    }
    return display.showPercent && measure.currency?.trim().isNotEmpty != true;
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

  static String _remainingLabel(
    ProviderUsageMeasure measure,
    ManagedProviderDisplayConfig display,
    AppLocalizations l10n,
  ) {
    var value = measure.remaining ?? measure.used ?? measure.total ?? '—';
    final places = display.decimalPlaces;
    if (places != null && value != '—') {
      value = _formatDecimal(value, places);
    }
    return l10n.managedProvidersRemainingPercent(value);
  }

  @override
  Widget build(BuildContext context) {
    final fraction = _remainingFraction(measure);
    if (fraction == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final remainingLabel = _remainingLabel(measure, display, context.l10n);
    final barColor = warning
        ? cs.error
        : fraction <= 0.35
        ? cs.tertiary
        : const Color(0xFF2EA043);

    return Column(
      key: const Key('managed-provider-quota-meter'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 4,
            child: LinearProgressIndicator(
              key: const Key('managed-provider-usage-progress'),
              value: fraction,
              minHeight: 4,
              backgroundColor: cs.onSurface.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: Text(
                remainingLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.xs.copyWith(
                  color: warning ? cs.error : cs.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (resetsAt != null) ...[
              const SizedBox(width: 8),
              ManagedProviderResetCountdownLabel(
                resetsAt: resetsAt,
                now: now,
                style: styles.xs.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.72),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            if (warning)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.warning_amber_rounded,
                  key: const Key('managed-provider-usage-warning'),
                  size: 13,
                  color: cs.error,
                ),
              ),
          ],
        ),
      ],
    );
  }

}
