import 'dart:convert';

import '../../../models/managed_provider.dart';
import '../../../models/provider_usage_snapshot.dart';
import '../cli_credential_source.dart';
import '../http_json_template.dart';
import '../managed_provider_usage_adapter.dart';
import 'official_subscription_parse.dart';

/// Weekly quota and prepaid balance for The X Subscription.
///
/// grok.com's dashboard API is behind Cloudflare, so Cursor CLI cookies never
/// reach it. The same dashboard lives on cursor.com and accepts the Cursor
/// session cookie. Saved grok.com preset URLs are rewritten onto that host.
class GrokDashboardUsageAdapter implements ManagedProviderUsageAdapter {
  GrokDashboardUsageAdapter({this.cliCredentials});

  static const adapterId = 'grok-dashboard-usage';
  static const _cursorHost = 'cursor.com';
  static const _grokHost = 'grok.com';
  static const _cursorUsagePath = '/api/dashboard/v2/usage-status';
  static const _grokUsagePath = '/dashboard/api/dashboard/v2/usage-status';
  static const _prepaidPath = '/api/dashboard/get-user-prepaid-billing';
  static const _sandPath = '/api/dashboard/get-sand-usage-status';

  final CliCredentialSourceResolver? cliCredentials;

  @override
  String get id => adapterId;

  @override
  Future<ProviderUsageSnapshot> fetch(
    ManagedProvider provider, {
    required ProviderCredentialResolver credentials,
    required ProviderUsageHttpClient http,
    required DateTime now,
  }) async {
    final cookie = await _sessionCookie(provider);
    _validatedUsageUri(provider.endpointConfig);
    final usage = await _fetchUsage(http, cookie);
    final measures = <ProviderUsageMeasure>[
      ?_weeklyMeasure(usage) ?? await _fetchSandWeekly(http, cookie),
      ?await _fetchPrepaid(http, cookie),
    ];
    if (measures.isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }
    return ProviderUsageSnapshot(
      providerId: provider.id,
      status: ProviderUsageStatus.ready,
      measures: measures,
      fetchedAt: now.millisecondsSinceEpoch,
    );
  }

  Future<String> _sessionCookie(ManagedProvider provider) async {
    final resolver = cliCredentials;
    if (resolver == null) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    late final ProviderCredentialScope scope;
    try {
      scope = await resolver.read(provider.endpointConfig.credentialSource);
    } on ManagedProviderUsageQueryError {
      rethrow;
    } on Object {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    final values = fillAccountIdFromJwt(_scopeToValues(scope));
    final accessToken = values['accessToken'] ?? '';
    if (accessToken.isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    final accountId = values['accountId'] ?? '';
    if (accountId.isEmpty) {
      return 'WorkosCursorSessionToken=$accessToken';
    }
    return 'WorkosCursorSessionToken=$accountId%3A%3A$accessToken';
  }

  static Map<String, String> _scopeToValues(ProviderCredentialScope scope) {
    final values = <String, String>{};
    for (final field in scope.fields) {
      final value = scope.valueFor(field);
      if (value != null && value.isNotEmpty) {
        values[field] = value;
      }
    }
    return values;
  }

  static Uri _cursorUri(String path, {Map<String, String>? query}) => Uri(
    scheme: 'https',
    host: _cursorHost,
    path: path,
    queryParameters: query,
  );

  static void _validatedUsageUri(ManagedProviderEndpointConfig endpoint) {
    if (endpoint.hadUnsafeUrl) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
    }
    final uri = Uri.tryParse(endpoint.url.trim());
    final scope = uri?.queryParametersAll['scope'];
    final queryOk =
        uri != null &&
        uri.queryParametersAll.length == 1 &&
        scope?.length == 1 &&
        scope?.single == 'user';
    final host = uri?.host.toLowerCase();
    final pathOk =
        (host == _grokHost && uri?.path == _grokUsagePath) ||
        (host == _cursorHost && uri?.path == _cursorUsagePath);
    if (uri == null ||
        uri.scheme != 'https' ||
        !pathOk ||
        uri.hasPort && uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        !queryOk) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
    }
  }

  Future<Map<String, Object?>> _fetchUsage(
    ProviderUsageHttpClient http,
    String cookie,
  ) async {
    final response = await _send(
      http,
      ProviderUsageHttpRequest(
        method: 'GET',
        uri: _cursorUri(_cursorUsagePath, query: const {'scope': 'user'}),
        headers: _headers(cookie),
      ),
    );
    throwOfficialHttpStatus(response.statusCode);
    return decodeOfficialJsonObject(response.body);
  }

  Future<ProviderUsageMeasure?> _fetchSandWeekly(
    ProviderUsageHttpClient http,
    String cookie,
  ) async {
    try {
      final response = await http.send(
        ProviderUsageHttpRequest(
          method: 'POST',
          uri: _cursorUri(_sandPath),
          headers: _headers(cookie, post: true),
          body: jsonEncode(const <String, Object?>{}),
        ),
      );
      throwOfficialHttpStatus(response.statusCode);
      return _sandWeeklyMeasure(decodeOfficialJsonObject(response.body));
    } on Object {
      return null;
    }
  }

  Future<ProviderUsageMeasure?> _fetchPrepaid(
    ProviderUsageHttpClient http,
    String cookie,
  ) async {
    try {
      final response = await http.send(
        ProviderUsageHttpRequest(
          method: 'POST',
          uri: _cursorUri(_prepaidPath),
          headers: _headers(cookie, post: true),
          body: jsonEncode(const <String, Object?>{}),
        ),
      );
      throwOfficialHttpStatus(response.statusCode);
      return _prepaidMeasure(decodeOfficialJsonObject(response.body));
    } on Object {
      return null;
    }
  }

  static Future<ProviderUsageHttpResponse> _send(
    ProviderUsageHttpClient http,
    ProviderUsageHttpRequest request,
  ) async {
    try {
      return await http.send(request);
    } on ManagedProviderUsageQueryError {
      rethrow;
    } on Object {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.networkFailed,
      );
    }
  }

  static Map<String, String> _headers(String cookie, {bool post = false}) => {
    'Accept': 'application/json',
    'Origin': 'https://cursor.com',
    'Referer': 'https://cursor.com/dashboard',
    'User-Agent': 'TeamPilot',
    'x-cursor-dashboard-surface': 'v2',
    'Cookie': cookie,
    if (post) 'content-type': 'application/json',
  };

  static ProviderUsageMeasure? _weeklyMeasure(Map<String, Object?> json) {
    if (json['availability'] != 'available') return null;
    final weekly = json['weeklyIncludedUsage'];
    if (weekly is! Map) return null;
    final usedCents = _readCents(weekly['usedCents']);
    final budgetCents = _readCents(weekly['budgetCents']);
    if (usedCents == null ||
        usedCents < 0 ||
        budgetCents == null ||
        budgetCents <= 0) {
      return null;
    }
    final percent = (usedCents / budgetCents * 100).clamp(0, 100);
    return ProviderUsageMeasure(
      label: 'Weekly',
      kind: ProviderUsageMeasureKind.quota,
      used: formatOfficialPercent(percent),
      total: '100',
      remaining: formatOfficialPercent((100 - percent).clamp(0, 100)),
      unit: '%',
      resetsAt: parseOfficialResetAt(weekly['resetsAt']),
    );
  }

  static ProviderUsageMeasure? _sandWeeklyMeasure(Map<String, Object?> json) {
    if (json['includedLimitZero'] == true) return null;
    if (json['hasNonZeroIncludedLimit'] == false) return null;
    final percent = _readCents(json['usagePercent']);
    if (percent == null || percent < 0) return null;
    final clamped = percent.clamp(0, 100);
    return ProviderUsageMeasure(
      label: 'Weekly',
      kind: ProviderUsageMeasureKind.quota,
      used: formatOfficialPercent(clamped),
      total: '100',
      remaining: formatOfficialPercent((100 - clamped).clamp(0, 100)),
      unit: '%',
      resetsAt: parseOfficialResetAt(json['nextResetTimestampUtc']),
    );
  }

  static ProviderUsageMeasure? _prepaidMeasure(Map<String, Object?> json) {
    if (json['billingMode'] != 'PREPAID_BILLING_MODE_PREPAID') return null;
    if (json['eligible'] != true) return null;
    final rawCents = json['availableCents'];
    final cents = rawCents == null ? 0 : _readCents(rawCents);
    if (cents == null || cents < 0) return null;
    final remaining = _dollarsFromCents(cents);
    if (remaining == null) return null;
    return ProviderUsageMeasure(
      label: 'Prepaid',
      kind: ProviderUsageMeasureKind.balance,
      remaining: remaining,
      unit: 'USD',
    );
  }

  static num? _readCents(Object? raw) {
    final value = switch (raw) {
      final num number => number,
      final String text => num.tryParse(text.trim()),
      _ => null,
    };
    if (value == null || !value.isFinite) return null;
    return value;
  }

  static String? _dollarsFromCents(num cents) {
    if (!cents.isFinite || cents < 0) return null;
    final whole = cents is int ? cents : cents.round();
    if (whole < 0) return null;
    final dollars = whole ~/ 100;
    final remainder = whole % 100;
    if (remainder == 0) return '$dollars';
    return '$dollars.${remainder.toString().padLeft(2, '0')}';
  }
}
