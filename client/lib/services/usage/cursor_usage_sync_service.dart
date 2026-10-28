import 'dart:async';

import 'package:http/http.dart' as http;

import '../../models/cursor_usage_import.dart';
import '../../models/session_usage.dart';
import '../cli/cursor/provider/cursor_usage_auth_resolver.dart';
import 'cursor_usage_csv.dart';
import 'cursor_usage_import_store.dart';

enum CursorUsageSyncError { login, rateLimited, network, http, invalidCsv }

class CursorUsageSyncException implements Exception {
  const CursorUsageSyncException(this.code, this.message);

  final CursorUsageSyncError code;
  final String message;

  @override
  String toString() => message;
}

/// Imports the Cursor dashboard CSV and optionally downloads it from
/// cursor.com with the app's own Cursor session.
///
/// This is deliberately separate from the per-session scanner: Cursor's
/// dashboard rows are account-level (they include IDE and CLI requests) and
/// replace the local estimates for the covered period.
final class CursorUsageSyncService {
  CursorUsageSyncService({
    required CursorUsageImportStore store,
    required CursorUsageAuthResolver auth,
    http.Client? httpClient,
    Uri? exportUri,
    DateTime Function()? now,
    Duration timeout = const Duration(seconds: 45),
  }) : _store = store,
       _auth = auth,
       _http = httpClient,
       _exportUri =
           exportUri ??
           Uri.parse(
             'https://cursor.com/api/dashboard/export-usage-events-csv',
           ),
       _now = now ?? DateTime.now,
       _timeout = timeout;

  final CursorUsageImportStore _store;
  final CursorUsageAuthResolver _auth;
  final http.Client? _http;
  final Uri _exportUri;
  final DateTime Function() _now;
  final Duration _timeout;

  Future<CursorUsageImportStatus> status() => _store.status();

  Future<List<SessionUsageEvent>> loadEvents() => _store.loadEvents();

  Future<void> clear() => _store.clear();

  Future<CursorUsageImportResult> importCsv(String text) async {
    final parsed = _parse(text);
    final nowMs = _now().millisecondsSinceEpoch;
    return _store.merge(
      events: parsed.events,
      origin: CursorUsageOrigin.manual,
      startMs: parsed.firstMs,
      endMs: parsed.lastMs,
      nowMs: nowMs,
    );
  }

  Future<CursorUsageImportResult> sync() async {
    final auth = await _auth.resolve();
    if (auth == null) {
      throw const CursorUsageSyncException(
        CursorUsageSyncError.login,
        'Cursor is not signed in or the session expired',
      );
    }
    final snapshot = await _store.load();
    final nowMs = _now().millisecondsSinceEpoch;
    final startMs = snapshot.lastSyncAtMs == null
        ? _firstSyncStart(nowMs)
        : _localDayStart(
            snapshot.lastSyncAtMs! - const Duration(days: 1).inMilliseconds,
          );
    final uri = _exportUri.replace(
      queryParameters: {
        'startDate': '$startMs',
        'endDate': '$nowMs',
        'strategy': 'tokens',
      },
    );

    final http.Response response;
    final client = _http ?? http.Client();
    try {
      response = await client
          .get(
            uri,
            headers: {
              'Accept': 'text/csv',
              'Cookie': auth.cookie,
              'Origin': 'https://cursor.com',
              'User-Agent': 'TeamPilot',
            },
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const CursorUsageSyncException(
        CursorUsageSyncError.network,
        'Cursor usage request timed out',
      );
    } on http.ClientException catch (error) {
      throw CursorUsageSyncException(
        CursorUsageSyncError.network,
        'Cursor usage request failed: $error',
      );
    } finally {
      if (_http == null) client.close();
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const CursorUsageSyncException(
        CursorUsageSyncError.login,
        'Cursor rejected the app session',
      );
    }
    if (response.statusCode == 429) {
      throw const CursorUsageSyncException(
        CursorUsageSyncError.rateLimited,
        'Cursor rate-limited the usage export',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CursorUsageSyncException(
        CursorUsageSyncError.http,
        'Cursor returned HTTP ${response.statusCode}',
      );
    }
    if (response.body.trimLeft().startsWith('<')) {
      throw const CursorUsageSyncException(
        CursorUsageSyncError.login,
        'Cursor returned a login page instead of the usage export',
      );
    }

    final parsed = _parse(response.body);
    final inWindow = [
      for (final event in parsed.events)
        if (event.timestampMs >= startMs) event,
    ];
    return _store.merge(
      events: inWindow,
      origin: CursorUsageOrigin.sync,
      startMs: startMs,
      endMs: nowMs,
      nowMs: nowMs,
      account: auth.account,
    );
  }

  CursorUsageCsvResult _parse(String text) {
    try {
      return parseCursorUsageCsv(text);
    } on FormatException catch (error) {
      throw CursorUsageSyncException(
        CursorUsageSyncError.invalidCsv,
        error.message,
      );
    }
  }
}

int _firstSyncStart(int nowMs) {
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs).toLocal();
  final monthStart = DateTime(now.year, now.month).millisecondsSinceEpoch;
  final today = DateTime(now.year, now.month, now.day);
  final thirtyDays = today
      .subtract(const Duration(days: 30))
      .millisecondsSinceEpoch;
  return monthStart < thirtyDays ? monthStart : thirtyDays;
}

int _localDayStart(int ms) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  return DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
}
