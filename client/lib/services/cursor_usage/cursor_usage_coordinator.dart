import 'package:collection/collection.dart';

import '../../models/cursor_usage_account.dart';
import '../../models/cursor_usage_range.dart';
import '../../models/cursor_usage_report.dart';
import 'cursor_account_registry.dart';
import 'cursor_usage_api_client.dart';
import 'cursor_usage_cache.dart';
import 'cursor_usage_cache_store.dart';
import 'cursor_usage_range_math.dart';

/// Why a [CursorUsageCoordinator] load could not produce a report.
enum CursorUsageFailure {
  login,
  rateLimited,
  network,
  http,
  invalidResponse,
  accountMismatch,
  rangeTooLarge,
  noCredential,
}

class CursorUsageException implements Exception {
  const CursorUsageException(this.failure, this.message);

  final CursorUsageFailure failure;
  final String message;

  @override
  String toString() => message;
}

/// Fills the cache for the requested range, then reports from the cache.
///
/// A load only asks Cursor for the windows the cache does not already cover,
/// so switching ranges back and forth costs nothing after the first fetch.
final class CursorUsageCoordinator {
  CursorUsageCoordinator({
    required CursorAccountDirectory registry,
    required CursorUsageCacheStore cacheStore,
    required CursorUsageApi api,
    DateTime Function()? now,
    int maxPages = 40,
    int pageSize = 500,
  }) : _registry = registry,
       _cacheStore = cacheStore,
       _api = api,
       _now = now ?? DateTime.now,
       _maxPages = maxPages,
       _pageSize = pageSize;

  final CursorAccountDirectory _registry;
  final CursorUsageCacheStore _cacheStore;
  final CursorUsageApi _api;
  final DateTime Function() _now;
  final int _maxPages;
  final int _pageSize;

  Future<CursorUsageWindow?> billingCycleFor(String accountId) async {
    final credentials = await _registry.credentialFor(accountId);
    if (credentials == null) return null;
    try {
      return await _api.fetchBillingCycle(credentials: credentials);
    } on CursorUsageApiException {
      return null;
    }
  }

  Future<CursorUsageReport> load({
    required String accountId,
    required CursorUsageRange range,
    CursorUsageWindow? billingCycle,
    bool forceRefresh = false,
  }) async {
    final credentials = await _registry.credentialFor(accountId);
    if (credentials == null) {
      throw const CursorUsageException(
        CursorUsageFailure.noCredential,
        'No live Cursor credential for this account',
      );
    }
    final nowMs = _now().millisecondsSinceEpoch;
    final resolved = cursorUsageResolveRange(
      range: range,
      nowMs: nowMs,
      billingCycle: billingCycle,
    );
    final window = CursorUsageWindow(
      startMs: resolved.startMs,
      endMs: resolved.endMs > nowMs ? nowMs : resolved.endMs,
    );

    var cache = await _cacheStore.load(accountId);
    final account = (await _registry.list())
        .where((row) => row.accountId == accountId)
        .firstOrNull;
    final teamId = account?.teamId ?? 0;
    final durableOwner = account?.owningUser;
    final gaps = forceRefresh
        ? [cursorUsageAlignWindow(window)]
        : cursorUsageMissingWindows(covered: cache.coverage, requested: window);

    for (final gap in gaps) {
      cache = await _fillGap(
        cache: cache,
        credentials: credentials,
        gap: gap,
        teamId: teamId,
        initialOwner: durableOwner,
      );
    }
    return buildCursorUsageReport(cache, window: window);
  }

  Future<CursorUsageCache> _fillGap({
    required CursorUsageCache cache,
    required CursorAccountCredentials credentials,
    required CursorUsageWindow gap,
    required int teamId,
    required String? initialOwner,
  }) async {
    final collected = <CursorUsageEvent>[];
    var boundOwningUser = cache.owningUser ?? initialOwner;
    var page = 1;
    var total = 0;
    while (page <= _maxPages) {
      final CursorUsagePage response;
      try {
        response = await _api.fetchPage(
          credentials: credentials,
          startMs: gap.startMs,
          endMs: gap.endMs,
          page: page,
          pageSize: _pageSize,
          teamId: teamId,
        );
      } on CursorUsageApiException catch (error) {
        throw CursorUsageException(_failureFor(error.code), error.message);
      }
      // Later pages may report a smaller total than earlier ones; keep the
      // largest claim so a short page cannot hide a truncated result.
      if (response.totalCount > total) total = response.totalCount;
      collected.addAll(response.events);
      if (response.events.isEmpty) break;
      if (collected.length >= total) break;
      page++;
    }
    // Fewer events than Cursor promised means the fetch was truncated (paging
    // ceiling, or a totalCount that counts events outside the range). Caching
    // it would mark the whole gap covered and under-count until a refresh.
    if (collected.length < total) {
      throw CursorUsageException(
        page > _maxPages
            ? CursorUsageFailure.rangeTooLarge
            : CursorUsageFailure.invalidResponse,
        'Cursor returned ${collected.length} of $total events',
      );
    }
    if (teamId == 0) {
      final owners = collected.map(_owningUserOf).whereType<String>().toSet();
      if (owners.length > 1) {
        throw const CursorUsageException(
          CursorUsageFailure.accountMismatch,
          'Cursor returned events for more than one user',
        );
      }
      final owner = owners.isEmpty ? null : owners.first;
      if (owner != null) {
        if (boundOwningUser != null && boundOwningUser != owner) {
          throw const CursorUsageException(
            CursorUsageFailure.accountMismatch,
            'The Cursor session belongs to a different account',
          );
        }
        boundOwningUser = owner;
        if (owner != cache.owningUser) {
          await _registry.update(cache.accountId, owningUser: owner);
        }
      }
    }

    final next = applyCursorUsageEvents(
      cache,
      collected,
      window: gap,
      owningUser: boundOwningUser,
    );
    final trimmed = trimCursorUsageCache(
      next,
      nowMs: _now().millisecondsSinceEpoch,
    );
    await _cacheStore.save(trimmed);
    return trimmed;
  }

  /// Cursor leaves `owningUser` empty for personal accounts; an empty value is
  /// "unknown", not an owner, so it must not look like a second account.
  static String? _owningUserOf(CursorUsageEvent event) =>
      event.owningUser.isEmpty ? null : event.owningUser;

  static CursorUsageFailure _failureFor(CursorUsageApiError code) =>
      switch (code) {
        CursorUsageApiError.login => CursorUsageFailure.login,
        CursorUsageApiError.rateLimited => CursorUsageFailure.rateLimited,
        CursorUsageApiError.network => CursorUsageFailure.network,
        CursorUsageApiError.http => CursorUsageFailure.http,
        CursorUsageApiError.invalidResponse =>
          CursorUsageFailure.invalidResponse,
      };
}
