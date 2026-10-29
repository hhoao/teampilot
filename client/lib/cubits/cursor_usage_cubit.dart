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
    required Future<void> Function(String accountId, bool enabled)
    setAccountEnabled,
    Future<CursorUsageRange> Function()? loadRange,
    Future<CursorUsageReport?> Function({
      required String accountId,
      required CursorUsageRange range,
      CursorUsageWindow? billingCycle,
    })?
    peekReport,
    required CursorUsageRange initialRange,
  }) : _loadAccounts = loadAccounts,
       _refreshAccount = refreshAccount,
       _billingCycleFor = billingCycleFor,
       _loadReport = loadReport,
       _saveRange = saveRange,
       _addAccount = addAccount,
       _removeAccount = removeAccount,
       _setAccountEnabled = setAccountEnabled,
       _loadRange = loadRange,
       _peekReport = peekReport,
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
  final Future<void> Function(String accountId, bool enabled)
  _setAccountEnabled;
  final Future<CursorUsageRange> Function()? _loadRange;
  final Future<CursorUsageReport?> Function({
    required String accountId,
    required CursorUsageRange range,
    CursorUsageWindow? billingCycle,
  })?
  _peekReport;

  Future<void>? _loadFlight;

  /// Bumped by every [_loadAll] flight; a flight that sees a newer value stops
  /// publishing so a superseded load cannot overwrite fresher state.
  int _generation = 0;

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
    final generation = ++_generation;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final accounts = state.accounts
        .where((account) => account.enabled && !account.isExpired(nowMs))
        .toList();
    // Seed with this flight's accounts only: a superseded flight bails without
    // clearing its entries, so re-unioning a previous set would keep them (and
    // `isSyncing`) alive forever.
    final syncing = {for (final account in accounts) account.accountId};
    if (!isClosed) emit(state.copyWith(syncing: syncing));

    // Prune to the enabled set first: a removed or disabled account must not
    // keep a stale report, failure or cycle around (nor stay selected).
    final enabledIds = accounts.map((account) => account.accountId).toSet();
    final reports = {
      for (final entry in state.reports.entries)
        if (enabledIds.contains(entry.key)) entry.key: entry.value,
    };
    final failures = {
      for (final entry in state.failures.entries)
        if (enabledIds.contains(entry.key)) entry.key: entry.value,
    };
    final cycles = {
      for (final entry in state.billingCycles.entries)
        if (enabledIds.contains(entry.key)) entry.key: entry.value,
    };
    if (!isClosed && generation == _generation) {
      emit(
        state.copyWith(
          reports: Map.unmodifiable(reports),
          failures: Map.unmodifiable(failures),
          billingCycles: Map.unmodifiable(cycles),
        ),
      );
    }
    // Nothing to fetch (no accounts, or all disabled), but the prune above must
    // still have run so removing the last account clears its report.
    if (accounts.isEmpty) return;

    for (final account in accounts) {
      try {
        await _refreshAccount(account.accountId);
        if (isClosed || generation != _generation) return;
        final cycle = force
            ? await _billingCycleFor(account.accountId)
            : cycles[account.accountId] ??
                  await _billingCycleFor(account.accountId);
        if (isClosed || generation != _generation) return;
        if (cycle != null) cycles[account.accountId] = cycle;
        // Serve the cached numbers before the network call so a slow or
        // failing refresh never blanks out data that is already on disk.
        final peek = _peekReport;
        if (peek != null) {
          final cached = await peek(
            accountId: account.accountId,
            range: state.range,
            billingCycle: cycle,
          );
          if (isClosed || generation != _generation) return;
          if (cached != null) {
            reports[account.accountId] = cached;
            if (!isClosed) {
              emit(
                state.copyWith(
                  reports: Map.unmodifiable(reports),
                  failures: Map.unmodifiable(failures),
                  billingCycles: Map.unmodifiable(cycles),
                ),
              );
            }
          }
        }
        reports[account.accountId] = await _loadReport(
          accountId: account.accountId,
          range: state.range,
          billingCycle: cycle,
          forceRefresh: force,
        );
        if (isClosed || generation != _generation) return;
        failures.remove(account.accountId);
      } on CursorUsageException catch (error) {
        failures[account.accountId] = error.failure;
      } on Object {
        failures[account.accountId] = CursorUsageFailure.network;
      }
      if (isClosed || generation != _generation) return;
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
    // Keep the previous reports on screen while the new range loads: blanking
    // them makes every range switch look like the cache was lost. Each
    // account's numbers are replaced as its fetch lands, and the spinning
    // status dots show what is still in flight.
    emit(state.copyWith(range: range));
    await _saveRange(range);
    await _loadAll();
  }

  Future<void> refresh({bool force = false}) => _loadAll(force: force);

  Future<bool> addAccount(String rawToken, {String? label}) async {
    final ok = await _addAccount(rawToken, label);
    if (!ok) return false;
    // A flight that has already read the account list will not see the new
    // account, so let it finish before starting a fresh load.
    await _loadFlight;
    await ensureLoaded();
    return true;
  }

  Future<void> removeAccount(String accountId) async {
    await _removeAccount(accountId);
    await _loadFlight;
    await ensureLoaded();
  }

  Future<void> setAccountEnabled(String accountId, bool enabled) async {
    await _setAccountEnabled(accountId, enabled);
    await _loadFlight;
    await ensureLoaded();
  }
}
