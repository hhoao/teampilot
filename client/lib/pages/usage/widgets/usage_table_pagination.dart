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
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  key: AppKeys.sessionUsagePageSize,
                  value: pageSize,
                  isDense: true,
                  borderRadius: BorderRadius.circular(8),
                  style: styles.md.copyWith(color: cs.onSurface),
                  items: [
                    for (final size in pageSizeOptions)
                      DropdownMenuItem(value: size, child: Text('$size')),
                  ],
                  onChanged: (value) {
                    if (value != null) onPageSizeChanged(value);
                  },
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
