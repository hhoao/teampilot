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
        body: TpForm(
          child: SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
}

Future<_HostState> _pumpPicker(WidgetTester tester, AutomationScheduleDraft draft) async {
  tester.view.physicalSize = const Size(900, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_wrap(_Host(draft)));
  await tester.pump();
  return tester.state<_HostState>(find.byType(_Host));
}

void main() {
  testWidgets('once mode shows segmented modes, date picker, and time picker', (
    tester,
  ) async {
    await _pumpPicker(tester, _onceDraft());

    final segmented = tester
        .widget<TpSegmentedPicker<AutomationScheduleMode>>(
          find.byType(TpSegmentedPicker<AutomationScheduleMode>),
        );
    expect(
      segmented.segments.map((s) => s.value),
      [
        AutomationScheduleMode.once,
        AutomationScheduleMode.countdown,
        AutomationScheduleMode.recurring,
      ],
    );
    // Dialog host is narrow; the three modes must stay a visible pill.
    expect(segmented.mobileBreakpoint, 0);
    expect(find.text(_l10n.automationsScheduleModeOnce), findsOneWidget);
    expect(find.text(_l10n.automationsScheduleModeCountdown), findsOneWidget);
    expect(find.text(_l10n.automationsScheduleModeRecurring), findsOneWidget);

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

    await tester.tap(find.text(_l10n.automationsScheduleModeRecurring));
    await tester.pump();

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

  testWidgets('countdown mode emits minutes and shows a run preview', (
    tester,
  ) async {
    final host = await _pumpPicker(tester, _onceDraft());

    await tester.tap(find.text(_l10n.automationsScheduleModeCountdown));
    await tester.pump();
    await tester.tap(find.text(_l10n.automationsCountdownMinutes(15)));
    await tester.pump();

    final emitted = host.emissions.last;
    expect(emitted.mode, AutomationScheduleMode.countdown);
    expect(emitted.countdownMinutes, 15);

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            RegExp(r'^Runs at \d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(
              w.data ?? '',
            ),
      ),
      findsOneWidget,
    );
  });

  test('scheduleDraftFromAutomation maps once runAtMs to local date and time', () {
    final runAtMs =
        DateTime(2026, 9, 3, 14, 30).millisecondsSinceEpoch;
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
  });

  test('scheduleDraftFromAutomation maps recurring presets to recurring mode', () {
    final draft = scheduleDraftFromAutomation(
      sampleAutomation(id: 'daily-1', workspaceId: 'ws1'),
    );

    expect(draft.mode, AutomationScheduleMode.recurring);
    expect(draft.preset, AutomationSchedulePreset.daily);
    expect(draft.onceDate, isNull);
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
      scheduleDraftFromAutomation(sampleAutomation(id: 'd', workspaceId: 'ws1')),
    );
    expect(daily, 'Daily at 09:00');
  });
}
