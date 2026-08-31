# Automation Once / Countdown Schedule + Tp Date/Time Pickers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users create one-shot (date+time), countdown, and recurring automations that can fire later today, using new `TpDatePicker` / `TpTimePicker` controls instead of free-text `HH:mm`.

**Architecture:** Add single-day and time pickers in `shared_ui` (shadcn-aligned UX, no `shadcn_ui` package). Extend `Automation` with `preset: once` + `runAtMs`. Editor exposes three modes (Once / Countdown / Recurring); countdown saves as once. Calculator returns `int?` so expired once schedules clear `nextRunAtMs`.

**Tech Stack:** Flutter / Dart 3, `shared_ui` (`TpPopover`, `TpTheme`, `calendar_date_utils`), existing `Automation` / `AutomationScheduleCalculator` / editor dialog, ARB l10n, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-31-automation-schedule-once-countdown-pickers-design.md`

## Global Constraints

- Do **not** add a `shadcn_ui` dependency; implement `Tp*` on existing `TpPopover` / `TpTheme`.
- Countdown is create-only UI; never persist a countdown preset.
- `once` effective run limit is 1; hide max-run field for once.
- New create defaults: mode **Once**; once = now+15m; countdown chip = 15m; recurring daily with time rounded up to next 15-minute slot.
- Recurring must keep supporting “today’s upcoming time”; fix only defaults/UX, not the daily algorithm’s core.
- l10n only in `client/lib/l10n/app_en.arb` and `app_zh.arb`.
- Prefer `Tp*` for new reusable controls; no `print`; diagnostics via `AppLogger` if needed.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` and targeted tests listed per task (full `dart run tool/run_tests.dart` at end).

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/shared_ui/lib/src/components/date_range/tp_calendar.dart` | Single-day month grid (reuse `calendar_date_utils`). |
| `client/packages/shared_ui/lib/src/components/date_range/tp_date_picker.dart` | Popover single-date picker. |
| `client/packages/shared_ui/lib/src/components/time_picker/tp_time_picker.dart` | 24h hour+minute time picker. |
| `client/packages/shared_ui/lib/shared_ui.dart` | Export new widgets. |
| `client/packages/shared_ui/test/components/date_range/tp_date_picker_test.dart` | Date picker widget tests. |
| `client/packages/shared_ui/test/components/time_picker/tp_time_picker_test.dart` | Time picker widget tests. |
| `client/lib/models/automation.dart` | `once` preset, `runAtMs`, validate, JSON, `hasRunLimit` / `isRunLimitReached`. |
| `client/lib/services/automation/automation_schedule_calculator.dart` | `once` next-run; return `int?`. |
| `client/lib/services/automation/automation_schedule_defaults.dart` | Pure helpers: default once/recurring times, combine date+time → ms. |
| `client/lib/pages/automations/automation_schedule_picker.dart` | Three-mode UI + draft fields. |
| `client/lib/pages/automations/automation_editor_dialog.dart` | Save once/`runAtMs`/`dtstartMs`/`maxRunCount`; mode defaults. |
| `client/lib/pages/automations/automation_editor_form_body.dart` | Hide max-run when once. |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | Mode labels, once summary, past-time error, countdown chips. |
| `client/lib/services/automation/automation_scheduler.dart` | Clear `nextRunAtMs` when compute returns null. |
| `client/lib/services/automation/automation_dispatcher.dart` | Use effective max runs for once without NPE. |

---

### Task 1: `TpCalendar` + `TpDatePicker`

**Files:**
- Create: `client/packages/shared_ui/lib/src/components/date_range/tp_calendar.dart`
- Create: `client/packages/shared_ui/lib/src/components/date_range/tp_date_picker.dart`
- Modify: `client/packages/shared_ui/lib/shared_ui.dart` (export both)
- Test: `client/packages/shared_ui/test/components/date_range/tp_date_picker_test.dart`

**Interfaces:**
- Consumes: `CalendarDateUtils`, `TpPopover`, `TpHover`, `TpActionMenuMetrics.panelDecoration`, patterns from `TpRangeCalendar` / `TpDateRangePicker`
- Produces:
  - `class TpCalendar extends StatefulWidget` with `DateTime firstDate`, `DateTime lastDate`, `DateTime? selected`, `ValueChanged<DateTime?>? onChanged`, `DateTime? initialMonth`, `bool allowDeselection`
  - `class TpDatePicker extends StatefulWidget` with same date bounds, `DateTime? selected`, `ValueChanged<DateTime?>? onChanged`, `bool closeOnSelection`, `Widget Function(BuildContext, bool isOpen) triggerBuilder`, `TpPopoverController? controller`, optional `Widget? header`

- [ ] **Step 1: Write the failing widget tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: TpTheme(
          data: TpThemeData.fromColorScheme(
            ColorScheme.fromSeed(seedColor: Colors.orange),
            scale: 1.0,
          ),
          child: Scaffold(body: child),
        ),
      );

  testWidgets('TpCalendar selects a single day', (tester) async {
    DateTime? selected;
    await tester.pumpWidget(
      wrap(
        Center(
          child: SizedBox(
            width: 280,
            child: TpCalendar(
              firstDate: DateTime(2026, 7, 1),
              lastDate: DateTime(2026, 7, 31),
              initialMonth: DateTime(2026, 7, 1),
              onChanged: (d) => selected = d,
            ),
          ),
        ),
      ),
    );
    Finder enabledDay(String label) => find.descendant(
          of: find.byType(TpHover),
          matching: find.text(label),
        );
    await tester.tap(enabledDay('5'));
    await tester.pump();
    expect(selected, DateTime(2026, 7, 5));
  });

  testWidgets('TpDatePicker opens and closes on selection', (tester) async {
    DateTime? selected;
    await tester.pumpWidget(
      wrap(
        TpDatePicker(
          firstDate: DateTime(2026, 1, 1),
          lastDate: DateTime(2026, 12, 31),
          closeOnSelection: true,
          onChanged: (d) => selected = d,
          triggerBuilder: (context, isOpen) =>
              Text(isOpen ? 'Open' : 'Closed'),
        ),
      ),
    );
    await tester.tap(find.text('Closed'));
    await tester.pumpAndSettle();
    expect(find.byType(TpCalendar), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(TpHover), matching: find.text('15')),
    );
    await tester.pumpAndSettle();
    expect(selected, isNotNull);
    expect(find.text('Closed'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client/packages/shared_ui && flutter test test/components/date_range/tp_date_picker_test.dart`

Expected: FAIL — `TpCalendar` / `TpDatePicker` not found.

- [ ] **Step 3: Implement `TpCalendar` and `TpDatePicker`**

Mirror `TpRangeCalendar` month chrome and `_DayCell` styling, but select one `DateTime` (calendar day). On re-tap of selected day when `allowDeselection` is true, emit `null`. `TpDatePicker` wraps calendar in `TpPopover` like `TpDateRangePicker` (`panelWidth: 280`, close when `closeOnSelection && selected != null`).

- [ ] **Step 4: Export and re-run tests**

Add exports to `shared_ui.dart`. Re-run the test file. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/shared_ui/lib/src/components/date_range/tp_calendar.dart \
  client/packages/shared_ui/lib/src/components/date_range/tp_date_picker.dart \
  client/packages/shared_ui/lib/shared_ui.dart \
  client/packages/shared_ui/test/components/date_range/tp_date_picker_test.dart
git commit -m "$(cat <<'EOF'
feat(shared_ui): add TpDatePicker single-day calendar

EOF
)"
```

---

### Task 2: `TpTimePicker`

**Files:**
- Create: `client/packages/shared_ui/lib/src/components/time_picker/tp_time_picker.dart`
- Modify: `client/packages/shared_ui/lib/shared_ui.dart`
- Test: `client/packages/shared_ui/test/components/time_picker/tp_time_picker_test.dart`

**Interfaces:**
- Consumes: `TpTheme` / `ColorScheme`, optional trailing widget
- Produces:
  - `class TpTimePicker extends StatefulWidget` with `TimeOfDay? initialValue`, `ValueChanged<TimeOfDay>? onChanged`, `bool enabled`, `Widget? trailing`, `bool showSeconds` (default `false`)
  - Emits clamped hour `0..23` and minute `0..59` via `TimeOfDay`

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('TpTimePicker notifies on hour and minute edit', (tester) async {
  TimeOfDay? value;
  await tester.pumpWidget(
    wrap(
      TpTimePicker(
        initialValue: const TimeOfDay(hour: 9, minute: 0),
        onChanged: (t) => value = t,
      ),
    ),
  );
  // Find hour / minute TextFields by keys set on the widget:
  // Key('tp-time-picker-hour'), Key('tp-time-picker-minute')
  await tester.enterText(find.byKey(const Key('tp-time-picker-hour')), '14');
  await tester.enterText(find.byKey(const Key('tp-time-picker-minute')), '30');
  await tester.pump();
  expect(value, const TimeOfDay(hour: 14, minute: 30));
});
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client/packages/shared_ui && flutter test test/components/time_picker/tp_time_picker_test.dart`

- [ ] **Step 3: Implement `TpTimePicker`**

Layout: two narrow numeric fields (hour, minute) separated by `:`, optional trailing icon. Digits-only formatters; on change parse + clamp; do not show seconds when `showSeconds == false`. Keep height consistent with `TpInput` / select closed header (~32–36px).

- [ ] **Step 4: Export, run tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/shared_ui/lib/src/components/time_picker/tp_time_picker.dart \
  client/packages/shared_ui/lib/shared_ui.dart \
  client/packages/shared_ui/test/components/time_picker/tp_time_picker_test.dart
git commit -m "$(cat <<'EOF'
feat(shared_ui): add TpTimePicker 24h hour-minute control

EOF
)"
```

---

### Task 3: Automation model — `once` + `runAtMs`

**Files:**
- Modify: `client/lib/models/automation.dart`
- Modify: `client/test/models/automation_test.dart`
- Modify: `client/test/support/automation_test_fixtures.dart` (optional `runAtMs` param if helpers construct Automation)

**Interfaces:**
- Consumes: existing `Automation` JSON shape
- Produces:
  - `enum AutomationSchedulePreset { hourly, daily, weekdays, weekly, custom, once }`
  - `final int? runAtMs` on `Automation`
  - `bool get hasRunLimit` true when `preset == once` **or** (`maxRunCount != null && maxRunCount! > 0`)
  - `int? get effectiveMaxRunCount` → `1` when `preset == once`, else `maxRunCount`
  - `bool get isRunLimitReached` → `hasRunLimit && runCount >= (effectiveMaxRunCount ?? 0)`
  - `validate()` requires `runAtMs != null && runAtMs! > 0` when `preset == once`

- [ ] **Step 1: Write failing model tests**

```dart
test('once round-trips runAtMs', () {
  final a = Automation(
    // ...minimal required fields...
    preset: AutomationSchedulePreset.once,
    runAtMs: 1_700_000_100_000,
    hourMinute: '09:00',
    timezone: 'UTC',
    dtstartMs: 1_700_000_100_000,
    // ...
  );
  final back = Automation.fromJson(a.toJson());
  expect(back.preset, AutomationSchedulePreset.once);
  expect(back.runAtMs, 1_700_000_100_000);
  expect(back.hasRunLimit, isTrue);
  expect(back.effectiveMaxRunCount, 1);
});

test('once requires runAtMs', () {
  expect(
    () => Automation(
      // preset once, runAtMs: null
    ).validate(),
    throwsA(isA<ArgumentError>()),
  );
});
```

- [ ] **Step 2: Run — expect FAIL** (enum / field missing)

Run: `cd client && flutter test test/models/automation_test.dart`

- [ ] **Step 3: Implement model fields**

Wire `runAtMs` through constructor, `fromJson`, `toJson`, `copyWith` (`clearRunAtMs`), `==` / `hashCode`. Update `hasRunLimit` / `isRunLimitReached` as above so dispatcher never does `maxRunCount!` on a bare once without stored max.

- [ ] **Step 4: Run model tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/automation.dart client/test/models/automation_test.dart \
  client/test/support/automation_test_fixtures.dart
git commit -m "$(cat <<'EOF'
feat(automations): add once schedule preset and runAtMs

EOF
)"
```

---

### Task 4: Schedule calculator — `once` + nullable next

**Files:**
- Modify: `client/lib/services/automation/automation_schedule_calculator.dart`
- Modify: `client/test/services/automation/automation_schedule_calculator_test.dart`
- Modify callers that assume non-null `int`:
  - `client/lib/services/automation/automation_dispatcher.dart` (`_advanceAutomationAfterRun` — already nullable assign)
  - `client/lib/services/automation/automation_scheduler.dart` (missed-run + claim)
  - `client/lib/cubits/automation_cubit.dart`
  - `client/lib/pages/automations/automation_editor_dialog.dart`

**Interfaces:**
- Consumes: `Automation.runAtMs`, `AutomationSchedulePreset.once`
- Produces: `int? computeNextRunAtMs(Automation automation, {required int afterMs})`

- [ ] **Step 1: Write failing calculator tests**

```dart
test('once returns runAtMs when still in the future', () {
  final runAt = DateTime.utc(2026, 1, 1, 15, 0).millisecondsSinceEpoch;
  final automation = _automation(
    preset: AutomationSchedulePreset.once,
    runAtMs: runAt,
    dtstartMs: runAt,
  );
  final after = DateTime.utc(2026, 1, 1, 14, 0).millisecondsSinceEpoch;
  expect(calc.computeNextRunAtMs(automation, afterMs: after), runAt);
});

test('once returns null when runAtMs is not after afterMs', () {
  final runAt = DateTime.utc(2026, 1, 1, 15, 0).millisecondsSinceEpoch;
  final automation = _automation(
    preset: AutomationSchedulePreset.once,
    runAtMs: runAt,
    dtstartMs: runAt,
  );
  final after = DateTime.utc(2026, 1, 1, 15, 0).millisecondsSinceEpoch;
  expect(calc.computeNextRunAtMs(automation, afterMs: after), isNull);
});

test('daily still-upcoming time stays on same day', () {
  final automation = _automation(hourMinute: '18:00');
  final after = DateTime.utc(2026, 1, 1, 10, 0).millisecondsSinceEpoch;
  final next = calc.computeNextRunAtMs(automation, afterMs: after)!;
  final dt = DateTime.fromMillisecondsSinceEpoch(next, isUtc: true);
  expect(dt.day, 1);
  expect(dt.hour, 18);
});
```

Update `_automation` helper to accept `int? runAtMs` and `int? dtstartMs` override.

- [ ] **Step 2: Run calculator tests — expect FAIL**

Run: `cd client && flutter test test/services/automation/automation_schedule_calculator_test.dart`

- [ ] **Step 3: Implement calculator + caller null clearing**

In `computeNextRunAtMs`, handle `once` first (validate `runAtMs`). Change return type to `int?`. In `automation_scheduler.dart` missed-run advance:

```dart
final next = _scheduleCalculator.computeNextRunAtMs(automation, afterMs: now);
final advanced = automation.copyWith(
  lastRunAtMs: now,
  nextRunAtMs: next,
  clearNextRunAtMs: next == null,
  updatedAtMs: now,
);
```

Same pattern anywhere a non-null `int` was assumed. In dispatcher `_advanceAutomationAfterRun`, replace `maxRunCount!` with `effectiveMaxRunCount!` (or local `final max = automation.effectiveMaxRunCount`).

- [ ] **Step 4: Run calculator + related unit tests — PASS**

```bash
cd client && flutter test \
  test/services/automation/automation_schedule_calculator_test.dart \
  test/services/automation/automation_scheduler_test.dart \
  test/services/automation/automation_dispatcher_test.dart \
  test/cubits/automation_cubit_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/automation/automation_schedule_calculator.dart \
  client/lib/services/automation/automation_scheduler.dart \
  client/lib/services/automation/automation_dispatcher.dart \
  client/lib/cubits/automation_cubit.dart \
  client/lib/pages/automations/automation_editor_dialog.dart \
  client/test/services/automation/automation_schedule_calculator_test.dart
git commit -m "$(cat <<'EOF'
feat(automations): compute next run for once schedules

EOF
)"
```

---

### Task 5: Pure schedule defaults + datetime combine helpers

**Files:**
- Create: `client/lib/services/automation/automation_schedule_defaults.dart`
- Create: `client/test/services/automation/automation_schedule_defaults_test.dart`

**Interfaces:**
- Produces:
  - `enum AutomationScheduleMode { once, countdown, recurring }`
  - `DateTime defaultOnceDateTime(DateTime now)` → `now.add(Duration(minutes: 15))`
  - `TimeOfDay roundUpToNextQuarterHour(DateTime now)` — if already on quarter and seconds==0, use next quarter; else ceil to 0/15/30/45 or next hour
  - `String formatHourMinute(TimeOfDay t)` → `HH:mm` zero-padded
  - `int combineLocalDateAndTimeToMs({required DateTime date, required TimeOfDay time, required String timezone})` using same `_resolveLocation` approach as calculator (either export a shared location helper or duplicate the small resolve via a package-visible function in the calculator file)
  - `int countdownToRunAtMs({required int durationMinutes, required DateTime now})` → `now.add(Duration(minutes: durationMinutes)).millisecondsSinceEpoch`

- [ ] **Step 1: Write failing unit tests** for defaults and combine (use fixed `DateTime` inputs; for timezone use `'UTC'`).

- [ ] **Step 2: Run — FAIL**

Run: `cd client && flutter test test/services/automation/automation_schedule_defaults_test.dart`

- [ ] **Step 3: Implement helpers**

Prefer extracting `tz.Location resolveAutomationLocation(String timezone)` from the calculator into a small shared top-level in the same library file or the new defaults file importing `timezone`.

- [ ] **Step 4: Run — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/automation/automation_schedule_defaults.dart \
  client/test/services/automation/automation_schedule_defaults_test.dart \
  client/lib/services/automation/automation_schedule_calculator.dart
git commit -m "$(cat <<'EOF'
feat(automations): add schedule default and datetime helpers

EOF
)"
```

---

### Task 6: Schedule picker UI — three modes + Tp pickers

**Files:**
- Modify: `client/lib/pages/automations/automation_schedule_picker.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb` (then regenerate localizations per project norm — usually `flutter gen-l10n` via existing tooling)
- Test: extend `client/test/pages/automations/automation_editor_dialog_test.dart` **or** add `client/test/pages/automations/automation_schedule_picker_test.dart`

**Interfaces:**
- Consumes: `TpDatePicker`, `TpTimePicker`, `TpSegmentedControl` / `TpSegmentedPicker`, helpers from Task 5
- Produces: expanded `AutomationScheduleDraft` with:
  - `AutomationScheduleMode mode`
  - `DateTime? onceDate` (calendar day)
  - `TimeOfDay onceTime`
  - `int? countdownMinutes`
  - existing recurring fields
  - factory `scheduleDraftFromAutomation(Automation)` maps `once` → mode once; else recurring
  - `localizedScheduleSummary` handles once → formatted date-time string

- [ ] **Step 1: Add ARB keys** (en + zh)

```
automationsScheduleModeOnce / Countdown / Recurring
automationsScheduleDate
automationsScheduleOnceSummary: "{dateTime}"
automationsSchedulePastTime: "Choose a time in the future"
automationsCountdownMinutes: "{minutes} min"
automationsCountdownHours: "{hours} h"
automationsCountdownCustom: "Custom"
automationsCountdownPreview: "Runs at {dateTime}"
```

- [ ] **Step 2: Write a widget/unit test** that builds `AutomationSchedulePicker` in a `TpTheme` harness, switches to recurring, and asserts no free-text `TextField` with hint `09:00` remains for the daily time row (find `TpTimePicker` instead). For countdown, selecting 15 minutes emits draft with `mode: countdown` and `countdownMinutes: 15`.

- [ ] **Step 3: Run — FAIL**

- [ ] **Step 4: Rewrite picker UI**

Structure:

1. Segmented mode control (Once | Countdown | Recurring).
2. **Once:** `TpFormField` date (`TpDatePicker` trigger showing `yyyy-MM-dd`) + time (`TpTimePicker`); validator: combined ms > now.
3. **Countdown:** chip row `5,15,30,60,120` + optional custom int field (minutes); live preview via `automationsCountdownPreview`.
4. **Recurring:** existing preset select; replace hourMinute `TextField` with `TpTimePicker` that writes `hourMinute` via `formatHourMinute`; keep hourly minute select and weekly/custom as today.

Default draft for create (when editor passes null initial): `mode: once`, onceDate/time from `defaultOnceDateTime`.

- [ ] **Step 5: Run picker/editor tests — PASS**

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/automations/automation_schedule_picker.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations*.dart \
  client/test/pages/automations/
git commit -m "$(cat <<'EOF'
feat(automations): three-mode schedule picker with Tp date/time

EOF
)"
```

---

### Task 7: Editor save / form wiring

**Files:**
- Modify: `client/lib/pages/automations/automation_editor_dialog.dart`
- Modify: `client/lib/pages/automations/automation_editor_form_body.dart`
- Modify: `client/test/pages/automations/automation_editor_dialog_test.dart`

**Interfaces:**
- Consumes: draft mode + helpers from Tasks 5–6
- Produces: saved `Automation` where:
  - Once / Countdown → `preset: once`, `runAtMs` set, `dtstartMs = runAtMs`, `maxRunCount: 1`, clear customCron/dayOfWeek as needed
  - Recurring → `runAtMs: null` (`clearRunAtMs`), existing preset fields, maxRunCount from field (unchanged)
  - Reject save if once/countdown `runAtMs <= now` (form error on time/date field)

- [ ] **Step 1: Extend editor dialog test** — create scheduled-message automation via dialog save path with countdown/once draft and assert cubit `save` receives `preset == once` and non-null `runAtMs`. Use existing dialog test harness patterns in `automation_editor_dialog_test.dart`.

- [ ] **Step 2: Run — FAIL** if save still forces daily/`09:00`

- [ ] **Step 3: Wire `_save` and form body**

In `_save`:

```dart
final now = DateTime.now();
final nowMs = now.millisecondsSinceEpoch;
int? runAtMs;
var preset = _schedule.preset;
int? maxRunCount = /* parse field */;

switch (_schedule.mode) {
  case AutomationScheduleMode.once:
  case AutomationScheduleMode.countdown:
    preset = AutomationSchedulePreset.once;
    runAtMs = _schedule.mode == AutomationScheduleMode.countdown
        ? countdownToRunAtMs(
            durationMinutes: _schedule.countdownMinutes ?? 15,
            now: now,
          )
        : combineLocalDateAndTimeToMs(
            date: _schedule.onceDate!,
            time: _schedule.onceTime,
            timezone: _schedule.timezone,
          );
    if (runAtMs <= nowMs) {
      form.setFieldError('scheduleHourMinute' /* or once field id */,
          l10n.automationsSchedulePastTime);
      return;
    }
    maxRunCount = 1;
  case AutomationScheduleMode.recurring:
    runAtMs = null;
}
```

Hide max-run `TpFormField` when `_schedule.mode != recurring` (or when resulting preset is once). Change create-path initial `_schedule` to once defaults from Task 5.

- [ ] **Step 4: Run editor tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/automations/automation_editor_dialog.dart \
  client/lib/pages/automations/automation_editor_form_body.dart \
  client/test/pages/automations/automation_editor_dialog_test.dart
git commit -m "$(cat <<'EOF'
feat(automations): save once and countdown as runAtMs schedules

EOF
)"
```

---

### Task 8: List summary + final verification

**Files:**
- Modify: `client/lib/pages/automations/automation_schedule_picker.dart` (`localizedScheduleSummary` — if not finished in Task 6)
- Modify: `client/lib/pages/automations/automations_list_body.dart` only if it bypasses `localizedScheduleSummary`
- Modify: any switch on `AutomationSchedulePreset` that must handle `once` (search repo)

- [ ] **Step 1: Grep for exhaustiveness**

```bash
cd /home/hhoa/git/hhoa/teampilot && rg -n "AutomationSchedulePreset\." client/lib client/test --glob '*.dart' | head -80
```

Fix every `switch` missing `once` (summary, calculator already done, formatScheduleSummary).

- [ ] **Step 2: Add/adjust summary test** asserting once → contains date and time digits.

- [ ] **Step 3: Run focused suite**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test \
  packages/shared_ui/test/components/date_range/tp_date_picker_test.dart \
  packages/shared_ui/test/components/time_picker/tp_time_picker_test.dart \
  test/models/automation_test.dart \
  test/services/automation/automation_schedule_calculator_test.dart \
  test/services/automation/automation_schedule_defaults_test.dart \
  test/services/automation/automation_scheduler_test.dart \
  test/services/automation/automation_dispatcher_test.dart \
  test/cubits/automation_cubit_test.dart \
  test/pages/automations/
```

- [ ] **Step 4: Full client test pass**

```bash
cd client && dart run tool/run_tests.dart
```

- [ ] **Step 5: Commit any leftover exhaustiveness / summary fixes**

```bash
git add -u client/lib client/test client/packages/shared_ui
git commit -m "$(cat <<'EOF'
fix(automations): handle once preset in summaries and switches

EOF
)"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `TpDatePicker` / `TpTimePicker` without `shadcn_ui` | 1, 2 |
| Modes Once / Countdown / Recurring | 6, 7 |
| Persist `once` + `runAtMs`; countdown → once | 3, 7 |
| Implicit max runs = 1 for once | 3, 7, 4 (dispatcher) |
| `dtstartMs = runAtMs` for once | 7 |
| Defaults: once now+15m; countdown 15m; recurring quarter-hour | 5, 6, 7 |
| Past once rejected | 6, 7 |
| Calculator once future/null; daily today-upcoming test | 4 |
| Clear next when null | 4 |
| List summary absolute time | 6, 8 |
| Hide max-run for once | 7 |
| No free-text HH:mm in schedule editor | 6 |

## Placeholder / consistency self-review

- No TBD left in tasks.
- `computeNextRunAtMs` → `int?` consistently across Task 4 callers.
- `effectiveMaxRunCount` used wherever `maxRunCount!` was used for limit checks.
- Draft field names (`onceDate`, `onceTime`, `countdownMinutes`, `mode`) match Tasks 6–7.
