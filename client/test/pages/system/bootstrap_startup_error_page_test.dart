import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/system/bootstrap_startup_error_page.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

void main() {
  testWidgets('Android error page shows Retry and Choose work environment', (
    tester,
  ) async {
    var retried = false;
    var choseEnv = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BootstrapStartupErrorPage(
          error: StateError('ssh down'),
          showChooseWorkEnvironment: true,
          showNativeStorageFallback: false,
          retrying: false,
          onRetry: () => retried = true,
          onChooseWorkEnvironment: () => choseEnv = true,
        ),
      ),
    );

    expect(find.text('Startup failed: Bad state: ssh down'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.bootstrapRetryButton));
    expect(retried, isTrue);

    await tester.tap(find.byKey(AppKeys.bootstrapChooseWorkEnvironmentButton));
    expect(choseEnv, isTrue);
  });

  testWidgets('shows native storage fallback when enabled', (tester) async {
    var usedNative = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BootstrapStartupErrorPage(
          error: StateError('wsl unavailable'),
          showChooseWorkEnvironment: false,
          showNativeStorageFallback: true,
          retrying: false,
          onRetry: () {},
          onNativeStorageFallback: () => usedNative = true,
        ),
      ),
    );

    expect(
      find.text('Use Windows local storage instead'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(AppKeys.bootstrapNativeStorageFallbackButton));
    expect(usedNative, isTrue);
  });

  testWidgets('disables action buttons while retrying', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BootstrapStartupErrorPage(
          error: StateError('ssh down'),
          showChooseWorkEnvironment: true,
          showNativeStorageFallback: true,
          retrying: true,
          onRetry: () {},
          onChooseWorkEnvironment: () {},
          onNativeStorageFallback: () {},
        ),
      ),
    );

    final retryButton = tester.widget<FilledButton>(
      find.byKey(AppKeys.bootstrapRetryButton),
    );
    expect(retryButton.onPressed, isNull);

    final chooseButton = tester.widget<FilledButton>(
      find.byKey(AppKeys.bootstrapChooseWorkEnvironmentButton),
    );
    expect(chooseButton.onPressed, isNull);

    final nativeButton = tester.widget<FilledButton>(
      find.byKey(AppKeys.bootstrapNativeStorageFallbackButton),
    );
    expect(nativeButton.onPressed, isNull);

    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });
}
