import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/automation.dart';
import '../../services/automation/automation_schedule_calculator.dart';
import 'package:shared_ui/shared_ui.dart';

/// Schedule fields edited by [AutomationEditorDialog].
class AutomationScheduleDraft {
  const AutomationScheduleDraft({
    required this.preset,
    required this.minute,
    required this.hourMinute,
    this.dayOfWeek,
    this.customCron,
    required this.timezone,
  });

  final AutomationSchedulePreset preset;
  final int minute;
  final String hourMinute;
  final int? dayOfWeek;
  final String? customCron;
  final String timezone;

  AutomationScheduleDraft copyWith({
    AutomationSchedulePreset? preset,
    int? minute,
    String? hourMinute,
    int? dayOfWeek,
    bool clearDayOfWeek = false,
    String? customCron,
    bool clearCustomCron = false,
    String? timezone,
  }) {
    return AutomationScheduleDraft(
      preset: preset ?? this.preset,
      minute: minute ?? this.minute,
      hourMinute: hourMinute ?? this.hourMinute,
      dayOfWeek: clearDayOfWeek ? null : (dayOfWeek ?? this.dayOfWeek),
      customCron: clearCustomCron ? null : (customCron ?? this.customCron),
      timezone: timezone ?? this.timezone,
    );
  }
}

AutomationScheduleDraft scheduleDraftFromAutomation(Automation automation) {
  return AutomationScheduleDraft(
    preset: automation.preset,
    minute: automation.minute,
    hourMinute: automation.hourMinute,
    dayOfWeek: automation.dayOfWeek,
    customCron: automation.customCron,
    timezone: automation.timezone,
  );
}

String localizedScheduleSummary(
  AppLocalizations l10n,
  AutomationScheduleDraft draft,
) {
  final (hour, minute) = parseHourMinute(draft.hourMinute);
  final time =
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  return switch (draft.preset) {
    AutomationSchedulePreset.hourly => l10n.automationsScheduleSummaryHourly(
      draft.minute,
    ),
    AutomationSchedulePreset.daily => l10n.automationsScheduleSummaryDaily(
      time,
    ),
    AutomationSchedulePreset.weekdays =>
      l10n.automationsScheduleSummaryWeekdays(time),
    AutomationSchedulePreset.weekly => l10n.automationsScheduleSummaryWeekly(
      _dayOfWeekLabel(l10n, draft.dayOfWeek ?? DateTime.monday),
      time,
    ),
    AutomationSchedulePreset.custom =>
      draft.customCron?.trim().isNotEmpty == true
          ? draft.customCron!.trim()
          : l10n.automationsScheduleCustom,
    AutomationSchedulePreset.once => l10n.automationsScheduleSummaryOnce(time),
  };
}

String _dayOfWeekLabel(AppLocalizations l10n, int dayOfWeek) {
  return switch (dayOfWeek) {
    DateTime.monday => l10n.automationsDayMonday,
    DateTime.tuesday => l10n.automationsDayTuesday,
    DateTime.wednesday => l10n.automationsDayWednesday,
    DateTime.thursday => l10n.automationsDayThursday,
    DateTime.friday => l10n.automationsDayFriday,
    DateTime.saturday => l10n.automationsDaySaturday,
    _ => l10n.automationsDaySunday,
  };
}

/// Inline [TpFormField] rows for automation schedule editing.
class AutomationSchedulePicker extends StatefulWidget {
  AutomationSchedulePicker({
    required this.draft,
    required this.onChanged,
    required this.labelWidth,
    AutomationScheduleCalculator? calculator,
    super.key,
  }) : calculator = calculator ?? _defaultCalculator;

  static final _defaultCalculator = AutomationScheduleCalculator();

  final AutomationScheduleDraft draft;
  final ValueChanged<AutomationScheduleDraft> onChanged;
  final double labelWidth;
  final AutomationScheduleCalculator calculator;

  @override
  State<AutomationSchedulePicker> createState() =>
      _AutomationSchedulePickerState();
}

class _AutomationSchedulePickerState extends State<AutomationSchedulePicker> {
  late final TextEditingController _hourMinuteCtl;
  late final TextEditingController _customCronCtl;

  AutomationScheduleDraft get _draft => widget.draft;

  @override
  void initState() {
    super.initState();
    _hourMinuteCtl = TextEditingController(text: widget.draft.hourMinute);
    _customCronCtl = TextEditingController(text: widget.draft.customCron ?? '');
  }

  @override
  void didUpdateWidget(covariant AutomationSchedulePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft.hourMinute != widget.draft.hourMinute &&
        _hourMinuteCtl.text != widget.draft.hourMinute) {
      _hourMinuteCtl.text = widget.draft.hourMinute;
    }
    if (oldWidget.draft.customCron != widget.draft.customCron &&
        _customCronCtl.text != (widget.draft.customCron ?? '')) {
      _customCronCtl.text = widget.draft.customCron ?? '';
    }
  }

  @override
  void dispose() {
    _hourMinuteCtl.dispose();
    _customCronCtl.dispose();
    super.dispose();
  }

  void _emit(AutomationScheduleDraft next) {
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final draft = _draft;
    final presets = AutomationSchedulePreset.values;
    final inline = TpFormFieldLayoutStyle.inline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpFormField<AutomationSchedulePreset>(
          key: ValueKey('schedule-preset-${draft.preset.name}'),
          id: 'schedulePreset',
          initialValue: draft.preset,
          label: Text(l10n.automationsSchedule),
          layoutStyle: inline,
          labelWidth: widget.labelWidth,
          builder: (state) {
            return TpSelect<AutomationSchedulePreset>(
              items: presets,
              initialItem: state.value ?? draft.preset,
              decoration: TpSelectDecorations.themed(context),
              itemLabel: (p) => _presetLabel(l10n, p),
              onChanged: (value) {
                if (value == null) return;
                state.didChange(value);
                _emit(
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
            layoutStyle: inline,
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
                  _emit(draft.copyWith(minute: value));
                },
              );
            },
          ),
          AutomationSchedulePreset.custom => TpFormField<String>(
            id: 'scheduleCustomCron',
            initialValue: draft.customCron ?? '',
            label: Text(l10n.automationsCustomCron),
            layoutStyle: inline,
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
                  _emit(draft.copyWith(customCron: value.trim()));
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
                layoutStyle: inline,
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
                  return TextField(
                    controller: _hourMinuteCtl,
                    focusNode: state.focusNode,
                    keyboardType: TextInputType.datetime,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
                    ],
                    onChanged: (value) {
                      state.didChange(value);
                      try {
                        parseHourMinute(value);
                        _emit(draft.copyWith(hourMinute: value));
                      } on Object {
                        // Keep typing; field validator runs on save.
                      }
                    },
                    decoration: InputDecoration(
                      hintText: '09:00',
                      errorText: state.hasError ? '' : null,
                      errorStyle: const TextStyle(height: 0, fontSize: 0),
                    ),
                  );
                },
              ),
              if (draft.preset == AutomationSchedulePreset.weekly) ...[
                const SizedBox(height: 12),
                TpFormField<int>(
                  id: 'scheduleDayOfWeek',
                  initialValue: draft.dayOfWeek ?? DateTime.monday,
                  label: Text(l10n.automationsScheduleWeekly),
                  layoutStyle: inline,
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
                      itemLabel: (d) => _dayOfWeekLabel(l10n, d),
                      onChanged: (value) {
                        if (value == null) return;
                        state.didChange(value);
                        _emit(draft.copyWith(dayOfWeek: value));
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
}

String _presetLabel(AppLocalizations l10n, AutomationSchedulePreset preset) {
  return switch (preset) {
    AutomationSchedulePreset.hourly => l10n.automationsScheduleHourly,
    AutomationSchedulePreset.daily => l10n.automationsScheduleDaily,
    AutomationSchedulePreset.weekdays => l10n.automationsScheduleWeekdays,
    AutomationSchedulePreset.weekly => l10n.automationsScheduleWeekly,
    AutomationSchedulePreset.custom => l10n.automationsScheduleCustom,
    AutomationSchedulePreset.once => l10n.automationsScheduleOnce,
  };
}
