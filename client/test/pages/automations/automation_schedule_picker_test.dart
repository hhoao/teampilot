import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/pages/automations/automation_schedule_picker.dart';
import 'package:teampilot/services/automation/automation_schedule_defaults.dart';

import '../../support/automation_test_fixtures.dart';

AppLocalizations get _l10n => lookupAppLocalizations(const Locale('en'));

AutomationScheduleDraft _onceDraft() => AutomationScheduleDraft(
  mode: AutomationScheduleMode.once,
  preset: AutomationSchedulePreset.once,
  minute: 0,
  hourMinute: '09:00',
  timezone: 'UTC',
  onceDate: DateTime(2026, 9, 3),
  onceTime: const TimeOfDay(hour: 9, minute: 15),
  countdownMinutes: 15,
);

/// Stateful host echoing emitted drafts back into the picker, mirroring how
/// [AutomationEditorDialog] owns the draft.
class _Host extends StatefulWidget {
  const _Host(this.initialDraft);

  final AutomationScheduleDraft initialDraft;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late AutomationScheduleDraft draft = widget.initialDraft;
  final List<AutomationScheduleDraft> emissions = [];

  @override
  Widget build(BuildContext context) {
    return AutomationSchedulePicker(
      draft: draft,
      labelWidth: 160,
      onChanged: (next) => setState(() {
        draft = next;
        emissions.add(next);
      }),
    );
  }
}

Widget _wrap(Widget child) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(colorScheme: scheme, useMaterial3: true),
    home: TpTheme(
      data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
      child: Scaffold(
        body: TpForm(child: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

Future<_HostState> _pumpPicker(
  WidgetTester tester,
  AutomationScheduleDraft draft,
) async {
  tester.view.physicalSize = const Size(900, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_wrap(_Host(draft)));
  await tester.pump();
  return tester.state<_HostState>(find.byType(_Host));
}

Future<void> _selectScheduleMode(
  WidgetTester tester,
  AppLocalizations l10n,
  AutomationScheduleMode mode,
) async {
  await tester.tap(find.byType(TpSelect<AutomationScheduleMode>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(scheduleModeLabel(l10n, mode)).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('once mode shows schedule mode select, date picker, and time picker', (
    tester,
  ) async {
    await _pumpPicker(tester, _onceDraft());

    final modeSelect = tester.widget<TpSelect<AutomationScheduleMode>>(
      find.byType(TpSelect<AutomationScheduleMode>),
    );
    expect(modeSelect.items, AutomationScheduleMode.values);
    expect(modeSelect.initialItem, AutomationScheduleMode.once);
    expect(find.text(_l10n.automationsScheduleModeOnce), findsOneWidget);

    expect(find.byType(TpDatePicker), findsOneWidget);
    // Trigger renders the selected day as yyyy-MM-dd.
    expect(find.text('2026-09-03'), findsOneWidget);
    expect(find.byType(TpTimePicker), findsOneWidget);
    expect(find.text('09'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
  });

  testWidgets('recurring mode drops the free-text time field and once preset', (
    tester,
  ) async {
    final host = await _pumpPicker(tester, _onceDraft());

    await _selectScheduleMode(
      tester,
      _l10n,
      AutomationScheduleMode.recurring,
    );

    final emitted = host.emissions.last;
    expect(emitted.mode, AutomationScheduleMode.recurring);
    // Mode once maps to preset once; going back to recurring falls back to daily.
    expect(emitted.preset, AutomationSchedulePreset.daily);

    final select = tester.widget<TpSelect<AutomationSchedulePreset>>(
      find.byType(TpSelect<AutomationSchedulePreset>),
    );
    expect(select.items, isNot(contains(AutomationSchedulePreset.once)));
    expect(find.byType(TpTimePicker), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '09:00',
      ),
      findsNothing,
    );
  });

  testWidgets('switching to once seeds a missing once slot with defaults', (
    tester,
  ) async {
    // A recurring-only draft has never had a once date/time; entering once
    // mode must seed them (instead of the rows falling back to a 09:00
    // placeholder) so the emitted draft always carries a complete slot.
    final host = await _pumpPicker(
      tester,
      AutomationScheduleDraft(
        mode: AutomationScheduleMode.recurring,
        preset: AutomationSchedulePreset.daily,
        minute: 0,
        hourMinute: '09:00',
        timezone: 'UTC',
      ),
    );

    await _selectScheduleMode(
      tester,
      _l10n,
      AutomationScheduleMode.once,
    );

    final emitted = host.emissions.last;
    expect(emitted.mode, AutomationScheduleMode.once);
    expect(emitted.onceDate, isNotNull);
    expect(emitted.onceTime, isNotNull);

    // Seed contract: 15 minutes out from now, matching defaultOnceDateTime.
    final seeded = DateTime.now().add(const Duration(minutes: 15));
    expect(emitted.onceDate, DateTime(seeded.year, seeded.month, seeded.day));
    expect(
      emitted.onceTime,
      TimeOfDay(hour: seeded.hour, minute: seeded.minute),
    );
  });

  testWidgets('custom cron field keeps trailing space through host echo', (
    tester,
  ) async {
    final host = await _pumpPicker(tester, _onceDraft());

    await _selectScheduleMode(
      tester,
      _l10n,
      AutomationScheduleMode.recurring,
    );
    // Open the preset select and pick Custom so the cron TextField mounts.
    await tester.tap(find.byType(TpSelect<AutomationSchedulePreset>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.automationsScheduleCustom).last);
    await tester.pumpAndSettle();

    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '0 */2 * * *',
    );
    expect(field, findsOneWidget);

    // Type like a user would: '0' commits the draft, then a trailing space.
    await tester.enterText(field, '0');
    await tester.pump();
    await tester.enterText(field, '0 ');
    // Host setState echoes the trimmed draft back through didUpdateWidget;
    // the two-clause guard must not resync (and eat the space) in that case.
    await tester.pump();

    final text = tester.widget<TextField>(field).controller!.text;
    expect(text, '0 ');
    expect(host.emissions.last.customCron, '0');
  });

  testWidgets('countdown mode emits minutes and shows a run preview', (
    tester,
  ) async {
    final host = await _pumpPicker(tester, _onceDraft());

    await _selectScheduleMode(
      tester,
      _l10n,
      AutomationScheduleMode.countdown,
    );
    await tester.tap(find.byType(TpSelectWithCustomInput));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.automationsCountdownMinutes(15)).last);
    await tester.pumpAndSettle();

    final emitted = host.emissions.last;
    expect(emitted.mode, AutomationScheduleMode.countdown);
    expect(emitted.countdownMinutes, 15);

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            RegExp(
              r'^Runs at \d{4}-\d{2}-\d{2} \d{2}:\d{2}$',
            ).hasMatch(w.data ?? ''),
      ),
      findsOneWidget,
    );
  });

  test(
    'scheduleDraftFromAutomation maps once runAtMs to local date and time',
    () {
      final runAtMs = DateTime(2026, 9, 3, 14, 30).millisecondsSinceEpoch;
      final draft = scheduleDraftFromAutomation(
        sampleAutomation(
          id: 'once-1',
          workspaceId: 'ws1',
          preset: AutomationSchedulePreset.once,
          runAtMs: runAtMs,
        ),
      );

      expect(draft.mode, AutomationScheduleMode.once);
      expect(draft.onceDate, DateTime(2026, 9, 3));
      expect(draft.onceTime, const TimeOfDay(hour: 14, minute: 30));
      // Carried verbatim so the save path can round-trip the stored target
      // without recomposing it from local wall clock.
      expect(draft.runAtMs, runAtMs);
    },
  );

  test(
    'scheduleDraftFromAutomation maps recurring presets to recurring mode',
    () {
      final draft = scheduleDraftFromAutomation(
        sampleAutomation(id: 'daily-1', workspaceId: 'ws1'),
      );

      expect(draft.mode, AutomationScheduleMode.recurring);
      expect(draft.preset, AutomationSchedulePreset.daily);
      expect(draft.onceDate, isNull);
    },
  );

  test(
    'list summary for a saved once automation shows the stored date-time',
    () {
      final runAtMs = DateTime(2026, 9, 3, 14, 30).millisecondsSinceEpoch;
      final automation = sampleAutomation(
        id: 'once-summary',
        workspaceId: 'ws1',
        preset: AutomationSchedulePreset.once,
        runAtMs: runAtMs,
      );

      // Exactly the expression AutomationsListBody renders per row, so a
      // stale hourMinute fallback ('Once at 09:00') fails here.
      final summary = localizedScheduleSummary(
        _l10n,
        scheduleDraftFromAutomation(automation),
      );

      expect(summary, 'Once at 2026-09-03 14:30');
    },
  );

  test('parseCountdownMinutesSelectValue accepts presets and custom minutes', () {
    expect(parseCountdownMinutesSelectValue(_l10n, '15'), 15);
    expect(
      parseCountdownMinutesSelectValue(
        _l10n,
        _l10n.automationsCountdownMinutes(30),
      ),
      30,
    );
    expect(
      parseCountdownMinutesSelectValue(
        _l10n,
        _l10n.automationsCountdownHours(2),
      ),
      120,
    );
    expect(parseCountdownMinutesSelectValue(_l10n, ''), isNull);
    expect(parseCountdownMinutesSelectValue(_l10n, 'abc'), isNull);
  });

  test('forCreate seeds once defaults from the provided now', () {
    final draft = AutomationScheduleDraft.forCreate(
      timezone: 'UTC',
      now: DateTime(2026, 9, 1, 10, 3),
    );

    expect(draft.mode, AutomationScheduleMode.once);
    expect(draft.preset, AutomationSchedulePreset.once);
    expect(draft.onceDate, DateTime(2026, 9, 1));
    expect(draft.onceTime, const TimeOfDay(hour: 10, minute: 18));
    expect(draft.countdownMinutes, 15);
    expect(draft.hourMinute, '10:15');
    expect(draft.timezone, 'UTC');
  });

  test('localizedScheduleSummary renders once, countdown, and recurring', () {
    final once = localizedScheduleSummary(_l10n, _onceDraft());
    expect(once, 'Once at 2026-09-03 09:15');

    final countdown = localizedScheduleSummary(
      _l10n,
      AutomationScheduleDraft(
        mode: AutomationScheduleMode.countdown,
        preset: AutomationSchedulePreset.daily,
        minute: 0,
        hourMinute: '09:00',
        timezone: 'UTC',
        countdownMinutes: 15,
      ),
    );
    expect(countdown, '15 min');

    final daily = localizedScheduleSummary(
      _l10n,
      scheduleDraftFromAutomation(
        sampleAutomation(id: 'd', workspaceId: 'ws1'),
      ),
    );
    expect(daily, 'Daily at 09:00');
  });

  group('resolveDraftRunAtMs', () {
    test(
      'reuses the raw stored target while once date and time are untouched',
      () {
        final runAtMs = DateTime(2026, 9, 3, 14, 30).millisecondsSinceEpoch;
        final draft = scheduleDraftFromAutomation(
          sampleAutomation(
            id: 'once-raw',
            workspaceId: 'ws1',
            preset: AutomationSchedulePreset.once,
            runAtMs: runAtMs,
          ),
        );

        // Recomposing wall clock through the draft timezone can shift the
        // instant; the untouched draft must carry the stored ms verbatim.
        expect(resolveDraftRunAtMs(draft, now: DateTime(2026, 9, 1)), runAtMs);
      },
    );

    test('recomposes from date and time after the user changes the time', () {
      final runAtMs = DateTime(2026, 9, 3, 14, 30).millisecondsSinceEpoch;
      final draft = scheduleDraftFromAutomation(
        sampleAutomation(
          id: 'once-time',
          workspaceId: 'ws1',
          preset: AutomationSchedulePreset.once,
          runAtMs: runAtMs,
        ),
      ).copyWith(onceTime: const TimeOfDay(hour: 16, minute: 45));

      final resolved = resolveDraftRunAtMs(draft, now: DateTime(2026, 9, 1));
      expect(resolved, isNot(runAtMs));
      expect(
        resolved,
        combineLocalDateAndTimeToMs(
          date: draft.onceDate!,
          time: const TimeOfDay(hour: 16, minute: 45),
          timezone: draft.timezone,
        ),
      );
    });

    test('recomposes from date and time after the user changes the date', () {
      final runAtMs = DateTime(2026, 9, 3, 14, 30).millisecondsSinceEpoch;
      final draft = scheduleDraftFromAutomation(
        sampleAutomation(
          id: 'once-date',
          workspaceId: 'ws1',
          preset: AutomationSchedulePreset.once,
          runAtMs: runAtMs,
        ),
      ).copyWith(onceDate: DateTime(2026, 9, 10));

      final resolved = resolveDraftRunAtMs(draft, now: DateTime(2026, 9, 1));
      expect(resolved, isNot(runAtMs));
      expect(
        resolved,
        combineLocalDateAndTimeToMs(
          date: DateTime(2026, 9, 10),
          time: draft.onceTime!,
          timezone: draft.timezone,
        ),
      );
    });

    test('composes the countdown target from now', () {
      final draft = _onceDraft().copyWith(
        mode: AutomationScheduleMode.countdown,
        countdownMinutes: 20,
      );

      expect(
        resolveDraftRunAtMs(draft, now: DateTime(2026, 9, 1, 10, 0)),
        DateTime(2026, 9, 1, 10, 20).millisecondsSinceEpoch,
      );
    });

    test('returns null without a once slot or for recurring drafts', () {
      expect(
        resolveDraftRunAtMs(
          AutomationScheduleDraft(
            mode: AutomationScheduleMode.once,
            preset: AutomationSchedulePreset.once,
            minute: 0,
            hourMinute: '09:00',
            timezone: 'UTC',
          ),
          now: DateTime(2026, 9, 1),
        ),
        isNull,
      );
      expect(
        resolveDraftRunAtMs(
          AutomationScheduleDraft(
            mode: AutomationScheduleMode.recurring,
            preset: AutomationSchedulePreset.daily,
            minute: 0,
            hourMinute: '09:00',
            timezone: 'UTC',
          ),
          now: DateTime(2026, 9, 1),
        ),
        isNull,
      );
    });
  });
}
