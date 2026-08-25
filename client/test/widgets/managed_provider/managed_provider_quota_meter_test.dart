import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/widgets/managed_provider/managed_provider_quota_meter.dart';

void main() {
  testWidgets('quota meter shows progress bar, remaining label, and reset time', (
    tester,
  ) async {
    const resetsAt = 1_800_000_000_000;
    final now = DateTime.fromMillisecondsSinceEpoch(1_799_400_000_000);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ManagedProviderQuotaMeter(
            measure: ProviderUsageMeasure(
              label: '5h',
              kind: ProviderUsageMeasureKind.quota,
              total: '100',
              used: '0',
              remaining: '100',
              unit: '%',
              resetsAt: resetsAt,
            ),
            display: ManagedProviderDisplayConfig(),
            resetsAt: resetsAt,
            now: now,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('managed-provider-quota-meter')), findsOneWidget);
    expect(find.byKey(const Key('managed-provider-usage-progress')), findsOneWidget);
    expect(find.text('100% remaining'), findsOneWidget);
    expect(find.textContaining('Resets in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quota meter uses Chinese remaining label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ManagedProviderQuotaMeter(
            measure: ProviderUsageMeasure(
              label: '5h',
              kind: ProviderUsageMeasureKind.quota,
              total: '100',
              used: '25',
              remaining: '75',
              unit: '%',
            ),
            display: ManagedProviderDisplayConfig(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('75剩余 %'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('low remaining quota uses tertiary bar without warning icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ManagedProviderQuotaMeter(
                measure: ProviderUsageMeasure(
                  label: '5h',
                  kind: ProviderUsageMeasureKind.quota,
                  total: '100',
                  used: '92',
                  remaining: '8',
                  unit: '%',
                ),
                display: ManagedProviderDisplayConfig(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    final cs = Theme.of(tester.element(find.byType(Scaffold))).colorScheme;
    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('managed-provider-usage-progress')),
    );
    expect(
      (progress.valueColor as AlwaysStoppedAnimation<Color>).value,
      cs.tertiary,
    );
    expect(
      find.byKey(const Key('managed-provider-usage-warning')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('error warning uses error bar color and warning icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ManagedProviderQuotaMeter(
                measure: ProviderUsageMeasure(
                  label: '5h',
                  kind: ProviderUsageMeasureKind.quota,
                  total: '100',
                  used: '0',
                  remaining: '80',
                  unit: '%',
                ),
                display: ManagedProviderDisplayConfig(),
                warning: true,
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    final cs = Theme.of(tester.element(find.byType(Scaffold))).colorScheme;
    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('managed-provider-usage-progress')),
    );
    expect(
      (progress.valueColor as AlwaysStoppedAnimation<Color>).value,
      cs.error,
    );
    expect(
      find.byKey(const Key('managed-provider-usage-warning')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
