import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/progress_activity.dart';
import 'package:teampilot/widgets/notification/progress_activity_tile.dart';

ProgressActivity _activity({
  String title = 'Importing files',
  String? subtitle,
  bool cancellable = false,
  double? fraction,
  int? completedItems,
  int? totalItems,
}) {
  final at = DateTime(2026, 7, 30, 12);
  return ProgressActivity(
    id: 'activity-1',
    kind: ProgressActivityKind.fileTreeImport,
    title: title,
    subtitle: subtitle,
    phase: ProgressActivityPhase.running,
    fraction: fraction,
    completedItems: completedItems,
    totalItems: totalItems,
    cancellable: cancellable,
    createdAt: at,
    updatedAt: at,
  );
}

Widget _host({required Widget child}) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(colorScheme: scheme),
    home: TpTheme(
      data: TpThemeData.fromColorScheme(scheme, scale: 1),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('shows Cancel when cancellable and invokes onCancel', (
    tester,
  ) async {
    var cancelled = false;

    await tester.pumpWidget(
      _host(
        child: ProgressActivityTile(
          activity: _activity(cancellable: true),
          onTap: () {},
          onCancel: () => cancelled = true,
        ),
      ),
    );

    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    expect(cancelled, isTrue);
  });

  testWidgets('hides Cancel when not cancellable', (tester) async {
    await tester.pumpWidget(
      _host(
        child: ProgressActivityTile(
          activity: _activity(cancellable: false),
          onTap: () {},
          onCancel: () {},
        ),
      ),
    );

    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('shows subtitle when provided', (tester) async {
    await tester.pumpWidget(
      _host(
        child: ProgressActivityTile(
          activity: _activity(subtitle: 'readme.md'),
          onTap: () {},
          onCancel: () {},
        ),
      ),
    );

    expect(find.text('readme.md'), findsOneWidget);
  });

  testWidgets('uses determinate progress when fraction is known', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        child: ProgressActivityTile(
          activity: _activity(fraction: 0.42),
          onTap: () {},
          onCancel: () {},
        ),
      ),
    );

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.42);
  });

  testWidgets('uses indeterminate progress when fraction is unknown', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        child: ProgressActivityTile(
          activity: _activity(),
          onTap: () {},
          onCancel: () {},
        ),
      ),
    );

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, isNull);
  });
}
