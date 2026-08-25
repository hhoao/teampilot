import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/managed_provider/managed_provider_reset_countdown.dart';

void main() {
  group('ManagedProviderResetCountdown', () {
    test('label formats relative countdown', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final now = DateTime.fromMillisecondsSinceEpoch(1_800_000_000_000);
      final resetsAt = now.millisecondsSinceEpoch + const Duration(hours: 1, minutes: 40).inMilliseconds;

      expect(
        ManagedProviderResetCountdown.label(l10n, resetsAt, now: now),
        'Resets in 1h 40m',
      );
    });

    test('label returns soon when past reset time', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        ManagedProviderResetCountdown.label(
          l10n,
          1_000,
          now: DateTime.fromMillisecondsSinceEpoch(2_000),
        ),
        'Resets soon',
      );
    });
  });

  testWidgets('countdown label ticks down over time', (tester) async {
    const resetsAt = 1_800_000_000_000;
    final start = DateTime.fromMillisecondsSinceEpoch(1_799_999_000_000);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ManagedProviderResetCountdownLabel(
            resetsAt: resetsAt,
            now: start,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Resets in'), findsOneWidget);
    expect(find.text('Resets in 16m'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: ManagedProviderResetCountdownLabel(resetsAt: resetsAt),
        ),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('managed-provider-reset-countdown')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
