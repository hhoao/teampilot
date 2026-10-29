import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/cursor_usage_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cursor_usage_account.dart';
import 'package:teampilot/models/cursor_usage_range.dart';
import 'package:teampilot/models/cursor_usage_report.dart';
import 'package:teampilot/pages/cursor_usage/cursor_usage_page.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUpTestAppStorage();
  tearDownTestAppStorage();

  CursorUsageCubit buildCubit() => CursorUsageCubit(
    loadAccounts: () async => const [
      CursorUsageAccount(
        accountId: 'a',
        userId: 'user_a',
        label: 'Work',
        source: CursorAccountSource.discovered,
      ),
    ],
    refreshAccount: (_) async {},
    billingCycleFor: (_) async => null,
    loadReport:
        ({
          required accountId,
          required range,
          billingCycle,
          forceRefresh = false,
        }) async => const CursorUsageReport(
          accountId: 'a',
          startMs: 0,
          endMs: 1,
          inputTokens: 1200,
          outputTokens: 300,
          totalCents: 42,
          eventCount: 3,
        ),
    saveRange: (_) async {},
    addAccount: (_, __) async => true,
    removeAccount: (_) async {},
    initialRange: const CursorUsagePresetRange(CursorUsagePreset.billingCycle),
  );

  testWidgets('renders the account and its totals', (tester) async {
    final cubit = buildCubit();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<CursorUsageCubit>.value(
          value: cubit,
          child: const Scaffold(body: CursorUsagePage(autoSync: false)),
        ),
      ),
    );
    await cubit.ensureLoaded();
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.cursorUsagePage), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.byKey(AppKeys.cursorUsageAddAccount), findsOneWidget);
  });
}
