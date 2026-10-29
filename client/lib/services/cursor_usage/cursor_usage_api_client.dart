import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/cursor_usage_account.dart';
import '../../models/cursor_usage_range.dart';
import '../../models/cursor_usage_report.dart';

enum CursorUsageApiError { login, rateLimited, network, http, invalidResponse }

class CursorUsageApiException implements Exception {
  const CursorUsageApiException(this.code, this.message);

  final CursorUsageApiError code;
  final String message;

  @override
  String toString() => message;
}

final class CursorUsagePage {
  const CursorUsagePage({required this.events, required this.totalCount});

  final List<CursorUsageEvent> events;
  final int totalCount;
}

/// The transport seam. Fakes in tests implement this, never the concrete
/// client — `CursorUsageApiClient` is `final` on purpose.
abstract interface class CursorUsageApi {
  Future<CursorUsagePage> fetchPage({
    required CursorAccountCredentials credentials,
    required int startMs,
    required int endMs,
    required int page,
    int pageSize,
    int teamId,
  });

  Future<CursorUsageWindow?> fetchBillingCycle({
    required CursorAccountCredentials credentials,
  });
}

final class CursorUsageApiClient implements CursorUsageApi {
  CursorUsageApiClient({
    http.Client? client,
    Uri? eventsUri,
    Uri? summaryUri,
    Duration timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _eventsUri =
           eventsUri ??
           Uri.parse(
             'https://cursor.com/api/dashboard/get-filtered-usage-events',
           ),
       _summaryUri =
           summaryUri ?? Uri.parse('https://cursor.com/api/usage-summary'),
       _timeout = timeout;

  final http.Client _client;
  final bool _ownsClient;
  final Uri _eventsUri;
  final Uri _summaryUri;
  final Duration _timeout;

  Map<String, String> get _baseHeaders => {
    'Accept': '*/*',
    'Content-Type': 'application/json',
    'Origin': 'https://cursor.com',
    'Referer': 'https://cursor.com/dashboard/usage',
    'User-Agent': 'TeamPilot',
  };

  @override
  Future<CursorUsagePage> fetchPage({
    required CursorAccountCredentials credentials,
    required int startMs,
    required int endMs,
    required int page,
    int pageSize = 500,
    int teamId = 0,
  }) async {
    final response = await _post(_eventsUri, credentials, {
      'teamId': teamId,
      'startDate': '$startMs',
      'endDate': '$endMs',
      'page': page,
      'pageSize': pageSize,
    });
    final json = _decodeObject(response);
    final rawEvents = json['usageEventsDisplay'];
    final declaredTotal = (json['totalUsageEventsCount'] as num?)?.toInt();
    // An empty result set may omit the array entirely — that is a real
    // "zero events" page and must be cached as covered. A missing array next
    // to a non-zero (or absent) count is an unparseable envelope; the body
    // snippet goes into the message so the log shows which shape appeared.
    if (rawEvents is! List) {
      if (declaredTotal == 0) {
        return const CursorUsagePage(events: [], totalCount: 0);
      }
      final snippet = response.body.replaceAll(RegExp(r'\s+'), ' ').trim();
      throw CursorUsageApiException(
        CursorUsageApiError.invalidResponse,
        'Cursor returned no usage events array '
        '(total=$declaredTotal): '
        '${snippet.length > 160 ? snippet.substring(0, 160) : snippet}',
      );
    }
    final events = <CursorUsageEvent>[];
    for (final item in rawEvents) {
      if (item is! Map) continue;
      final event = _parseEvent(Map<String, Object?>.from(item));
      if (event != null) events.add(event);
    }
    return CursorUsagePage(
      events: events,
      totalCount:
          (json['totalUsageEventsCount'] as num?)?.toInt() ?? events.length,
    );
  }

  @override
  Future<CursorUsageWindow?> fetchBillingCycle({
    required CursorAccountCredentials credentials,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .get(
            _summaryUri,
            headers: {..._baseHeaders, 'Cookie': credentials.cookie},
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const CursorUsageApiException(
        CursorUsageApiError.network,
        'Cursor usage summary timed out',
      );
    } on http.ClientException catch (error) {
      throw CursorUsageApiException(
        CursorUsageApiError.network,
        'Cursor usage summary failed: $error',
      );
    }
    _throwForStatus(response);
    final json = _decodeObject(response);
    final start = DateTime.tryParse(
      json['billingCycleStart']?.toString() ?? '',
    );
    final end = DateTime.tryParse(json['billingCycleEnd']?.toString() ?? '');
    if (start == null || end == null) return null;
    return CursorUsageWindow(
      startMs: start.millisecondsSinceEpoch,
      endMs: end.millisecondsSinceEpoch,
    );
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<http.Response> _post(
    Uri uri,
    CursorAccountCredentials credentials,
    Map<String, Object?> body,
  ) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {..._baseHeaders, 'Cookie': credentials.cookie},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const CursorUsageApiException(
        CursorUsageApiError.network,
        'Cursor usage request timed out',
      );
    } on http.ClientException catch (error) {
      throw CursorUsageApiException(
        CursorUsageApiError.network,
        'Cursor usage request failed: $error',
      );
    }
    _throwForStatus(response);
    return response;
  }

  void _throwForStatus(http.Response response) {
    final status = response.statusCode;
    if (status == 401 || status == 403) {
      throw const CursorUsageApiException(
        CursorUsageApiError.login,
        'Cursor rejected the session',
      );
    }
    // A dead session arrives as a 3xx redirect to WorkOS sign-in, not a 401.
    if (status >= 300 && status < 400) {
      throw const CursorUsageApiException(
        CursorUsageApiError.login,
        'Cursor redirected the session to sign-in',
      );
    }
    if (status == 429) {
      throw const CursorUsageApiException(
        CursorUsageApiError.rateLimited,
        'Cursor rate-limited the usage request',
      );
    }
    if (status < 200 || status >= 300) {
      throw CursorUsageApiException(
        CursorUsageApiError.http,
        'Cursor returned HTTP $status',
      );
    }
  }

  Map<String, Object?> _decodeObject(http.Response response) {
    final body = response.body.trimLeft();
    if (body.isEmpty) {
      throw const CursorUsageApiException(
        CursorUsageApiError.invalidResponse,
        'Cursor returned an empty body',
      );
    }
    if (body.startsWith('<')) {
      throw const CursorUsageApiException(
        CursorUsageApiError.login,
        'Cursor returned a login page',
      );
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const CursorUsageApiException(
          CursorUsageApiError.invalidResponse,
          'Cursor returned an unexpected payload',
        );
      }
      return Map<String, Object?>.from(decoded);
    } on CursorUsageApiException {
      rethrow;
    } on FormatException {
      throw const CursorUsageApiException(
        CursorUsageApiError.invalidResponse,
        'Cursor returned malformed json',
      );
    }
  }

  CursorUsageEvent? _parseEvent(Map<String, Object?> json) {
    final eventId = json['usageEventId']?.toString() ?? '';
    if (eventId.isEmpty) return null;
    final timestampRaw = json['timestamp']?.toString() ?? '';
    final timestamp = int.tryParse(timestampRaw);
    if (timestamp == null) return null;
    final usage = json['tokenUsage'];
    final tokens = usage is Map ? Map<String, Object?>.from(usage) : const {};
    return CursorUsageEvent(
      eventId: eventId,
      timestampMs: timestamp,
      model: json['model']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      owningUser: json['owningUser']?.toString() ?? '',
      inputTokens: (tokens['inputTokens'] as num?)?.toInt() ?? 0,
      outputTokens: (tokens['outputTokens'] as num?)?.toInt() ?? 0,
      cacheReadTokens: (tokens['cacheReadTokens'] as num?)?.toInt() ?? 0,
      cacheWriteTokens: (tokens['cacheWriteTokens'] as num?)?.toInt() ?? 0,
      totalCents: (tokens['totalCents'] as num?)?.toDouble() ?? 0,
      chargedCents: (json['chargedCents'] as num?)?.toDouble() ?? 0,
    );
  }
}
