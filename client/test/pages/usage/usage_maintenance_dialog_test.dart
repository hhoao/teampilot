import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/usage/usage_maintenance_dialog.dart';
import 'package:teampilot/services/usage/usage_store.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

Widget _host({
  UsageStoreStats? stats,
  required Future<bool> Function() onCompact,
  Future<bool> Function()? onFullSync,
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
            builder: (_) => UsageMaintenanceDialog(
              stats: stats,
              onCompact: onCompact,
              onFullSync: onFullSync ?? () async => true,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('compacts and closes', (tester) async {
    var compacted = 0;
    await tester.pumpWidget(
      _host(
        stats: const UsageStoreStats(
          lineCount: 10,
          eventCount: 5,
          sizeBytes: 2048,
        ),
        onCompact: () async {
          compacted++;
          return true;
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.sessionUsageMaintenanceDialog), findsOneWidget);
    expect(find.text('10 lines · 5 events'), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.sessionUsageCompactButton));
    await tester.pumpAndSettle();

    expect(compacted, 1);
    expect(find.byKey(AppKeys.sessionUsageMaintenanceDialog), findsNothing);
  });

  testWidgets('runs a manual full rescan', (tester) async {
    var fullSyncs = 0;
    await tester.pumpWidget(
      _host(
        stats: const UsageStoreStats(
          lineCount: 10,
          eventCount: 5,
          sizeBytes: 2048,
        ),
        onCompact: () async => true,
        onFullSync: () async {
          fullSyncs++;
          return true;
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.sessionUsageFullSyncButton));
    await tester.pumpAndSettle();

    expect(fullSyncs, 1);
    expect(find.byKey(AppKeys.sessionUsageMaintenanceDialog), findsNothing);
  });

  testWidgets('shows a failed compaction', (tester) async {
    await tester.pumpWidget(
      _host(
        stats: const UsageStoreStats(
          lineCount: 10,
          eventCount: 5,
          sizeBytes: 2048,
        ),
        onCompact: () async => false,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.sessionUsageCompactButton));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't compact usage storage."), findsOneWidget);
  });
}
