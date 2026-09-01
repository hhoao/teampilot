import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/automation.dart';
import '../../services/automation/automation_schedule_calculator.dart';
import '../../services/automation/automation_schedule_defaults.dart';
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
      timezone: timezone ?? this.timezone,
    );
  }
}

AutomationScheduleDraft scheduleDraftFromAutomation(Automation automation) {
  final once = automation.preset == AutomationSchedulePreset.once;
  final runAt = once && automation.runAtMs != null
      ? DateTime.fromMillisecondsSinceEpoch(automation.runAtMs!)
      : null;
  return AutomationScheduleDraft(
    mode: once
        ? AutomationScheduleMode.once
        : AutomationScheduleMode.recurring,
    preset: automation.preset,
    minute: automation.minute,
    hourMinute: automation.hourMinute,
    onceDate: runAt == null ? null : DateTime(runAt.year, runAt.month, runAt.day),
    onceTime: runAt == null ? null : TimeOfDay(hour: runAt.hour, minute: runAt.minute),
    dayOfWeek: automation.dayOfWeek,
    customCron: automation.customCron,
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
        '${_formatDate(date)} ${formatHourMinute(time)}',
      );
    }
    return l10n.automationsScheduleOnce;
  }
  if (draft.mode == AutomationScheduleMode.countdown) {
    // Countdown drafts only exist transiently during create; the absolute
    // target is not known here, so render the raw delay label.
    return _countdownLabel(l10n, draft.countdownMinutes ?? 0);
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

String _countdownLabel(AppLocalizations l10n, int minutes) {
  if (minutes > 0 && minutes % 60 == 0) {
    return l10n.automationsCountdownHours(minutes ~/ 60);
  }
  return l10n.automationsCountdownMinutes(minutes);
}

/// Zero-padded `yyyy-MM-dd`, kept locale-independent so saved schedule strings
/// round-trip like the `HH:mm` times do.
String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// `_formatDate` + zero-padded `HH:mm`, for previews and summaries.
String _formatLocalDateTime(DateTime dateTime) =>
    '${_formatDate(dateTime)} '
    '${dateTime.hour.toString().padLeft(2, '0')}:'
    '${dateTime.minute.toString().padLeft(2, '0')}';

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
  late final TextEditingController _customCronCtl;
  late final TextEditingController _countdownCtl;

  /// True while the countdown custom field is being edited, so the value stays
  /// in the field (not the chips) until it parses.
  bool _countdownCustomActive = false;

  AutomationScheduleDraft get _draft => widget.draft;

  @override
  void initState() {
    super.initState();
    _customCronCtl = TextEditingController(text: widget.draft.customCron ?? '');
    _countdownCtl = TextEditingController(
      text: widget.draft.countdownMinutes?.toString() ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant AutomationSchedulePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft.customCron != widget.draft.customCron &&
        _customCronCtl.text != (widget.draft.customCron ?? '')) {
      _customCronCtl.text = widget.draft.customCron ?? '';
    }
    final minutes = _draft.countdownMinutes;
    if (!_countdownCustomActive &&
        _countdownCtl.text != (minutes?.toString() ?? '')) {
      _countdownCtl.text = minutes?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _customCronCtl.dispose();
    _countdownCtl.dispose();
    super.dispose();
  }

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
          AutomationScheduleMode.once => _buildOnceRows(l10n, draft, inline),
          AutomationScheduleMode.countdown => _buildCountdownRows(
            l10n,
            draft,
            inline,
          ),
          AutomationScheduleMode.recurring => _buildRecurringRows(
            l10n,
            draft,
            inline,
          ),
        },
      ],
    );
  }

  /// Once ⇔ preset once stay in sync; recurring falls back to the daily
  /// preset the editor has always defaulted to.
  AutomationScheduleDraft _draftForMode(
    AutomationScheduleDraft draft,
    AutomationScheduleMode mode,
  ) {
    switch (mode) {
      case AutomationScheduleMode.once:
        return draft.copyWith(mode: mode, preset: AutomationSchedulePreset.once);
      case AutomationScheduleMode.countdown:
        return draft.copyWith(
          mode: mode,
          preset: AutomationSchedulePreset.once,
          countdownMinutes: draft.countdownMinutes ?? 15,
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

  Widget _buildOnceRows(
    AppLocalizations l10n,
    AutomationScheduleDraft draft,
    TpFormFieldLayoutStyle inline,
  ) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpFormField<DateTime>(
          key: ValueKey('schedule-once-date-${_formatDate(draft.onceDate ?? now)}'),
          id: 'scheduleOnceDate',
          initialValue: draft.onceDate ?? now,
          label: Text(l10n.automationsScheduleDate),
          layoutStyle: inline,
          labelWidth: widget.labelWidth,
          builder: (state) {
            final selected = state.value ?? draft.onceDate ?? now;
            return TpDatePicker(
              key: ValueKey('schedule-once-date-picker-$selected'),
              firstDate: DateTime(now.year, now.month, now.day),
              lastDate: now.add(const Duration(days: 365)),
              selected: selected,
              onChanged: (date) {
                if (date == null) return;
                state.didChange(date);
                _emit(draft.copyWith(onceDate: date));
              },
              triggerBuilder: (context, isOpen) => _FieldTrigger(
                label: _formatDate(selected),
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
          layoutStyle: inline,
          labelWidth: widget.labelWidth,
          builder: (state) {
            return TpTimePicker(
              initialValue: state.value ?? draft.onceTime,
              onChanged: (time) {
                state.didChange(time);
                _emit(draft.copyWith(onceTime: time));
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildCountdownRows(
    AppLocalizations l10n,
    AutomationScheduleDraft draft,
    TpFormFieldLayoutStyle inline,
  ) {
    final minutes = draft.countdownMinutes ?? 15;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final quick in const [5, 15, 30, 60, 120])
              ChoiceChip(
                label: Text(_countdownLabel(l10n, quick)),
                selected: minutes == quick && !_countdownCustomActive,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  setState(() => _countdownCustomActive = false);
                  _countdownCtl.text = quick.toString();
                  _emit(draft.copyWith(countdownMinutes: quick));
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        TpFormField<String>(
          id: 'scheduleCountdownMinutes',
          initialValue: _countdownCtl.text,
          label: Text(l10n.automationsCountdownCustom),
          layoutStyle: inline,
          labelWidth: widget.labelWidth,
          builder: (state) {
            return TextField(
              controller: _countdownCtl,
              focusNode: state.focusNode,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (value) {
                state.didChange(value);
                final parsed = int.tryParse(value.trim());
                setState(() => _countdownCustomActive = value.trim().isNotEmpty);
                if (parsed == null || parsed <= 0) {
                  // Keep typing; nothing meaningful to emit yet.
                  return;
                }
                _emit(draft.copyWith(countdownMinutes: parsed));
              },
              decoration: InputDecoration(
                errorText: state.hasError ? '' : null,
                errorStyle: const TextStyle(height: 0, fontSize: 0),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          l10n.automationsCountdownPreview(
            _formatLocalDateTime(
              DateTime.fromMillisecondsSinceEpoch(
                countdownToRunAtMs(
                  durationMinutes: minutes,
                  now: DateTime.now(),
                ),
              ),
            ),
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildRecurringRows(
    AppLocalizations l10n,
    AutomationScheduleDraft draft,
    TpFormFieldLayoutStyle inline,
  ) {
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
                  final (hour, minute) = _parseDraftHourMinute(
                    state.value ?? draft.hourMinute,
                  );
                  return TpTimePicker(
                    initialValue: TimeOfDay(hour: hour, minute: minute),
                    onChanged: (time) {
                      final formatted = formatHourMinute(time);
                      state.didChange(formatted);
                      _emit(draft.copyWith(hourMinute: formatted));
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

  (int, int) _parseDraftHourMinute(String raw) {
    try {
      return parseHourMinute(raw);
    } on Object {
      return (9, 0);
    }
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

/// Bordered, field-styled trigger for the once-mode [TpDatePicker] so the row
/// reads like the other inline form controls.
class _FieldTrigger extends StatelessWidget {
  const _FieldTrigger({required this.label, required this.isOpen});

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
            size: context.tpIconSizes.sm,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(label, style: TpTextStyles.of(context).sm),
        ],
      ),
    );
  }
}
