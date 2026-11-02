import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/vault/vault_entry_detail.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('secret field masks by default, reveals, then re-masks', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const VaultSecretField(
          label: 'Password',
          value: 'hunter2',
          secret: true,
          revealDuration: Duration(seconds: 1),
        ),
      ),
    );

    expect(find.text('hunter2'), findsNothing);
    expect(find.textContaining('••'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(find.text('hunter2'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('hunter2'), findsNothing);
  });

  testWidgets('copy-only entries hide the reveal button', (tester) async {
    await tester.pumpWidget(
      _host(
        const VaultSecretField(
          label: 'Private key',
          value: 'PEM',
          secret: true,
          revealable: false,
        ),
      ),
    );

    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
  });
}
