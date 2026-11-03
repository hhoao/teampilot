import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../usage_format.dart';
import 'usage_cost_card.dart';

class UsageSummaryCards extends StatefulWidget {
  const UsageSummaryCards({
    required this.dashboard,
    required this.nowMs,
    this.onManagePricing,
    this.pricingCorrupted = false,
    super.key,
  });

  final UsageDashboard dashboard;
  final int nowMs;
  final VoidCallback? onManagePricing;
  final bool pricingCorrupted;

  @override
  State<UsageSummaryCards> createState() => _UsageSummaryCardsState();
}

class _UsageSummaryCardsState extends State<UsageSummaryCards> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final summary = widget.dashboard.summary;
    final cards = <Widget>[
      _MetricCard(
        title: l10n.sessionUsageTotalTokens,
        value: formatUsageTokens(summary.totalTokens),
        icon: Icons.data_usage_outlined,
        accent: const Color(0xFFD97757),
      ),
      _MetricCard(
        title: l10n.sessionUsageInputTokens,
        value: formatUsageTokens(summary.freshInputTokens),
        icon: Icons.south_east_outlined,
        accent: const Color(0xFF6366F1),
      ),
      _MetricCard(
        title: l10n.sessionUsageOutputTokens,
        value: formatUsageTokens(summary.outputTokens),
        icon: Icons.north_east_outlined,
        accent: const Color(0xFF10A37F),
      ),
      _MetricCard(
        title: l10n.sessionUsageCacheRead,
        value: formatUsageTokens(summary.cacheReadTokens),
        icon: Icons.bolt_outlined,
        accent: const Color(0xFFF59E0B),
      ),
    ];

    final details = <Widget>[
      _DetailTile(
        label: l10n.sessionUsagePricingCacheWrite,
        value: formatUsageTokens(summary.cacheCreationTokens),
      ),
      _DetailTile(
        label: l10n.sessionUsageHeatmapMetricHitRate,
        value: formatUsagePercent(summary.cacheHitRate),
      ),
      _DetailTile(
        label: l10n.sessionUsageRequests,
        value: '${summary.requests}',
      ),
      _DetailTile(
        label: l10n.sessionUsageSessions,
        value: '${summary.sessions}',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 980
            ? 4
            : width >= 520
            ? 2
            : 1;
        const gap = 12.0;
        Widget grid(
          List<Widget> children, {
          required bool intrinsic,
          required int columns,
        }) {
          final cardWidth = columns == 1
              ? width
              : (width - gap * (columns - 1)) / columns;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (
                var start = 0;
                start < children.length;
                start += columns
              ) ...[
                if (start > 0) const SizedBox(height: gap),
                intrinsic
                    ? IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (
                              var index = start;
                              index < start + columns &&
                                  index < children.length;
                              index++
                            ) ...[
                              if (index > start) const SizedBox(width: gap),
                              SizedBox(
                                width: cardWidth,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 108,
                                  ),
                                  child: children[index],
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : Row(
                        children: [
                          for (
                            var index = start;
                            index < start + columns && index < children.length;
                            index++
                          ) ...[
                            if (index > start) const SizedBox(width: gap),
                            SizedBox(width: cardWidth, child: children[index]),
                          ],
                        ],
                      ),
              ],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            grid(cards, intrinsic: true, columns: columns),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 24,
                child: Center(
                  child: Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: context.tpIconSizes.md,
                    color: cs.onSurface.withValues(alpha: 0.56),
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.onManagePricing != null) ...[
                          UsageCostCard(
                            summary: summary,
                            corrupted: widget.pricingCorrupted,
                            onManagePricing: widget.onManagePricing!,
                          ),
                          const SizedBox(height: 8),
                        ],
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: grid(
                            details,
                            intrinsic: false,
                            columns: columns,
                          ),
                        ),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: workspaceCardDecoration(
        cs,
        radius: 14,
      ).copyWith(color: cs.workspaceCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.smMedium.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.66),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.xl.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.md.copyWith(
              color: cs.onSurface.withValues(alpha: 0.56),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.lg,
          ),
        ],
      ),
    );
  }
}
