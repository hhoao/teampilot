import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/ssh_profiles/credential_push_opt_in_tile.dart';

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('defaults off and reflects opted-in state', (tester) async {
    await tester.pumpWidget(_host(
      CredentialPushOptInTile(
        host: 'box.example',
        optedIn: false,
        onChanged: (_) {},
        confirmTrustBoundary: () async => true,
      ),
    ));
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('enabling shows confirm; confirmed → onChanged(true)',
      (tester) async {
    bool? changed;
    await tester.pumpWidget(_host(
      CredentialPushOptInTile(
        host: 'box.example',
        optedIn: false,
        onChanged: (v) => changed = v,
        confirmTrustBoundary: () async => true,
      ),
    ));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(changed, isTrue);
  });

  testWidgets('enabling but cancelling confirm → onChanged not called',
      (tester) async {
    bool? changed;
    await tester.pumpWidget(_host(
      CredentialPushOptInTile(
        host: 'box.example',
        optedIn: false,
        onChanged: (v) => changed = v,
        confirmTrustBoundary: () async => false,
      ),
    ));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(changed, isNull);
  });

  testWidgets('disabling persists false immediately (no confirm)',
      (tester) async {
    bool? changed;
    var confirmCalled = false;
    await tester.pumpWidget(_host(
      CredentialPushOptInTile(
        host: 'box.example',
        optedIn: true,
        onChanged: (v) => changed = v,
        confirmTrustBoundary: () async {
          confirmCalled = true;
          return true;
        },
      ),
    ));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(changed, isFalse);
    expect(confirmCalled, isFalse);
  });

  testWidgets('real confirm dialog names the host and confirms', (tester) async {
    bool? changed;
    await tester.pumpWidget(_host(
      CredentialPushOptInTile(
        host: 'box.example',
        optedIn: false,
        onChanged: (v) => changed = v,
      ),
    ));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    // dialog shows + names the host
    expect(find.textContaining('box.example'), findsWidgets);
    final l10n = AppLocalizations.of(tester.element(find.byType(FilledButton)));
    await tester.tap(find.text(l10n.credentialPushConfirmAction));
    await tester.pumpAndSettle();
    expect(changed, isTrue);
  });
}
