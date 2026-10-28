import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/cursor_usage_range.dart';
import '../../../utils/ui/app_keys.dart';

class CursorUsageRangePicker extends StatelessWidget {
  const CursorUsageRangePicker({
    required this.range,
    required this.onChanged,
    super.key,
  });

  final CursorUsageRange range;
  final ValueChanged<CursorUsageRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final selected = switch (range) {
      CursorUsagePresetRange(:final preset) => preset,
      CursorUsageCustomRange() => null,
    };

    return Wrap(
      key: AppKeys.cursorUsageRangePicker,
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final preset in CursorUsagePreset.values)
          ChoiceChip(
            label: Text(_label(context, preset), style: styles.xs),
            selected: selected == preset,
            onSelected: (_) => onChanged(CursorUsagePresetRange(preset)),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range_outlined, size: 16),
          label: Text(
            range is CursorUsageCustomRange
                ? l10n.cursorUsageRangeCustomActive
                : l10n.cursorUsageRangeCustom,
            style: styles.xs,
          ),
          onPressed: () async {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2024),
              lastDate: DateTime.now(),
              initialDateRange: range is CursorUsageCustomRange
                  ? DateTimeRange(
                      start: DateTime.fromMillisecondsSinceEpoch(
                        (range as CursorUsageCustomRange).startMs,
                      ),
                      end: DateTime.fromMillisecondsSinceEpoch(
                        (range as CursorUsageCustomRange).endMs,
                      ),
                    )
                  : null,
            );
            if (picked == null) return;
            onChanged(
              CursorUsageCustomRange(
                startMs: DateTime(
                  picked.start.year,
                  picked.start.month,
                  picked.start.day,
                ).millisecondsSinceEpoch,
                endMs:
                    DateTime(
                      picked.end.year,
                      picked.end.month,
                      picked.end.day,
                    ).add(const Duration(days: 1)).millisecondsSinceEpoch -
                    1,
              ),
            );
          },
        ),
      ],
    );
  }

  String _label(BuildContext context, CursorUsagePreset preset) {
    final l10n = context.l10n;
    return switch (preset) {
      CursorUsagePreset.billingCycle => l10n.cursorUsageRangeCycle,
      CursorUsagePreset.today => l10n.cursorUsageRangeToday,
      CursorUsagePreset.sevenDays => l10n.cursorUsageRangeSevenDays,
      CursorUsagePreset.thirtyDays => l10n.cursorUsageRangeThirtyDays,
      CursorUsagePreset.lastMonth => l10n.cursorUsageRangeLastMonth,
    };
  }
}
