import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/session_launch_error_banner.dart';
import 'package:teampilot/pages/chat/session_launch_failure_presenter.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

Widget _wrap(Widget child) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('shows message and invokes onRetry', (tester) async {
    var retried = false;
    final view = presentSessionLaunchFailure('spawn failed')!;
    await tester.pumpWidget(
      _wrap(
        SessionLaunchErrorBanner(
          view: view,
          onRetry: () => retried = true,
        ),
      ),
    );
    expect(find.text('spawn failed'), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.sessionLaunchErrorRetryButton));
    await tester.pump();
    expect(retried, isTrue);
  });

  testWidgets('shows remap CTA for dead SSH', (tester) async {
    final view = presentSessionLaunchFailure(
      'No SSH profile for target "ssh:x"',
    )!;
    await tester.pumpWidget(
      _wrap(
        SessionLaunchErrorBanner(
          view: view,
          onRetry: () {},
          onRemapDeadTarget: () {},
        ),
      ),
    );
    expect(find.text('Remap machine…'), findsOneWidget);
    expect(find.byKey(AppKeys.sessionLaunchErrorRetryButton), findsOneWidget);
    expect(find.byType(TextButton), findsNWidgets(2));
  });

  testWidgets('disables retry while isRetrying', (tester) async {
    final view = presentSessionLaunchFailure('spawn failed')!;
    await tester.pumpWidget(
      _wrap(
        SessionLaunchErrorBanner(
          view: view,
          onRetry: () {},
          isRetrying: true,
        ),
      ),
    );
    final button = tester.widget<TextButton>(
      find.byKey(AppKeys.sessionLaunchErrorRetryButton),
    );
    expect(button.onPressed, isNull);
  });
}
