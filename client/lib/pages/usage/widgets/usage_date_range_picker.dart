import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/session_usage_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../services/usage/usage_aggregator.dart';
import '../../../utils/ui/app_keys.dart';
import '../usage_format.dart';

const _usageRangePresets = <UsageRange>[
  UsageRange.today,
  UsageRange.last24Hours,
  UsageRange.sevenDays,
  UsageRange.fourteenDays,
  UsageRange.thirtyDays,
  UsageRange.all,
];

class UsageDateRangePicker extends StatelessWidget {
  const UsageDateRangePicker({
    required this.state,
    required this.cubit,
    super.key,
  });

  final SessionUsageState state;
  final SessionUsageCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final value = _valueFor(state, now);
    final labels = TpDateTimeRangePickerLabels(
      start: l10n.sessionUsageStartTime,
      end: l10n.sessionUsageEndTime,
      confirm: l10n.confirm,
      cancel: l10n.cancel,
      hint: l10n.sessionUsageRangeHint,
      liveEnd: l10n.sessionUsageLiveEnd,
      invalidOrder: l10n.sessionUsageRangeInvalidOrder,
      tooLong: l10n.sessionUsageRangeTooLong,
    );

    return TpDateTimeRangePicker(
      firstDate: DateTime(2000),
      lastDate: now.add(const Duration(days: 1)),
      value: value,
      maxDuration: const Duration(days: 30),
      labels: labels,
      presets: [
        for (final range in _usageRangePresets)
          TpDateTimeRangePreset(
            id: range.value,
            label: usageRangeLabel(context, range),
          ),
      ],
      selectedPresetId: state.range == UsageRange.custom
          ? null
          : state.range.value,
      onPresetSelected: (id) {
        final range = UsageRange.tryParse(id);
        if (range != null) cubit.setRange(range);
      },
      onChanged: (range) {
        if (range == null) return;
        if (state.range == UsageRange.all &&
            range.start == now.subtract(const Duration(days: 30))) {
          return;
        }
        cubit.setCustomRange(
          startMs: range.start.millisecondsSinceEpoch,
          endMs: range.end.millisecondsSinceEpoch,
          liveEnd: range.liveEnd,
        );
      },
      triggerBuilder: (context, isOpen) =>
          _Trigger(label: _triggerLabel(context, state), open: isOpen),
    );
  }

  TpDateTimeRange? _valueFor(SessionUsageState state, DateTime now) {
    if (state.range == UsageRange.custom &&
        state.customStartMs != null &&
        state.customEndMs != null) {
      return TpDateTimeRange(
        start: DateTime.fromMillisecondsSinceEpoch(state.customStartMs!),
        end: state.liveEnd
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(state.customEndMs!),
        liveEnd: state.liveEnd,
      );
    }

    if (state.range == UsageRange.all || state.range == UsageRange.custom) {
      return TpDateTimeRange(
        start: now.subtract(const Duration(days: 30)),
        end: now,
      );
    }

    final bounds = usageRangeBounds(
      range: state.range,
      nowMs: now.millisecondsSinceEpoch,
    );
    final start = DateTime.fromMillisecondsSinceEpoch(bounds.startMs!);
    return TpDateTimeRange(start: start, end: now, liveEnd: true);
  }

  String _triggerLabel(BuildContext context, SessionUsageState state) {
    if (state.range != UsageRange.custom ||
        state.customStartMs == null ||
        state.customEndMs == null) {
      return usageRangeLabel(context, state.range);
    }
    final formatter = DateFormat('MM/dd HH:mm');
    final start = DateTime.fromMillisecondsSinceEpoch(state.customStartMs!);
    final end = state.liveEnd
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(state.customEndMs!);
    return '${formatter.format(start)} – ${formatter.format(end)}';
  }
}

class _Trigger extends StatelessWidget {
  const _Trigger({required this.label, required this.open});

  final String label;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Container(
        key: AppKeys.sessionUsageRangeTrigger,
        height: usageFilterControlHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: open ? cs.surfaceContainerHighest : cs.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: context.tpIconSizes.md,
              color: cs.onSurface.withValues(alpha: 0.56),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.md,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: context.tpIconSizes.md,
              color: cs.onSurface.withValues(alpha: 0.56),
            ),
          ],
        ),
      ),
    );
  }
}
