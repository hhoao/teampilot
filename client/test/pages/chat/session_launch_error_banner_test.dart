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
  testWidgets(
    'compose card shows title, hides details until reviewed, then retries',
    (tester) async {
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

      expect(find.text("Couldn't start session"), findsOneWidget);
      expect(find.text('spawn failed'), findsNothing);
      expect(find.text('View details'), findsOneWidget);

      await tester.tap(find.byKey(AppKeys.sessionLaunchErrorReviewButton));
      await tester.pumpAndSettle();
      expect(find.text('spawn failed'), findsOneWidget);
      expect(find.text('Hide details'), findsOneWidget);

      await tester.tap(find.byKey(AppKeys.sessionLaunchErrorRetryButton));
      await tester.pump();
      expect(retried, isTrue);
    },
  );

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
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('compact shows short title, not raw error', (tester) async {
    final view = presentSessionLaunchFailure(
      'process exited with code 1\n/lib64/libstdc++.so.6: version not found',
    )!;
    await tester.pumpWidget(
      _wrap(
        SessionLaunchErrorBanner(
          view: view,
          compact: true,
          onRetry: () {},
        ),
      ),
    );
    expect(find.text("Couldn't start session"), findsOneWidget);
    expect(find.textContaining('libstdc++'), findsNothing);
    expect(find.byKey(AppKeys.sessionLaunchErrorRetryButton), findsOneWidget);
  });

  testWidgets(
    'compose card shows full multi-line detail when reviewed',
    (tester) async {
      final long = List<String>.generate(8, (i) => 'error line $i').join('\n');
      final view = presentSessionLaunchFailure(long)!;
      await tester.pumpWidget(
        _wrap(
          SessionLaunchErrorBanner(
            view: view,
            onRetry: () {},
          ),
        ),
      );

      await tester.tap(find.byKey(AppKeys.sessionLaunchErrorReviewButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('error line 0'), findsOneWidget);
      expect(find.textContaining('error line 7'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    },
  );
}
