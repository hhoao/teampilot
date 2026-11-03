import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/usage/usage_settings_dialog.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

Widget _wrap({
  bool autoSyncEnabled = true,
  int intervalMinutes = 10,
  ValueChanged<bool>? onAutoSyncChanged,
  ValueChanged<int>? onIntervalChanged,
  void Function(UsageSettingsAction?)? onResult,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        ColorScheme.fromSeed(seedColor: Colors.indigo),
        scale: 1,
      ),
      child: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await showDialog<UsageSettingsAction>(
                context: context,
                builder: (_) => UsageSettingsDialog(
                  autoSyncEnabled: autoSyncEnabled,
                  intervalMinutes: intervalMinutes,
                  onAutoSyncChanged: onAutoSyncChanged ?? (_) {},
                  onIntervalChanged: onIntervalChanged ?? (_) {},
                ),
              );
              onResult?.call(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the data source controls', (tester) async {
    await tester.pumpWidget(_wrap());
    await _open(tester);

    expect(find.byKey(AppKeys.sessionUsageSettingsDialog), findsOneWidget);
    expect(find.text('Auto-scan session logs'), findsOneWidget);
    expect(find.text('Every 10 min'), findsOneWidget);
    final toggle = tester.widget<Switch>(
      find.byKey(AppKeys.sessionUsageAutoScanSwitch),
    );
    expect(toggle.value, isTrue);
  });

  testWidgets('toggling auto scan reports the new value', (tester) async {
    bool? reported;
    await tester.pumpWidget(
      _wrap(onAutoSyncChanged: (value) => reported = value),
    );
    await _open(tester);

    await tester.tap(find.byKey(AppKeys.sessionUsageAutoScanSwitch));
    await tester.pumpAndSettle();

    expect(reported, isFalse);
  });

  testWidgets('changing the interval reports the new minutes', (tester) async {
    int? reported;
    await tester.pumpWidget(
      _wrap(onIntervalChanged: (minutes) => reported = minutes),
    );
    await _open(tester);

    await tester.tap(find.byKey(AppKeys.sessionUsageScanInterval));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every 30 min').last);
    await tester.pumpAndSettle();

    expect(reported, 30);
  });

  testWidgets('sync now closes the dialog with a sync action', (tester) async {
    UsageSettingsAction? result;
    await tester.pumpWidget(_wrap(onResult: (value) => result = value));
    await _open(tester);

    await tester.tap(find.byKey(AppKeys.sessionUsageSyncNowButton));
    await tester.pumpAndSettle();

    expect(result, UsageSettingsAction.syncNow);
    expect(find.byKey(AppKeys.sessionUsageSettingsDialog), findsNothing);
  });

  testWidgets('storage entry closes the dialog with a maintenance action', (
    tester,
  ) async {
    UsageSettingsAction? result;
    await tester.pumpWidget(_wrap(onResult: (value) => result = value));
    await _open(tester);

    await tester.tap(find.byKey(AppKeys.sessionUsageSettingsStorageEntry));
    await tester.pumpAndSettle();

    expect(result, UsageSettingsAction.maintenance);
  });
}
