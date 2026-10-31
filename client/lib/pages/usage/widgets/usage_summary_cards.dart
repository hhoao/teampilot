import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../usage_format.dart';

class UsageSummaryCards extends StatefulWidget {
  const UsageSummaryCards({
    required this.dashboard,
    required this.nowMs,
    super.key,
  });

  final UsageDashboard dashboard;
  final int nowMs;

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
    final total = summary.totalTokens;

    final cards = <Widget>[
      _MetricCard(
        title: l10n.sessionUsageTotalTokens,
        value: formatUsageTokens(summary.totalTokens),
        icon: Icons.data_usage_outlined,
        accent: const Color(0xFFD97757),
        details: [
          l10n.sessionUsageRequestsSessions(summary.requests, summary.sessions),
        ],
      ),
      _MetricCard(
        title: l10n.sessionUsageInputTokens,
        value: formatUsageTokens(summary.freshInputTokens),
        icon: Icons.south_east_outlined,
        accent: const Color(0xFF6366F1),
        details: [
          l10n.sessionUsageShare(
            formatUsageShare(summary.freshInputTokens, total),
          ),
        ],
      ),
      _MetricCard(
        title: l10n.sessionUsageOutputTokens,
        value: formatUsageTokens(summary.outputTokens),
        icon: Icons.north_east_outlined,
        accent: const Color(0xFF10A37F),
        details: [
          l10n.sessionUsageShare(formatUsageShare(summary.outputTokens, total)),
        ],
      ),
      _MetricCard(
        title: l10n.sessionUsageCacheRead,
        value: formatUsageTokens(summary.cacheReadTokens),
        icon: Icons.bolt_outlined,
        accent: const Color(0xFFF59E0B),
        details: [
          l10n.sessionUsageCacheHit(formatUsagePercent(summary.cacheHitRate)),
          l10n.sessionUsageCacheWrite(
            formatUsageTokens(summary.cacheCreationTokens),
          ),
        ],
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
        final cardWidth = columns == 1
            ? width
            : (width - gap * (columns - 1)) / columns;

        Widget grid(List<Widget> children, {required bool intrinsic}) {
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
                                    minHeight: 132,
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
            grid(cards, intrinsic: true),
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
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: grid(details, intrinsic: false),
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
    required this.details,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accent;
  final List<String> details;

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
          const Spacer(),
          for (final detail in details)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.xs.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
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
