import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/automation.dart';
import '../../services/automation/automation_schedule_calculator.dart';
import '../../services/automation/automation_schedule_defaults.dart';
import 'package:shared_ui/shared_ui.dart';
import 'automation_schedule_picker.dart';

/// Date + time rows for [AutomationScheduleMode.once].
class AutomationScheduleOnceRows extends StatelessWidget {
  const AutomationScheduleOnceRows({
    required this.draft,
    required this.labelWidth,
    required this.onChanged,
    super.key,
  });

  final AutomationScheduleDraft draft;
  final double labelWidth;
  final ValueChanged<AutomationScheduleDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpFormField<DateTime>(
          key: ValueKey(
            'schedule-once-date-${formatAutomationScheduleDate(draft.onceDate ?? now)}',
          ),
          id: 'scheduleOnceDate',
          initialValue: draft.onceDate ?? now,
          label: Text(l10n.automationsScheduleDate),
          layoutStyle: TpFormFieldLayoutStyle.inline,
          labelWidth: labelWidth,
          builder: (state) {
            final selected = state.value ?? draft.onceDate ?? now;
            return TpDatePicker(
              key: const ValueKey('schedule-once-date-picker'),
              firstDate: DateTime(now.year, now.month, now.day),
              lastDate: now.add(const Duration(days: 365)),
              selected: selected,
              onChanged: (date) {
                if (date == null) return;
                state.didChange(date);
                onChanged(draft.copyWith(onceDate: date));
              },
              triggerBuilder: (context, isOpen) => _DateFieldTrigger(
                label: formatAutomationScheduleDate(selected),
                isOpen: isOpen,
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        TpFormField<TimeOfDay>(
          id: 'scheduleOnceTime',
          initialValue: draft.onceTime ?? TimeOfDay(hour: 9, minute: 0),
          label: Text(l10n.automationsTime),
          layoutStyle: TpFormFieldLayoutStyle.inline,
          labelWidth: labelWidth,
          builder: (state) {
            return TpTimePicker(
              initialValue: state.value ?? draft.onceTime,
              onChanged: (time) {
                state.didChange(time);
                onChanged(draft.copyWith(onceTime: time));
              },
            );
          },
        ),
      ],
    );
  }
}

/// Duration select with preset options and custom minutes for
/// [AutomationScheduleMode.countdown].
class AutomationScheduleCountdownRows extends StatelessWidget {
  const AutomationScheduleCountdownRows({
    required this.draft,
    required this.labelWidth,
    required this.onChanged,
    super.key,
  });

  final AutomationScheduleDraft draft;
  final double labelWidth;
  final ValueChanged<AutomationScheduleDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final draft = this.draft;
    final minutes = draft.countdownMinutes ?? 15;
    final selectValue = countdownDelayLabel(l10n, minutes);
    final presetItems = kCountdownQuickPickMinutes
        .map((m) => countdownDelayLabel(l10n, m))
        .toList();
    final runAt = DateTime.fromMillisecondsSinceEpoch(
      countdownToRunAtMs(durationMinutes: minutes, now: DateTime.now()),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpFormField<String>(
          id: 'scheduleCountdownMinutes',
          initialValue: selectValue,
          label: Text(l10n.automationsTime),
          layoutStyle: TpFormFieldLayoutStyle.inline,
          labelWidth: labelWidth,
          builder: (state) {
            return TpSelectWithCustomInput(
              value: selectValue,
              items: presetItems,
              hintText: l10n.automationsTime,
              decoration: TpSelectDecorations.themed(context),
              searchable: false,
              customInputTooltip: l10n.automationsCountdownCustom,
              cancelLabel: l10n.cancel,
              confirmLabel: l10n.confirm,
              onChanged: (value) {
                state.didChange(value);
                final parsed = parseCountdownMinutesSelectValue(l10n, value);
                if (parsed == null) return;
                onChanged(draft.copyWith(countdownMinutes: parsed));
              },
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          l10n.automationsCountdownPreview(
            formatAutomationScheduleDateTime(runAt),
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Preset select + per-preset rows for [AutomationScheduleMode.recurring].
/// `once` is intentionally absent from the select — it is the once mode.
class AutomationScheduleRecurringRows extends StatefulWidget {
  const AutomationScheduleRecurringRows({
    required this.draft,
    required this.labelWidth,
    required this.onChanged,
    required this.calculator,
    super.key,
  });

  final AutomationScheduleDraft draft;
  final double labelWidth;
  final ValueChanged<AutomationScheduleDraft> onChanged;
  final AutomationScheduleCalculator calculator;

  @override
  State<AutomationScheduleRecurringRows> createState() =>
      _AutomationScheduleRecurringRowsState();
}

class _AutomationScheduleRecurringRowsState
    extends State<AutomationScheduleRecurringRows> {
  late final TextEditingController _customCronCtl;

  @override
  void initState() {
    super.initState();
    _customCronCtl = TextEditingController(text: widget.draft.customCron ?? '');
  }

  @override
  void didUpdateWidget(covariant AutomationScheduleRecurringRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    final cron = widget.draft.customCron;
    // Only resync when the draft itself changed: the emitted cron is trimmed,
    // so echoing back on every rebuild would eat spaces the user is typing.
    if (oldWidget.draft.customCron != widget.draft.customCron &&
        _customCronCtl.text != (cron ?? '')) {
      _customCronCtl.text = cron ?? '';
    }
  }

  @override
  void dispose() {
    _customCronCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final draft = widget.draft;
    final presets = AutomationSchedulePreset.values
        .where((p) => p != AutomationSchedulePreset.once)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpFormField<AutomationSchedulePreset>(
          key: ValueKey('schedule-preset-${draft.preset.name}'),
          id: 'schedulePreset',
          initialValue: draft.preset,
          label: Text(l10n.automationsSchedule),
          layoutStyle: TpFormFieldLayoutStyle.inline,
          labelWidth: widget.labelWidth,
          builder: (state) {
            return TpSelect<AutomationSchedulePreset>(
              items: presets,
              initialItem: state.value ?? draft.preset,
              decoration: TpSelectDecorations.themed(context),
              itemLabel: (p) => schedulePresetLabel(context.l10n, p),
              onChanged: (value) {
                if (value == null) return;
                state.didChange(value);
                widget.onChanged(
                  draft.copyWith(
                    preset: value,
                    clearDayOfWeek: value != AutomationSchedulePreset.weekly,
                    clearCustomCron: value != AutomationSchedulePreset.custom,
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 12),
        switch (draft.preset) {
          AutomationSchedulePreset.hourly => TpFormField<int>(
            id: 'scheduleMinute',
            initialValue: draft.minute,
            label: Text(l10n.automationsTime),
            layoutStyle: TpFormFieldLayoutStyle.inline,
            labelWidth: widget.labelWidth,
            builder: (state) {
              return TpSelect<int>(
                items: List<int>.generate(60, (i) => i),
                initialItem: (state.value ?? draft.minute).clamp(0, 59),
                decoration: TpSelectDecorations.themed(context),
                itemLabel: (m) => l10n.automationsScheduleSummaryHourly(m),
                onChanged: (value) {
                  if (value == null) return;
                  state.didChange(value);
                  widget.onChanged(draft.copyWith(minute: value));
                },
              );
            },
          ),
          AutomationSchedulePreset.custom => TpFormField<String>(
            id: 'scheduleCustomCron',
            initialValue: draft.customCron ?? '',
            label: Text(l10n.automationsCustomCron),
            layoutStyle: TpFormFieldLayoutStyle.inline,
            labelWidth: widget.labelWidth,
            validator: (value) {
              final cron = value?.trim() ?? '';
              if (!widget.calculator.isValidCron(cron)) {
                return l10n.automationsInvalidCron;
              }
              return null;
            },
            builder: (state) {
              return TextField(
                controller: _customCronCtl,
                focusNode: state.focusNode,
                onChanged: (value) {
                  state.didChange(value);
                  widget.onChanged(draft.copyWith(customCron: value.trim()));
                },
                decoration: InputDecoration(
                  hintText: '0 */2 * * *',
                  errorText: state.hasError ? '' : null,
                  errorStyle: const TextStyle(height: 0, fontSize: 0),
                ),
              );
            },
          ),
          _ => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpFormField<String>(
                id: 'scheduleHourMinute',
                initialValue: draft.hourMinute,
                label: Text(l10n.automationsTime),
                layoutStyle: TpFormFieldLayoutStyle.inline,
                labelWidth: widget.labelWidth,
                validator: (value) {
                  try {
                    parseHourMinute(value ?? '');
                    return null;
                  } on Object {
                    return l10n.automationsInvalidTime;
                  }
                },
                builder: (state) {
                  final (hour, minute) = _parseHourMinute(
                    state.value ?? draft.hourMinute,
                  );
                  return TpTimePicker(
                    initialValue: TimeOfDay(hour: hour, minute: minute),
                    onChanged: (time) {
                      final formatted = formatHourMinute(time);
                      state.didChange(formatted);
                      widget.onChanged(draft.copyWith(hourMinute: formatted));
                    },
                  );
                },
              ),
              if (draft.preset == AutomationSchedulePreset.weekly) ...[
                const SizedBox(height: 12),
                TpFormField<int>(
                  id: 'scheduleDayOfWeek',
                  initialValue: draft.dayOfWeek ?? DateTime.monday,
                  label: Text(l10n.automationsScheduleWeekly),
                  layoutStyle: TpFormFieldLayoutStyle.inline,
                  labelWidth: widget.labelWidth,
                  builder: (state) {
                    return TpSelect<int>(
                      items: const [
                        DateTime.monday,
                        DateTime.tuesday,
                        DateTime.wednesday,
                        DateTime.thursday,
                        DateTime.friday,
                        DateTime.saturday,
                        DateTime.sunday,
                      ],
                      initialItem:
                          state.value ?? draft.dayOfWeek ?? DateTime.monday,
                      decoration: TpSelectDecorations.themed(context),
                      itemLabel: (d) => dayOfWeekScheduleLabel(context.l10n, d),
                      onChanged: (value) {
                        if (value == null) return;
                        state.didChange(value);
                        widget.onChanged(draft.copyWith(dayOfWeek: value));
                      },
                    );
                  },
                ),
              ],
            ],
          ),
        },
      ],
    );
  }

  (int, int) _parseHourMinute(String raw) {
    try {
      return parseHourMinute(raw);
    } on Object {
      // TpTimePicker always emits valid HH:mm; guard stale drafts anyway.
      return (9, 0);
    }
  }
}

/// Bordered, field-styled trigger for the once-mode [TpDatePicker] so the row
/// reads like the other inline form controls.
class _DateFieldTrigger extends StatelessWidget {
  const _DateFieldTrigger({required this.label, required this.isOpen});

  final String label;
  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(context.tpTheme.control.radius),
        border: Border.all(
          color: isOpen ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: context.tpIconSizes.md,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(label, style: TpTextStyles.of(context).md),
        ],
      ),
    );
  }
}
