import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/cursor_usage_account.dart';
import '../models/cursor_usage_range.dart';
import '../models/cursor_usage_report.dart';
import '../services/cursor_usage/cursor_usage_coordinator.dart';

enum CursorUsageStatus { initial, loading, ready, error }

final class CursorUsageState extends Equatable {
  const CursorUsageState({
    this.status = CursorUsageStatus.initial,
    this.accounts = const [],
    this.selectedAccountId,
    this.range = const CursorUsagePresetRange(CursorUsagePreset.billingCycle),
    this.reports = const {},
    this.failures = const {},
    this.syncing = const {},
    this.billingCycles = const {},
  });

  final CursorUsageStatus status;
  final List<CursorUsageAccount> accounts;
  final String? selectedAccountId;
  final CursorUsageRange range;
  final Map<String, CursorUsageReport> reports;
  final Map<String, CursorUsageFailure> failures;
  final Set<String> syncing;
  final Map<String, CursorUsageWindow> billingCycles;

  bool get isSyncing => syncing.isNotEmpty;

  CursorUsageReport? get selectedReport =>
      selectedAccountId == null ? null : reports[selectedAccountId];

  CursorUsageAccount? get selectedAccount {
    final id = selectedAccountId;
    if (id == null) return null;
    for (final account in accounts) {
      if (account.accountId == id) return account;
    }
    return null;
  }

  CursorUsageState copyWith({
    CursorUsageStatus? status,
    List<CursorUsageAccount>? accounts,
    String? selectedAccountId,
    bool clearSelection = false,
    CursorUsageRange? range,
    Map<String, CursorUsageReport>? reports,
    Map<String, CursorUsageFailure>? failures,
    Set<String>? syncing,
    Map<String, CursorUsageWindow>? billingCycles,
  }) => CursorUsageState(
    status: status ?? this.status,
    accounts: accounts ?? this.accounts,
    selectedAccountId: clearSelection
        ? null
        : selectedAccountId ?? this.selectedAccountId,
    range: range ?? this.range,
    reports: reports ?? this.reports,
    failures: failures ?? this.failures,
    syncing: syncing ?? this.syncing,
    billingCycles: billingCycles ?? this.billingCycles,
  );

  @override
  List<Object?> get props => [
    status,
    accounts,
    selectedAccountId,
    range,
    reports,
    failures,
    syncing,
    billingCycles,
  ];
}

final class CursorUsageCubit extends Cubit<CursorUsageState> {
  CursorUsageCubit({
    required Future<List<CursorUsageAccount>> Function() loadAccounts,
    required Future<void> Function(String accountId) refreshAccount,
    required Future<CursorUsageWindow?> Function(String accountId)
    billingCycleFor,
    required Future<CursorUsageReport> Function({
      required String accountId,
      required CursorUsageRange range,
      CursorUsageWindow? billingCycle,
      bool forceRefresh,
    })
    loadReport,
    required Future<void> Function(CursorUsageRange range) saveRange,
    required Future<bool> Function(String rawToken, String? label) addAccount,
    required Future<void> Function(String accountId) removeAccount,
    Future<CursorUsageRange> Function()? loadRange,
    required CursorUsageRange initialRange,
  }) : _loadAccounts = loadAccounts,
       _refreshAccount = refreshAccount,
       _billingCycleFor = billingCycleFor,
       _loadReport = loadReport,
       _saveRange = saveRange,
       _addAccount = addAccount,
       _removeAccount = removeAccount,
       _loadRange = loadRange,
       super(CursorUsageState(range: initialRange));

  final Future<List<CursorUsageAccount>> Function() _loadAccounts;
  final Future<void> Function(String accountId) _refreshAccount;
  final Future<CursorUsageWindow?> Function(String accountId) _billingCycleFor;
  final Future<CursorUsageReport> Function({
    required String accountId,
    required CursorUsageRange range,
    CursorUsageWindow? billingCycle,
    bool forceRefresh,
  })
  _loadReport;
  final Future<void> Function(CursorUsageRange range) _saveRange;
  final Future<bool> Function(String rawToken, String? label) _addAccount;
  final Future<void> Function(String accountId) _removeAccount;
  final Future<CursorUsageRange> Function()? _loadRange;

  Future<void>? _loadFlight;

  Future<void> ensureLoaded() => _loadFlight ??= _load().whenComplete(() {
    _loadFlight = null;
  });

  Future<void> _load({bool force = false}) async {
    if (state.status == CursorUsageStatus.initial) {
      final loader = _loadRange;
      if (loader != null) {
        final saved = await loader();
        if (!isClosed && saved != state.range) {
          emit(state.copyWith(range: saved));
        }
      }
    }
    if (!isClosed) emit(state.copyWith(status: CursorUsageStatus.loading));
    final List<CursorUsageAccount> accounts;
    try {
      accounts = await _loadAccounts();
    } on Object {
      if (!isClosed) emit(state.copyWith(status: CursorUsageStatus.error));
      return;
    }
    final selected = state.selectedAccountId;
    final keep = accounts.any((account) => account.accountId == selected);
    final nextSelection = keep
        ? selected
        : (accounts.isEmpty ? null : accounts.first.accountId);
    if (!isClosed) {
      emit(
        state.copyWith(
          status: CursorUsageStatus.ready,
          accounts: accounts,
          selectedAccountId: nextSelection,
          clearSelection: nextSelection == null,
        ),
      );
    }
    await _loadAll(force: force);
  }

  Future<void> _loadAll({bool force = false}) async {
    final accounts = state.accounts
        .where((account) => account.enabled)
        .toList();
    if (accounts.isEmpty) return;
    final syncing = {...state.syncing, for (final a in accounts) a.accountId};
    if (!isClosed) emit(state.copyWith(syncing: syncing));

    final reports = {...state.reports};
    final failures = {...state.failures};
    final cycles = {...state.billingCycles};

    for (final account in accounts) {
      try {
        await _refreshAccount(account.accountId);
        final cycle = force
            ? await _billingCycleFor(account.accountId)
            : cycles[account.accountId] ??
                  await _billingCycleFor(account.accountId);
        if (cycle != null) cycles[account.accountId] = cycle;
        reports[account.accountId] = await _loadReport(
          accountId: account.accountId,
          range: state.range,
          billingCycle: cycle,
          forceRefresh: force,
        );
        failures.remove(account.accountId);
      } on CursorUsageException catch (error) {
        failures[account.accountId] = error.failure;
      } on Object {
        failures[account.accountId] = CursorUsageFailure.network;
      }
      if (isClosed) return;
      emit(
        state.copyWith(
          syncing: {...state.syncing}..remove(account.accountId),
          reports: Map.unmodifiable(reports),
          failures: Map.unmodifiable(failures),
          billingCycles: Map.unmodifiable(cycles),
        ),
      );
    }
  }

  void selectAccount(String? accountId) {
    if (accountId == null) {
      emit(state.copyWith(clearSelection: true));
    } else {
      emit(state.copyWith(selectedAccountId: accountId));
    }
  }

  Future<void> setRange(CursorUsageRange range) async {
    if (range == state.range) return;
    emit(state.copyWith(range: range, reports: const {}));
    await _saveRange(range);
    await _loadAll();
  }

  Future<void> refresh({bool force = false}) => _loadAll(force: force);

  Future<bool> addAccount(String rawToken, {String? label}) async {
    final ok = await _addAccount(rawToken, label);
    if (ok) await _load();
    return ok;
  }

  Future<void> removeAccount(String accountId) async {
    await _removeAccount(accountId);
    await _load();
  }
}
