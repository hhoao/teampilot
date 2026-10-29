import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cursor_usage_report.dart';
import 'package:teampilot/pages/cursor_usage/widgets/model_breakdown.dart';
import 'package:teampilot/pages/cursor_usage/widgets/usage_detail.dart';
import 'package:teampilot/pages/cursor_usage/widgets/usage_totals.dart';

void main() {
  const report = CursorUsageReport(
    accountId: 'a',
    startMs: 0,
    endMs: 1,
    inputTokens: 1500,
    outputTokens: 2500,
    cacheReadTokens: 10000,
    cacheWriteTokens: 0,
    totalCents: 1234,
    eventCount: 7,
    models: {
      'cursor-grok-4.6-high': CursorUsageModelTotals(
        inputTokens: 1500,
        outputTokens: 2500,
        cacheReadTokens: 10000,
        totalCents: 1000,
        eventCount: 5,
      ),
      '': CursorUsageModelTotals(totalCents: 234, eventCount: 2),
    },
  );

  testWidgets('totals render the token buckets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CursorUsageTotals(report: report),
      ),
    );
    expect(find.text('1.5K'), findsOneWidget);
  });

  testWidgets('model breakdown folds the empty model into unattributed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CursorUsageModelBreakdown(report: report),
      ),
    );
    expect(find.textContaining('cursor-grok-4.6-high'), findsOneWidget);
  });

  test('unattributed slice is merged from the empty model key', () {
    final slices = cursorUsageModelSlices(report);
    expect(slices.length, 2);
    expect(slices.first.model, 'cursor-grok-4.6-high');
    expect(
      slices.map((slice) => slice.model),
      contains(cursorUsageUnattributedModel),
    );
  });

  const withEvents = CursorUsageReport(
    accountId: 'a',
    startMs: 0,
    endMs: 1,
    inputTokens: 1500,
    outputTokens: 2500,
    cacheReadTokens: 10000,
    totalCents: 1234,
    eventCount: 2,
    models: {
      'cursor-grok-4.6-high': CursorUsageModelTotals(
        inputTokens: 1500,
        outputTokens: 2500,
        cacheReadTokens: 10000,
        totalCents: 1000,
        eventCount: 1,
      ),
      '': CursorUsageModelTotals(totalCents: 234, eventCount: 1),
    },
    events: [
      CursorUsageEvent(
        eventId: 'e1',
        timestampMs: 1700000000000,
        model: 'cursor-grok-4.6-high',
        kind: 'usage',
        inputTokens: 100,
        outputTokens: 200,
        totalCents: 12,
      ),
      CursorUsageEvent(
        eventId: 'e2',
        timestampMs: 1700000060000,
        model: '',
        kind: 'usage',
        totalCents: 3,
      ),
    ],
  );

  Widget host(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('detail lays out event rows without overflow at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        const CursorUsageDetail(report: withEvents, account: null, cycle: null),
      ),
    );

    expect(tester.takeException(), isNull);
    // One from the model breakdown slice, one from the event row.
    expect(find.text('Unattributed'), findsNWidgets(2));
  });

  testWidgets('summary-only report explains why there are no rows', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      host(
        const CursorUsageDetail(
          report: CursorUsageReport(
            accountId: 'a',
            startMs: 0,
            endMs: 1,
            eventCount: 3,
            totalCents: 5,
            summaryOnly: true,
          ),
          account: null,
          cycle: null,
        ),
      ),
    );

    expect(find.text(l10n.cursorUsageSummaryOnly), findsOneWidget);
    expect(find.text(l10n.cursorUsageNoData), findsOneWidget);
  });

  testWidgets('an empty report shows no-data in both empty sections', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      host(
        const CursorUsageDetail(
          report: CursorUsageReport(accountId: 'a', startMs: 0, endMs: 1),
          account: null,
          cycle: null,
        ),
      ),
    );

    expect(find.text(l10n.cursorUsageNoData), findsNWidgets(2));
  });
}
