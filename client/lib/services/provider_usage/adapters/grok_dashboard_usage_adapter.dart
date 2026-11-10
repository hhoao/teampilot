import 'dart:convert';

import '../../../models/managed_provider.dart';
import '../../../models/provider_usage_snapshot.dart';
import '../cli_credential_source.dart';
import '../http_json_template.dart';
import '../managed_provider_usage_adapter.dart';
import 'official_subscription_parse.dart';

/// Weekly quota and prepaid balance from the Grok dashboard.
///
/// The session cookie comes from the entry's Cursor CLI credential. The usage
/// URL is allowlisted; prepaid failures leave the weekly measure in place.
class GrokDashboardUsageAdapter implements ManagedProviderUsageAdapter {
  GrokDashboardUsageAdapter({this.cliCredentials});

  static const adapterId = 'grok-dashboard-usage';
  static const _host = 'grok.com';
  static const _usagePath = '/dashboard/api/dashboard/v2/usage-status';
  static const _prepaidPath =
      '/dashboard/api/dashboard/get-user-prepaid-billing';

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
    final usageUri = _validatedUsageUri(provider.endpointConfig);
    final usage = await _fetchUsage(http, usageUri, cookie);
    final measures = <ProviderUsageMeasure>[
      ?_weeklyMeasure(usage),
      ?await _fetchPrepaid(http, usageUri, cookie),
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
    return expandHttpJsonTemplate(
      'WorkosCursorSessionToken={accountId}::{accessToken}',
      values,
    );
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

  static Uri _validatedUsageUri(ManagedProviderEndpointConfig endpoint) {
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
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != _host ||
        uri.path != _usagePath ||
        uri.hasPort && uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        !queryOk) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
    }
    return uri;
  }

  Future<Map<String, Object?>> _fetchUsage(
    ProviderUsageHttpClient http,
    Uri usageUri,
    String cookie,
  ) async {
    final response = await _send(
      http,
      ProviderUsageHttpRequest(
        method: 'GET',
        uri: usageUri,
        headers: _headers(cookie),
      ),
    );
    throwOfficialHttpStatus(response.statusCode);
    return decodeOfficialJsonObject(response.body);
  }

  Future<ProviderUsageMeasure?> _fetchPrepaid(
    ProviderUsageHttpClient http,
    Uri usageUri,
    String cookie,
  ) async {
    try {
      final response = await http.send(
        ProviderUsageHttpRequest(
          method: 'POST',
          uri: Uri(
            scheme: usageUri.scheme,
            host: usageUri.host,
            path: _prepaidPath,
          ),
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
    'Origin': 'https://grok.com',
    'Referer': 'https://grok.com/dashboard',
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
