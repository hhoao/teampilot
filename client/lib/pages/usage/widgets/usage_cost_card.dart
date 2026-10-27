import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../../../utils/ui/app_keys.dart';
import '../usage_format.dart';

class UsageCostCard extends StatelessWidget {
  const UsageCostCard({
    required this.summary,
    required this.onManagePricing,
    this.corrupted = false,
    super.key,
  });

  final UsageSummary summary;
  final VoidCallback onManagePricing;
  final bool corrupted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final hasPriced = summary.pricedEvents > 0;
    final cost = hasPriced ? summary.costMicroUsd : null;
    final details = <String>[
      l10n.sessionUsageCostPricedUnpriced(
        summary.pricedEvents,
        summary.unpricedEvents,
      ),
      if (summary.unpricedEvents > 0)
        l10n.sessionUsageCostPartial(summary.unpricedEvents),
      if (corrupted) l10n.sessionUsagePricingCorrupt,
    ];

    return Container(
      key: AppKeys.sessionUsageCostCard,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: workspaceCardDecoration(
        cs,
        radius: 14,
      ).copyWith(color: cs.workspaceCard),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF0F9D58).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.payments_outlined,
              size: 20,
              color: Color(0xFF0F9D58),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.sessionUsageCost, style: styles.xs),
                const SizedBox(height: 2),
                Text(
                  hasPriced
                      ? formatUsageCost(cost)
                      : l10n.sessionUsageCostUnpriced,
                  style: styles.xl.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  details.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: styles.xs.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.56),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            key: AppKeys.sessionUsageManagePricingButton,
            onPressed: onManagePricing,
            icon: const Icon(Icons.tune, size: 17),
            label: Text(l10n.sessionUsageManagePricing),
          ),
        ],
      ),
    );
  }
}
