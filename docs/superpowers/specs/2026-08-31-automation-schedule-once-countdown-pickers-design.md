# Automation schedule: once, countdown, and Tp date/time pickers

## Problem

Creating scheduled messages and launch-prompt automations is awkward:

1. There is no **one-shot** schedule for a specific date and time (including today).
2. There is no **countdown** entry path (relative duration → absolute run time).
3. Recurring schedules default to `09:00`, so “today at a near-future time” is easy to miss even though `computeNextRunAtMs` already supports today’s upcoming slot.
4. Time is entered as free-text `HH:mm`, which is hard to use.

## Goals

- Three editor modes: **Once** | **Countdown** | **Recurring**.
- Once and countdown produce a durable one-shot run at an absolute instant.
- Recurring schedules can target today’s still-upcoming time; new defaults avoid hard-coded `09:00`.
- Introduce `TpDatePicker` and `TpTimePicker` in `shared_ui`, aligned with [flutter-shadcn-ui Date Picker](https://mariuti.com/flutter-shadcn-ui/components/date-picker/) and [Time Picker](https://mariuti.com/flutter-shadcn-ui/components/time-picker/) interaction, without depending on the `shadcn_ui` package.
- Keep existing TeamBus / dispatcher delivery paths unchanged.

## Non-goals (this iteration)

- 12-hour AM/PM time picker variant.
- Second-level precision.
- Date-range schedules.
- Persisting a distinct “countdown” schedule kind.
- Changing how messages/prompts are delivered after a run fires.

## Architecture

```
Editor UI (3 modes)
  ├─ Once        → TpDatePicker + TpTimePicker → preset=once, runAtMs
  ├─ Countdown   → relative duration UI        → same once payload (no stored mode)
  └─ Recurring   → existing presets + TpTimePicker → existing cron fields

Automation model / JSON
  └─ AutomationScheduleCalculator.computeNextRunAtMs
       └─ AutomationScheduler / Dispatcher (once ⇒ maxRunCount semantics)
```

## Section 1 — shared_ui: `TpDatePicker` / `TpTimePicker`

### Principles

- Match shadcn date/time picker UX (popover calendar; segmented hour/minute inputs).
- Implement as `Tp*` on top of existing `TpPopover`, `TpTheme`, and `calendar_date_utils`.
- **Do not** add a `shadcn_ui` dependency (avoids dual `ShadTheme` / `TpTheme`).

### `TpDatePicker` (single day)

- Trigger + popover calendar, same structural pattern as existing `TpDateRangePicker`, but single-day selection.
- API sketch: `selected` / `onChanged`, `closeOnSelection`, `firstDate` / `lastDate`, optional `header` (e.g. Today / Tomorrow shortcuts).
- Range selection remains `TpDateRangePicker`; this work does not rewrite range.

### `TpTimePicker`

- Align with `ShadTimePicker` **primary** (24h): hour + minute fields (typed digits with clamping; optional step buttons if they fit the Tp control density).
- **Hide seconds by default** (scheduling only needs minutes).
- `initialValue` / `onChanged` use Flutter `TimeOfDay` (no parallel type).
- Optional trailing clock icon.
- No `.period` (12h) variant in this iteration.

### Forms

- Compose inside existing `TpFormField` builders (same pattern as `TpSelect`).
- No separate Shad-style `*FormField` hierarchy required.

### Packaging

- Export from `shared_ui.dart`.
- Widget tests for single-day select/close and hour/minute changes.

## Section 2 — Editor modes and data model

### Mode switch

Top of the schedule section: segmented control **Once | Countdown | Recurring** (`TpSegmentedControl` or equivalent).

| Mode | UI | Persistence |
|------|----|-------------|
| **Once** | `TpDatePicker` + `TpTimePicker`; date from today onward; combined local wall time | `preset: once`, `runAtMs` = absolute epoch ms |
| **Countdown** | Relative duration: chips (5 / 15 / 30 min, 1 / 2 h) + custom N minutes/hours; preview absolute time | **Not stored as a mode**; save writes the same `once` + `runAtMs` payload |
| **Recurring** | Existing hourly / daily / weekdays / weekly / custom; time via `TpTimePicker` (replace free-text `HH:mm`) | Existing fields; `hourMinute` still derived from the picker |

### Model changes

- Add `AutomationSchedulePreset.once`.
- Add optional `runAtMs` (required when `preset == once`).
- For `once`, effective run limit is **1** (`maxRunCount` implicit / UI hidden).
- `dtstartMs`: unchanged meaning for recurring; for `once`, set equal to `runAtMs` at create/save (single rule).
- List / summary copy: `once` → localized `YYYY-MM-DD HH:mm`; after countdown save, summary matches once.

### Editing existing automations

- `preset == once` → open **Once** with date/time from `runAtMs`.
- Recurring presets → **Recurring**.
- Countdown is create-only; edit always shows Once for one-shots.

### New-create defaults

| Kind | Default |
|------|---------|
| Mode | **Once** (scheduled message and launch-prompt) |
| Once | Date = today; time = now + 15 minutes (roll to tomorrow if that crosses midnight) |
| Countdown | Preselect 15 minutes |
| Recurring | `daily`; time = now rounded up to next 15-minute slot (not `09:00`) |

## Section 3 — Calculator, validation, timezone, tests

### Calculator

- `once`: if `runAtMs > afterMs` return `runAtMs`; else return `null` (expired / disable path).
- Recurring paths unchanged; add tests that today’s still-upcoming `daily` / `weekdays` / `weekly` land on **today**.
- Dispatcher: after a successful `once` run, treat as run-limit reached and disable (same as `maxRunCount: 1`). Missed past `runAtMs` uses existing missed/skip handling.

### Validation on save

- `once`: `runAtMs` required and **strictly greater than now**; reject past times with l10n error.
- Countdown: duration > 0; converted `runAtMs` must also be in the future.
- Recurring: keep cron / field validation; `TpTimePicker` guarantees a legal `HH:mm`.

### Timezone

- Keep existing `timezone` string on `Automation`.
- Pickers display in local wall time; compose `runAtMs` using the automation timezone location (same resolution / UTC fallback as `AutomationScheduleCalculator` today).

### Test matrix

| Area | Cases |
|------|--------|
| shared_ui | `TpDatePicker` select + close; `TpTimePicker` hour/minute change |
| model | `once` JSON round-trip + `validate()` |
| calculator | once future/past; daily today-upcoming |
| editor | mode draft switching; countdown saves as once; recurring has no free-text time field |

## Error handling

- Invalid / past once times: field-level form error; do not save.
- Unresolvable timezone name: unchanged calculator fallback to UTC; document in UI only if already surfaced elsewhere (no new toast required).

## Migration

- Existing automations without `once` / `runAtMs` load unchanged.
- Missing `runAtMs` on `preset: once` fails validation (corrupt / hand-edited JSON).

## Success criteria

1. User can schedule a one-shot for later today via Once or Countdown.
2. Recurring new automations default to a near-future clock time and can fire today when that time is still ahead.
3. No free-text `HH:mm` in the schedule editor; date/time use Tp pickers.
4. Countdown never appears as a stored preset; lists show absolute once times.
5. Analyzer + targeted unit/widget tests for the above pass.
