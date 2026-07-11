import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/automation.dart';
import '../../services/automation/automation_schedule_calculator.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';

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

/// Preset + time/cron controls for automation schedules.
class AutomationSchedulePicker extends StatefulWidget {
  AutomationSchedulePicker({
    required this.draft,
    required this.onChanged,
    AutomationScheduleCalculator? calculator,
    super.key,
  }) : calculator = calculator ?? _defaultCalculator;

  static final _defaultCalculator = AutomationScheduleCalculator();

  final AutomationScheduleDraft draft;
  final ValueChanged<AutomationScheduleDraft> onChanged;
  final AutomationScheduleCalculator calculator;

  @override
  State<AutomationSchedulePicker> createState() =>
      _AutomationSchedulePickerState();
}

class _AutomationSchedulePickerState extends State<AutomationSchedulePicker> {
  late final TextEditingController _hourMinuteCtl;
  late final TextEditingController _customCronCtl;
  String? _cronError;

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
    final styles = AppTextStyles.of(context);
    final draft = widget.draft;
    final presets = AutomationSchedulePreset.values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.automationsSchedule,
          style: styles.smSemibold,
        ),
        const SizedBox(height: 8),
        AppDropdownField<AutomationSchedulePreset>(
          items: presets,
          initialItem: draft.preset,
          decoration: AppDropdownDecorations.themed(context),
          itemLabel: (p) => _presetLabel(l10n, p),
          onChanged: (value) {
            if (value == null) return;
            _emit(
              draft.copyWith(
                preset: value,
                clearDayOfWeek: value != AutomationSchedulePreset.weekly,
                clearCustomCron: value != AutomationSchedulePreset.custom,
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        switch (draft.preset) {
          AutomationSchedulePreset.hourly => _MinutePicker(
            minute: draft.minute,
            onChanged: (m) => _emit(draft.copyWith(minute: m)),
          ),
          AutomationSchedulePreset.custom => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _customCronCtl,
                decoration: InputDecoration(
                  labelText: l10n.automationsCustomCron,
                  hintText: '0 */2 * * *',
                  errorText: _cronError,
                ),
                onChanged: (value) {
                  final trimmed = value.trim();
                  final valid =
                      trimmed.isEmpty || widget.calculator.isValidCron(trimmed);
                  setState(() {
                    _cronError = valid ? null : l10n.automationsInvalidCron;
                  });
                  _emit(draft.copyWith(customCron: trimmed));
                },
              ),
            ],
          ),
          _ => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _hourMinuteCtl,
                decoration: InputDecoration(
                  labelText: l10n.automationsTime,
                  hintText: '09:00',
                ),
                keyboardType: TextInputType.datetime,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
                ],
                onChanged: (value) {
                  try {
                    parseHourMinute(value);
                    _emit(draft.copyWith(hourMinute: value));
                  } on Object {
                    // Keep typing; validation happens on save.
                  }
                },
              ),
              if (draft.preset == AutomationSchedulePreset.weekly) ...[
                const SizedBox(height: 12),
                AppDropdownField<int>(
                  items: const [
                    DateTime.monday,
                    DateTime.tuesday,
                    DateTime.wednesday,
                    DateTime.thursday,
                    DateTime.friday,
                    DateTime.saturday,
                    DateTime.sunday,
                  ],
                  initialItem: draft.dayOfWeek ?? DateTime.monday,
                  decoration: AppDropdownDecorations.themed(context),
                  itemLabel: (d) => _dayOfWeekLabel(l10n, d),
                  onChanged: (value) {
                    if (value == null) return;
                    _emit(draft.copyWith(dayOfWeek: value));
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

class _MinutePicker extends StatelessWidget {
  const _MinutePicker({required this.minute, required this.onChanged});

  final int minute;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppDropdownField<int>(
      items: List<int>.generate(60, (i) => i),
      initialItem: minute.clamp(0, 59),
      decoration: AppDropdownDecorations.themed(context),
      itemLabel: (m) => l10n.automationsScheduleSummaryHourly(m),
      onChanged: (value) {
        if (value == null) return;
        onChanged(value);
      },
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
  };
}
