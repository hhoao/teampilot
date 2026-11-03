import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../utils/ui/app_keys.dart';

class UsageTablePagination extends StatelessWidget {
  const UsageTablePagination({
    required this.page,
    required this.pageCount,
    required this.start,
    required this.end,
    required this.total,
    required this.pageSize,
    required this.pageSizeOptions,
    required this.onPageSizeChanged,
    required this.onPrev,
    required this.onNext,
    super.key,
  });

  final int page;
  final int pageCount;
  final int start;
  final int end;
  final int total;
  final int pageSize;
  final List<int> pageSizeOptions;
  final ValueChanged<int> onPageSizeChanged;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final muted = styles.md.copyWith(
      color: cs.onSurface.withValues(alpha: 0.56),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          Text(
            l10n.sessionUsagePageRange(start + 1, end, total),
            key: AppKeys.sessionUsagePageRange,
            style: muted,
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 2,
            children: [
              Text(l10n.sessionUsageRowsPerPage, style: muted),
              TpActionMenuButton(
                minWidth: 88,
                specs: [
                  for (final size in pageSizeOptions)
                    TpActionMenuSpec.item(
                      value: size,
                      label: '$size',
                      selected: size == pageSize,
                    ),
                ],
                onSelected: (value) {
                  if (value is int) onPageSizeChanged(value);
                },
                triggerBuilder: (context, controller) => InkWell(
                  key: AppKeys.sessionUsagePageSize,
                  onTap: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$pageSize',
                          style: styles.md.copyWith(color: cs.onSurface),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          size: context.tpIconSizes.md,
                          color: cs.onSurface.withValues(alpha: 0.56),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                key: AppKeys.sessionUsagePrevPage,
                tooltip: l10n.sessionUsagePrevPage,
                onPressed: onPrev,
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(l10n.sessionUsagePageOf(page + 1, pageCount), style: muted),
              IconButton(
                key: AppKeys.sessionUsageNextPage,
                tooltip: l10n.sessionUsageNextPage,
                onPressed: onNext,
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
