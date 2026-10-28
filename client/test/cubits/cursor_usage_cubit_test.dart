import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/cursor_usage_cubit.dart';
import 'package:teampilot/models/cursor_usage_account.dart';
import 'package:teampilot/models/cursor_usage_range.dart';
import 'package:teampilot/models/cursor_usage_report.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_coordinator.dart';

const _accountA = CursorUsageAccount(
  accountId: 'a',
  userId: 'user_a',
  label: 'A',
  source: CursorAccountSource.discovered,
);
const _accountB = CursorUsageAccount(
  accountId: 'b',
  userId: 'user_b',
  label: 'B',
  source: CursorAccountSource.manual,
);

void main() {
  test('loads accounts then reports for every account', () async {
    final loaded = <String>[];
    final cubit = CursorUsageCubit(
      loadAccounts: () async => [_accountA, _accountB],
      refreshAccount: (_) async {},
      billingCycleFor: (_) async => null,
      loadReport:
          ({
            required accountId,
            required range,
            billingCycle,
            forceRefresh = false,
          }) async {
            loaded.add(accountId);
            return CursorUsageReport(
              accountId: accountId,
              startMs: 0,
              endMs: 1,
              inputTokens: accountId == 'a' ? 10 : 20,
            );
          },
      saveRange: (_) async {},
      addAccount: (_, _) async => true,
      removeAccount: (_) async {},
      initialRange: const CursorUsagePresetRange(
        CursorUsagePreset.billingCycle,
      ),
    );

    await cubit.ensureLoaded();

    expect(cubit.state.status, CursorUsageStatus.ready);
    expect(cubit.state.accounts.length, 2);
    expect(loaded, ['a', 'b']);
    expect(cubit.state.reports['a']!.inputTokens, 10);
    expect(cubit.state.isSyncing, isFalse);
  });

  test('one failing account does not block the other', () async {
    final cubit = CursorUsageCubit(
      loadAccounts: () async => [_accountA, _accountB],
      refreshAccount: (_) async {},
      billingCycleFor: (_) async => null,
      loadReport:
          ({
            required accountId,
            required range,
            billingCycle,
            forceRefresh = false,
          }) async {
            if (accountId == 'a') throw StateError('boom');
            return CursorUsageReport(
              accountId: accountId,
              startMs: 0,
              endMs: 1,
            );
          },
      saveRange: (_) async {},
      addAccount: (_, _) async => true,
      removeAccount: (_) async {},
      initialRange: const CursorUsagePresetRange(CursorUsagePreset.today),
    );

    await cubit.ensureLoaded();

    expect(cubit.state.failures['a'], CursorUsageFailure.network);
    expect(cubit.state.reports['b'], isNotNull);
  });

  test('changing the range persists it and reloads', () async {
    final saved = <CursorUsageRange>[];
    var loads = 0;
    final cubit = CursorUsageCubit(
      loadAccounts: () async => [_accountA],
      refreshAccount: (_) async {},
      billingCycleFor: (_) async =>
          const CursorUsageWindow(startMs: 100, endMs: 200),
      loadReport:
          ({
            required accountId,
            required range,
            billingCycle,
            forceRefresh = false,
          }) async {
            loads++;
            return CursorUsageReport(
              accountId: accountId,
              startMs: 0,
              endMs: 1,
            );
          },
      saveRange: (range) async => saved.add(range),
      addAccount: (_, _) async => true,
      removeAccount: (_) async {},
      initialRange: const CursorUsagePresetRange(
        CursorUsagePreset.billingCycle,
      ),
    );

    await cubit.ensureLoaded();
    await cubit.setRange(CursorUsageCustomRange(startMs: 1000, endMs: 2000));

    expect(saved.length, 1);
    expect(loads, 2);
    expect(cubit.state.range, isA<CursorUsageCustomRange>());
    expect(cubit.state.billingCycles['a']!.startMs, 100);
  });

  test('selecting an account exposes its report', () async {
    final cubit = CursorUsageCubit(
      loadAccounts: () async => [_accountA, _accountB],
      refreshAccount: (_) async {},
      billingCycleFor: (_) async => null,
      loadReport:
          ({
            required accountId,
            required range,
            billingCycle,
            forceRefresh = false,
          }) async => CursorUsageReport(
            accountId: accountId,
            startMs: 0,
            endMs: 1,
            inputTokens: accountId == 'a' ? 10 : 20,
          ),
      saveRange: (_) async {},
      addAccount: (_, _) async => true,
      removeAccount: (_) async {},
      initialRange: const CursorUsagePresetRange(CursorUsagePreset.today),
    );

    await cubit.ensureLoaded();
    cubit.selectAccount('b');

    expect(cubit.state.selectedAccountId, 'b');
    expect(cubit.state.selectedReport!.inputTokens, 20);
  });
}
