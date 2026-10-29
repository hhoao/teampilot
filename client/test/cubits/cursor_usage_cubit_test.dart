import 'dart:async';

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
        expiresAtMs: 4000000000000,
);
const _accountB = CursorUsageAccount(
  accountId: 'b',
  userId: 'user_b',
  label: 'B',
  source: CursorAccountSource.manual,
        expiresAtMs: 4000000000000,
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
            mode = CursorUsageSyncMode.auto,
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
      setAccountEnabled: (_, __) async {},
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
            mode = CursorUsageSyncMode.auto,
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
      setAccountEnabled: (_, __) async {},
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
            mode = CursorUsageSyncMode.auto,
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
      setAccountEnabled: (_, __) async {},
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

  test('a failed refresh keeps the peeked report visible', () async {
    final cubit = CursorUsageCubit(
      loadAccounts: () async => [_accountA],
      refreshAccount: (_) async {},
      billingCycleFor: (_) async => null,
      peekReport:
          ({
            required accountId,
            required range,
            billingCycle,
          }) async => const CursorUsageReport(
            accountId: 'a',
            startMs: 0,
            endMs: 1,
            inputTokens: 99,
          ),
      loadReport:
          ({
            required accountId,
            required range,
            billingCycle,
            mode = CursorUsageSyncMode.auto,
          }) async => throw StateError('boom'),
      saveRange: (_) async {},
      addAccount: (_, _) async => true,
      removeAccount: (_) async {},
      setAccountEnabled: (_, __) async {},
      initialRange: const CursorUsagePresetRange(CursorUsagePreset.today),
    );

    await cubit.ensureLoaded();

    expect(cubit.state.failures['a'], CursorUsageFailure.network);
    expect(cubit.state.reports['a']!.inputTokens, 99);
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
            mode = CursorUsageSyncMode.auto,
          }) async => CursorUsageReport(
            accountId: accountId,
            startMs: 0,
            endMs: 1,
            inputTokens: accountId == 'a' ? 10 : 20,
          ),
      saveRange: (_) async {},
      addAccount: (_, _) async => true,
      removeAccount: (_) async {},
      setAccountEnabled: (_, __) async {},
      initialRange: const CursorUsagePresetRange(CursorUsagePreset.today),
    );

    await cubit.ensureLoaded();
    cubit.selectAccount('b');

    expect(cubit.state.selectedAccountId, 'b');
    expect(cubit.state.selectedReport!.inputTokens, 20);
  });

  test('first load selects the first account', () async {
    final cubit = CursorUsageCubit(
      loadAccounts: () async => [_accountA, _accountB],
      refreshAccount: (_) async {},
      billingCycleFor: (_) async => null,
      loadReport:
          ({
            required accountId,
            required range,
            billingCycle,
            mode = CursorUsageSyncMode.auto,
          }) async => CursorUsageReport(
            accountId: accountId,
            startMs: 0,
            endMs: 1,
            inputTokens: accountId == 'a' ? 10 : 20,
          ),
      saveRange: (_) async {},
      addAccount: (_, _) async => true,
      removeAccount: (_) async {},
      setAccountEnabled: (_, __) async {},
      initialRange: const CursorUsagePresetRange(CursorUsagePreset.today),
    );

    await cubit.ensureLoaded();

    expect(cubit.state.selectedAccountId, 'a');
    expect(cubit.state.selectedReport, isNotNull);
  });

  test(
    'forced refresh re-reads the billing cycle, plain refresh does not',
    () async {
      var cycleReads = 0;
      final cubit = CursorUsageCubit(
        loadAccounts: () async => [_accountA],
        refreshAccount: (_) async {},
        billingCycleFor: (_) async {
          cycleReads++;
          return const CursorUsageWindow(startMs: 100, endMs: 200);
        },
        loadReport:
            ({
              required accountId,
              required range,
              billingCycle,
              mode = CursorUsageSyncMode.auto,
            }) async =>
                CursorUsageReport(accountId: accountId, startMs: 0, endMs: 1),
        saveRange: (_) async {},
        addAccount: (_, _) async => true,
        removeAccount: (_) async {},
        setAccountEnabled: (_, __) async {},
        initialRange: const CursorUsagePresetRange(
          CursorUsagePreset.billingCycle,
        ),
      );

      await cubit.ensureLoaded();
      expect(cycleReads, 1);

      await cubit.syncFull();
      expect(cycleReads, 2);

      await cubit.syncIncremental();
      expect(cycleReads, 2);
    },
  );

  test('a superseded flight cannot publish stale reports', () async {
    // One gate per requested range: each flight parks in `loadReport` until
    // its gate opens, so the release order is under the test's control.
    final gates = <int, Completer<void>>{};
    const rangeA = CursorUsageCustomRange(startMs: 1000, endMs: 2000);
    const rangeB = CursorUsageCustomRange(startMs: 3000, endMs: 4000);
    int tagOf(CursorUsageRange range) => switch (range) {
      CursorUsageCustomRange(:final startMs) => startMs,
      CursorUsagePresetRange() => -1,
    };

    final cubit = CursorUsageCubit(
      loadAccounts: () async => [_accountA, _accountB],
      refreshAccount: (_) async {},
      billingCycleFor: (_) async => null,
      loadReport:
          ({
            required accountId,
            required range,
            billingCycle,
            mode = CursorUsageSyncMode.auto,
          }) async {
            final tag = tagOf(range);
            await gates.putIfAbsent(tag, Completer<void>.new).future;
            return CursorUsageReport(
              accountId: accountId,
              startMs: tag,
              endMs: tag + 1,
            );
          },
      saveRange: (_) async {},
      addAccount: (_, _) async => true,
      removeAccount: (_) async {},
      setAccountEnabled: (_, __) async {},
      initialRange: const CursorUsagePresetRange(CursorUsagePreset.today),
    );

    final initial = cubit.ensureLoaded();
    await pumpEventQueue();
    final changeA = cubit.setRange(rangeA);
    await pumpEventQueue();
    final changeB = cubit.setRange(rangeB);
    await pumpEventQueue();
    expect(gates.keys, containsAll([-1, 1000, 3000]));

    // Newest first, superseded initial flight last: without the generation
    // guard its preset-range numbers land on top of B's reports.
    gates[3000]!.complete();
    gates[1000]!.complete();
    gates[-1]!.complete();
    await Future.wait([initial, changeA, changeB]);
    await pumpEventQueue();

    expect(cubit.state.range, rangeB);
    expect(cubit.state.reports.keys, containsAll(['a', 'b']));
    for (final report in cubit.state.reports.values) {
      expect(report.startMs, rangeB.startMs);
    }
  });

  test('removed accounts are pruned from state', () async {
    final accounts = <CursorUsageAccount>[_accountA, _accountB];
    final cubit = CursorUsageCubit(
      loadAccounts: () async => [...accounts],
      refreshAccount: (_) async {},
      billingCycleFor: (_) async => null,
      loadReport:
          ({
            required accountId,
            required range,
            billingCycle,
            mode = CursorUsageSyncMode.auto,
          }) async =>
              CursorUsageReport(accountId: accountId, startMs: 0, endMs: 1),
      saveRange: (_) async {},
      addAccount: (_, _) async => true,
      removeAccount: (accountId) async {
        accounts.removeWhere((account) => account.accountId == accountId);
      },
      setAccountEnabled: (_, _) async {},
      initialRange: const CursorUsagePresetRange(CursorUsagePreset.today),
    );

    await cubit.ensureLoaded();
    cubit.selectAccount('b');
    expect(cubit.state.reports.containsKey('b'), isTrue);

    await cubit.removeAccount('b');

    expect(cubit.state.accounts.map((account) => account.accountId).toList(), [
      'a',
    ]);
    expect(cubit.state.reports.containsKey('b'), isFalse);
    expect(cubit.state.selectedAccountId, isNot('b'));
  });

  test('isSyncing recovers after a removal during an in-flight load', () async {
    // The first two flights park in `loadReport` until their own gate opens.
    final gates = <Completer<void>>[];
    final accounts = <CursorUsageAccount>[_accountA, _accountB];
    final cubit = CursorUsageCubit(
      loadAccounts: () async => [...accounts],
      refreshAccount: (_) async {},
      billingCycleFor: (_) async => null,
      loadReport:
          ({
            required accountId,
            required range,
            billingCycle,
            mode = CursorUsageSyncMode.auto,
          }) async {
            if (gates.length < 2) {
              final gate = Completer<void>();
              gates.add(gate);
              await gate.future;
            }
            return CursorUsageReport(
              accountId: accountId,
              startMs: 0,
              endMs: 1,
            );
          },
      saveRange: (_) async {},
      addAccount: (_, _) async => true,
      removeAccount: (accountId) async {
        accounts.removeWhere((account) => account.accountId == accountId);
      },
      setAccountEnabled: (_, _) async {},
      initialRange: const CursorUsagePresetRange(CursorUsagePreset.today),
    );

    final load = cubit.ensureLoaded();
    await pumpEventQueue();
    expect(cubit.state.isSyncing, isTrue);

    // Supersede the initial flight so it bails mid-way with `b` still marked
    // as syncing.
    final superseded = cubit.syncIncremental();
    await pumpEventQueue();
    final removal = cubit.removeAccount('b');
    await pumpEventQueue();
    expect(gates.length, 2);

    gates[0].complete();
    await Future.wait([load, removal]);
    await pumpEventQueue();

    gates[1].complete();
    await superseded;
    await pumpEventQueue();

    expect(cubit.state.accounts.map((account) => account.accountId).toList(), [
      'a',
    ]);
    expect(cubit.state.isSyncing, isFalse);
    expect(cubit.state.syncing, isEmpty);
  });

  test('removing the last account clears every report', () async {
    final accounts = <CursorUsageAccount>[_accountA];
    final cubit = CursorUsageCubit(
      loadAccounts: () async => [...accounts],
      refreshAccount: (_) async {},
      billingCycleFor: (_) async => null,
      loadReport:
          ({
            required accountId,
            required range,
            billingCycle,
            mode = CursorUsageSyncMode.auto,
          }) async =>
              CursorUsageReport(accountId: accountId, startMs: 0, endMs: 1),
      saveRange: (_) async {},
      addAccount: (_, _) async => true,
      removeAccount: (accountId) async {
        accounts.removeWhere((account) => account.accountId == accountId);
      },
      setAccountEnabled: (_, _) async {},
      initialRange: const CursorUsagePresetRange(CursorUsagePreset.today),
    );

    await cubit.ensureLoaded();
    expect(cubit.state.reports.keys, ['a']);
    expect(cubit.state.selectedAccountId, 'a');

    await cubit.removeAccount('a');

    expect(cubit.state.accounts, isEmpty);
    expect(cubit.state.reports, isEmpty);
    expect(cubit.state.selectedAccountId, isNull);
    expect(cubit.state.isSyncing, isFalse);
  });

  test('a mutation during an in-flight load is reflected', () async {
    final gate = Completer<void>();
    var gated = false;
    final accounts = <CursorUsageAccount>[_accountA];
    final cubit = CursorUsageCubit(
      loadAccounts: () async => [...accounts],
      refreshAccount: (_) async {},
      billingCycleFor: (_) async => null,
      loadReport:
          ({
            required accountId,
            required range,
            billingCycle,
            mode = CursorUsageSyncMode.auto,
          }) async {
            if (!gated) {
              gated = true;
              await gate.future;
            }
            return CursorUsageReport(
              accountId: accountId,
              startMs: 0,
              endMs: 1,
            );
          },
      saveRange: (_) async {},
      addAccount: (_, _) async {
        accounts.add(_accountB);
        return true;
      },
      removeAccount: (_) async {},
      setAccountEnabled: (_, __) async {},
      initialRange: const CursorUsagePresetRange(CursorUsagePreset.today),
    );

    final load = cubit.ensureLoaded();
    await pumpEventQueue();
    final added = cubit.addAccount('token');
    await pumpEventQueue();

    gate.complete();
    await Future.wait([load, added]);
    await pumpEventQueue();

    expect(cubit.state.accounts.map((account) => account.accountId).toList(), [
      'a',
      'b',
    ]);
    expect(cubit.state.reports.containsKey('b'), isTrue);
  });

  test('setAccountEnabled persists and reloads', () async {
    final calls = <(String, bool)>[];
    final cubit = CursorUsageCubit(
      loadAccounts: () async => const [
        CursorUsageAccount(
          accountId: 'a',
          userId: 'user_a',
          label: 'A',
          source: CursorAccountSource.discovered,
        expiresAtMs: 4000000000000,
        ),
      ],
      refreshAccount: (_) async {},
      billingCycleFor: (_) async => null,
      loadReport:
          ({
            required accountId,
            required range,
            billingCycle,
            mode = CursorUsageSyncMode.auto,
          }) async =>
              CursorUsageReport(accountId: accountId, startMs: 0, endMs: 1),
      saveRange: (_) async {},
      addAccount: (_, __) async => true,
      removeAccount: (_) async {},
      setAccountEnabled: (accountId, value) async =>
          calls.add((accountId, value)),
      initialRange: const CursorUsagePresetRange(CursorUsagePreset.today),
    );

    await cubit.ensureLoaded();
    await cubit.setAccountEnabled('a', false);

    expect(calls, [('a', false)]);
  });
}
