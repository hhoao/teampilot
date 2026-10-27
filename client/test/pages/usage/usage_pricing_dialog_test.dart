import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_usage_pricing.dart';
import 'package:teampilot/pages/usage/usage_pricing_dialog.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

const _rule = UsagePriceRule(
  model: 'm',
  inputPerMillion: 1,
  outputPerMillion: 2,
  cacheReadPerMillion: 0.1,
  cacheWritePerMillion: 1.25,
  effectiveFromMs: 0,
);

Widget _host({
  required List<UsagePriceRule> initial,
  required Future<bool> Function(List<UsagePriceRule>) onSave,
  required Future<bool> Function() onReset,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => UsagePricingDialog(
              initialRules: initial,
              onSave: onSave,
              onReset: onReset,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('saves edited rules', (tester) async {
    var saved = const <UsagePriceRule>[];
    await tester.pumpWidget(
      _host(
        initial: const [_rule],
        onSave: (rules) async {
          saved = rules;
          return true;
        },
        onReset: () async => true,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.sessionUsagePricingDialog), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.sessionUsagePricingSaveButton));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single.model, 'm');
    expect(saved.single.inputPerMillion, 1);
    expect(find.byKey(AppKeys.sessionUsagePricingDialog), findsNothing);
  });

  testWidgets('adds a draft row', (tester) async {
    await tester.pumpWidget(
      _host(
        initial: const [],
        onSave: (_) async => true,
        onReset: () async => true,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(7));

    await tester.tap(find.byKey(AppKeys.sessionUsagePricingAddButton));
    await tester.pump();
    expect(find.byType(TextField), findsNWidgets(14));
  });

  testWidgets('resets after confirmation', (tester) async {
    var reset = false;
    await tester.pumpWidget(
      _host(
        initial: const [_rule],
        onSave: (_) async => true,
        onReset: () async {
          reset = true;
          return true;
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.sessionUsagePricingResetButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset defaults'));
    await tester.pumpAndSettle();

    expect(reset, isTrue);
    expect(find.byKey(AppKeys.sessionUsagePricingDialog), findsNothing);
  });
}
