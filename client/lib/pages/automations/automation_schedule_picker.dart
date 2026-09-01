import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/automation.dart';
import '../../services/automation/automation_schedule_calculator.dart';
import '../../services/automation/automation_schedule_defaults.dart';
import 'automation_schedule_picker_modes.dart';
import 'package:shared_ui/shared_ui.dart';

/// Schedule fields edited by [AutomationEditorDialog].
///
/// [mode] selects which picker rows are shown: a one-shot date+time
/// ([AutomationScheduleMode.once]), a relative delay
/// ([AutomationScheduleMode.countdown], create-only — it is composed into an
/// absolute `runAtMs` when the automation is saved), or the recurring presets
/// ([AutomationScheduleMode.recurring]). Mode and [preset] stay in sync:
/// mode once ⇔ preset once.
///
/// For once mode, [onceDate] + [onceTime] are local wall-clock values; the
/// automation's [timezone] is applied when the saved `runAtMs` is composed
/// (see `combineLocalDateAndTimeToMs`), not here.
class AutomationScheduleDraft {
  const AutomationScheduleDraft({
    required this.preset,
    required this.minute,
    required this.hourMinute,
    this.mode = AutomationScheduleMode.recurring,
    this.onceDate,
    this.onceTime,
    this.countdownMinutes,
    this.dayOfWeek,
    this.customCron,
    this.runAtMs,
    required this.timezone,
  });

  /// Factory for the create flow: once mode seeded 15 minutes out, plus the
  /// recurring defaults the editor has always shown.
  factory AutomationScheduleDraft.forCreate({
    required String timezone,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final onceAt = defaultOnceDateTime(current);
    return AutomationScheduleDraft(
      mode: AutomationScheduleMode.once,
      preset: AutomationSchedulePreset.once,
      minute: 0,
      hourMinute: formatHourMinute(roundUpToNextQuarterHour(current)),
      timezone: timezone,
      onceDate: DateTime(onceAt.year, onceAt.month, onceAt.day),
      onceTime: TimeOfDay(hour: onceAt.hour, minute: onceAt.minute),
      countdownMinutes: 15,
    );
  }

  final AutomationScheduleMode mode;
  final AutomationSchedulePreset preset;
  final int minute;
  final String hourMinute;

  /// Calendar day for once mode (local wall clock); null otherwise.
  final DateTime? onceDate;

  /// Time of day for once mode; null for recurring drafts that never had a
  /// once time.
  final TimeOfDay? onceTime;

  /// Countdown length in minutes; only meaningful in countdown mode.
  final int? countdownMinutes;
  final int? dayOfWeek;
  final String? customCron;

  /// Raw stored target for once schedules; the save path reuses it verbatim
  /// when the user has not changed onceDate/onceTime (see
  /// AutomationEditorDialog _save).
  final int? runAtMs;

  final String timezone;

  AutomationScheduleDraft copyWith({
    AutomationScheduleMode? mode,
    AutomationSchedulePreset? preset,
    int? minute,
    String? hourMinute,
    DateTime? onceDate,
    bool clearOnceDate = false,
    TimeOfDay? onceTime,
    int? countdownMinutes,
    bool clearCountdownMinutes = false,
    int? dayOfWeek,
    bool clearDayOfWeek = false,
    String? customCron,
    bool clearCustomCron = false,
    int? runAtMs,
    bool clearRunAtMs = false,
    String? timezone,
  }) {
    return AutomationScheduleDraft(
      mode: mode ?? this.mode,
      preset: preset ?? this.preset,
      minute: minute ?? this.minute,
      hourMinute: hourMinute ?? this.hourMinute,
      onceDate: clearOnceDate ? null : (onceDate ?? this.onceDate),
      onceTime: onceTime ?? this.onceTime,
      countdownMinutes: clearCountdownMinutes
          ? null
          : (countdownMinutes ?? this.countdownMinutes),
      dayOfWeek: clearDayOfWeek ? null : (dayOfWeek ?? this.dayOfWeek),
      customCron: clearCustomCron ? null : (customCron ?? this.customCron),
      runAtMs: clearRunAtMs ? null : (runAtMs ?? this.runAtMs),
      timezone: timezone ?? this.timezone,
    );
  }
}

AutomationScheduleDraft scheduleDraftFromAutomation(Automation automation) {
  final once = automation.preset == AutomationSchedulePreset.once;
  // Stored runAtMs is composed in the automation timezone at save time; the
  // edit draft works in local wall clock, matching what the user picked.
  final runAt = once && automation.runAtMs != null
      ? DateTime.fromMillisecondsSinceEpoch(automation.runAtMs!)
      : null;
  return AutomationScheduleDraft(
    mode: once ? AutomationScheduleMode.once : AutomationScheduleMode.recurring,
    preset: automation.preset,
    minute: automation.minute,
    hourMinute: automation.hourMinute,
    onceDate: runAt == null
        ? null
        : DateTime(runAt.year, runAt.month, runAt.day),
    onceTime: runAt == null
        ? null
        : TimeOfDay(hour: runAt.hour, minute: runAt.minute),
    dayOfWeek: automation.dayOfWeek,
    customCron: automation.customCron,
    // Carried verbatim so the save path can reuse the stored target when the
    // user has not touched onceDate/onceTime (Task 7 _save).
    runAtMs: automation.runAtMs,
    timezone: automation.timezone,
  );
}

String localizedScheduleSummary(
  AppLocalizations l10n,
  AutomationScheduleDraft draft,
) {
  if (draft.mode == AutomationScheduleMode.once) {
    final date = draft.onceDate;
    final time = draft.onceTime;
    if (date != null && time != null) {
      return l10n.automationsScheduleSummaryOnce(
        formatAutomationScheduleDateTime(
          DateTime(date.year, date.month, date.day, time.hour, time.minute),
        ),
      );
    }
    return l10n.automationsScheduleOnce;
  }
  if (draft.mode == AutomationScheduleMode.countdown) {
    // Countdown drafts only exist transiently during create; the absolute
    // target is not known here, so render the raw delay label.
    return countdownDelayLabel(l10n, draft.countdownMinutes ?? 0);
  }
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
      dayOfWeekScheduleLabel(l10n, draft.dayOfWeek ?? DateTime.monday),
      time,
    ),
    AutomationSchedulePreset.custom =>
      draft.customCron?.trim().isNotEmpty == true
          ? draft.customCron!.trim()
          : l10n.automationsScheduleCustom,
    AutomationSchedulePreset.once => l10n.automationsScheduleSummaryOnce(time),
  };
}

/// Chip / summary label for a countdown delay: whole hours render as `{hours} h`,
/// everything else as `{minutes} min`.
String countdownDelayLabel(AppLocalizations l10n, int minutes) {
  if (minutes > 0 && minutes % 60 == 0) {
    return l10n.automationsCountdownHours(minutes ~/ 60);
  }
  return l10n.automationsCountdownMinutes(minutes);
}

/// Zero-padded `yyyy-MM-dd`, kept locale-independent so saved schedule strings
/// round-trip like the `HH:mm` times do.
String formatAutomationScheduleDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// [formatAutomationScheduleDate] + zero-padded `HH:mm`, for previews and
/// summaries.
String formatAutomationScheduleDateTime(DateTime dateTime) =>
    '${formatAutomationScheduleDate(dateTime)} '
    '${dateTime.hour.toString().padLeft(2, '0')}:'
    '${dateTime.minute.toString().padLeft(2, '0')}';

String dayOfWeekScheduleLabel(AppLocalizations l10n, int dayOfWeek) {
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

/// Inline [TpFormField] rows for automation schedule editing. Mode rows live
/// in `automation_schedule_picker_modes.dart`.
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
  AutomationScheduleDraft get _draft => widget.draft;

  void _emit(AutomationScheduleDraft next) {
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final draft = _draft;
    final inline = TpFormFieldLayoutStyle.inline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpFormField<AutomationScheduleMode>(
          key: ValueKey('schedule-mode-${draft.mode.name}'),
          id: 'scheduleMode',
          initialValue: draft.mode,
          label: Text(l10n.automationsSchedule),
          layoutStyle: inline,
          labelWidth: widget.labelWidth,
          builder: (state) {
            // The editor is a dialog (narrow viewport); mobileBreakpoint 0
            // keeps all three modes visible as a pill instead of collapsing
            // into a compact select that hides two of them.
            return TpSegmentedPicker<AutomationScheduleMode>(
              mobileBreakpoint: 0,
              scrollable: false,
              alignment: Alignment.centerLeft,
              segments: [
                TpSegmentedOption(
                  value: AutomationScheduleMode.once,
                  label: l10n.automationsScheduleModeOnce,
                  icon: Icons.schedule_outlined,
                ),
                TpSegmentedOption(
                  value: AutomationScheduleMode.countdown,
                  label: l10n.automationsScheduleModeCountdown,
                  icon: Icons.timer_outlined,
                ),
                TpSegmentedOption(
                  value: AutomationScheduleMode.recurring,
                  label: l10n.automationsScheduleModeRecurring,
                  icon: Icons.repeat_outlined,
                ),
              ],
              selected: state.value ?? draft.mode,
              onChanged: (mode) {
                state.didChange(mode);
                _emit(_draftForMode(draft, mode));
              },
            );
          },
        ),
        const SizedBox(height: 12),
        switch (draft.mode) {
          AutomationScheduleMode.once => AutomationScheduleOnceRows(
            draft: draft,
            labelWidth: widget.labelWidth,
            onChanged: _emit,
          ),
          AutomationScheduleMode.countdown => AutomationScheduleCountdownRows(
            draft: draft,
            labelWidth: widget.labelWidth,
            onChanged: _emit,
          ),
          AutomationScheduleMode.recurring => AutomationScheduleRecurringRows(
            draft: draft,
            labelWidth: widget.labelWidth,
            onChanged: _emit,
            calculator: widget.calculator,
          ),
        },
      ],
    );
  }

  /// Once ⇔ preset once stay in sync; recurring falls back to the daily
  /// preset the editor has always defaulted to. A recurring draft that never
  /// had a once slot is seeded 15 minutes out so the once/countdown rows do
  /// not fall back to a 09:00 placeholder.
  AutomationScheduleDraft _draftForMode(
    AutomationScheduleDraft draft,
    AutomationScheduleMode mode,
  ) {
    final needsOnceSlot =
        mode == AutomationScheduleMode.once ||
        mode == AutomationScheduleMode.countdown;
    final seeded =
        needsOnceSlot && draft.onceDate == null && draft.onceTime == null
        ? _withOnceDefaults(draft)
        : draft;
    switch (mode) {
      case AutomationScheduleMode.once:
        return seeded.copyWith(
          mode: mode,
          preset: AutomationSchedulePreset.once,
        );
      case AutomationScheduleMode.countdown:
        return seeded.copyWith(
          mode: mode,
          preset: AutomationSchedulePreset.once,
          countdownMinutes: seeded.countdownMinutes ?? 15,
        );
      case AutomationScheduleMode.recurring:
        return draft.copyWith(
          mode: mode,
          preset: draft.preset == AutomationSchedulePreset.once
              ? AutomationSchedulePreset.daily
              : draft.preset,
        );
    }
  }

  AutomationScheduleDraft _withOnceDefaults(AutomationScheduleDraft draft) {
    final onceAt = defaultOnceDateTime(DateTime.now());
    return draft.copyWith(
      onceDate: DateTime(onceAt.year, onceAt.month, onceAt.day),
      onceTime: TimeOfDay(hour: onceAt.hour, minute: onceAt.minute),
    );
  }
}

String schedulePresetLabel(
  AppLocalizations l10n,
  AutomationSchedulePreset preset,
) {
  return switch (preset) {
    AutomationSchedulePreset.hourly => l10n.automationsScheduleHourly,
    AutomationSchedulePreset.daily => l10n.automationsScheduleDaily,
    AutomationSchedulePreset.weekdays => l10n.automationsScheduleWeekdays,
    AutomationSchedulePreset.weekly => l10n.automationsScheduleWeekly,
    AutomationSchedulePreset.custom => l10n.automationsScheduleCustom,
    AutomationSchedulePreset.once => l10n.automationsScheduleOnce,
  };
}
