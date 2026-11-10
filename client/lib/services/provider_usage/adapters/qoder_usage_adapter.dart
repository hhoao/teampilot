import 'dart:convert';

import '../../../models/managed_provider.dart';
import '../../../models/provider_usage_snapshot.dart';
import '../managed_provider_usage_adapter.dart';
import 'official_subscription_parse.dart';

/// Qoder plan, add-on, and organization credits.
///
/// Qoder PATs cannot authenticate API calls directly. They are exchanged for a
/// short-lived job token, which then authenticates the quota query. The preset
/// URL selects the region, so both requests are derived from that one
/// allowlisted host.
class QoderUsageAdapter implements ManagedProviderUsageAdapter {
  static const adapterId = 'qoder-usage';

  static const _usagePath = '/api/v2/quota/usage';
  static const _exchangePath = '/api/v1/jobToken/exchange';
  static const _allowedHosts = <String>{
    'openapi.qoder.sh',
    'openapi.qoder.com.cn',
  };
  static const _userAgent = 'teampilot-qoder-usage/1.0';
  static const _cosyVersion = '1.0.1';
  static const _cosyClientType = '5';

  @override
  String get id => adapterId;

  @override
  Future<ProviderUsageSnapshot> fetch(
    ManagedProvider provider, {
    required ProviderCredentialResolver credentials,
    required ProviderUsageHttpClient http,
    required DateTime now,
  }) async {
    final pat = await _readPat(provider, credentials);
    final usageUri = _validatedUsageUri(provider.endpointConfig.url);
    final jobToken = await _exchange(pat, usageUri, http);
    final root = await _fetchUsage(jobToken, usageUri, http);
    final measures = _measures(root, provider);
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

  static Future<String> _readPat(
    ManagedProvider provider,
    ProviderCredentialResolver resolver,
  ) async {
    ProviderCredentialScope? scope;
    try {
      scope = await resolver.resolve(provider);
    } on Object {
      scope = null;
    }
    final value = scope?.valueFor('apiKey')?.trim() ?? '';
    if (value.isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    return value;
  }

  static Uri _validatedUsageUri(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        !_allowedHosts.contains(uri.host.toLowerCase()) ||
        uri.path != _usagePath ||
        uri.hasPort && uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
    }
    return uri;
  }

  static Future<String> _exchange(
    String pat,
    Uri usageUri,
    ProviderUsageHttpClient http,
  ) async {
    final response = await _send(
      http,
      ProviderUsageHttpRequest(
        method: 'POST',
        // The usage URI is validated without query or fragment, so replacing
        // the path keeps the region host while dropping the usage path.
        uri: usageUri.replace(path: _exchangePath),
        headers: const {
          'content-type': 'application/json',
          'accept': 'application/json',
          'user-agent': _userAgent,
          'cosy-version': _cosyVersion,
          'cosy-clienttype': _cosyClientType,
        },
        body: jsonEncode({'personal_token': pat}),
      ),
    );
    if (response.statusCode == 400 ||
        response.statusCode == 401 ||
        response.statusCode == 403) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.authenticationFailed,
      );
    }
    throwOfficialHttpStatus(response.statusCode);
    final token = decodeOfficialJsonObject(response.body)['token'];
    if (token is! String || token.trim().isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }
    return token.trim();
  }

  static Future<Map<String, Object?>> _fetchUsage(
    String jobToken,
    Uri usageUri,
    ProviderUsageHttpClient http,
  ) async {
    final response = await _send(
      http,
      ProviderUsageHttpRequest(
        method: 'GET',
        uri: usageUri,
        headers: {
          'authorization': 'Bearer $jobToken',
          'accept': 'application/json',
          'user-agent': _userAgent,
        },
      ),
    );
    throwOfficialHttpStatus(response.statusCode);
    return decodeOfficialJsonObject(response.body);
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

  static List<ProviderUsageMeasure> _measures(
    Map<String, Object?> root,
    ManagedProvider provider,
  ) {
    final resetsAt = parseOfficialResetAt(root['expiresAt']);
    final measures = <ProviderUsageMeasure>[];

    void addBucket(String label, Object? raw, {required String totalKey}) {
      final bucket = _asMap(raw);
      if (bucket == null || !_hasQuotaNumber(bucket, totalKey: totalKey)) {
        return;
      }
      measures.add(
        ProviderUsageMeasure(
          label: label,
          kind: ProviderUsageMeasureKind.quota,
          used: _decimal(bucket['used']),
          total: _decimal(bucket[totalKey]),
          remaining: _decimal(bucket['remaining']),
          unit: _unit(bucket['unit'], provider),
          resetsAt: resetsAt,
        ),
      );
    }

    addBucket('Plan', root['userQuota'], totalKey: 'total');
    addBucket('Add-on', root['addOnQuota'], totalKey: 'total');
    final org = _asMap(root['orgResourcePackage']);
    final orgTotalKey = org != null && _finiteNonNegative(org['cap']) != null
        ? 'cap'
        : 'total';
    addBucket('Org', org, totalKey: orgTotalKey);
    if (measures.isNotEmpty) return measures;

    final percentage = _finiteNonNegative(root['totalUsagePercentage']);
    if (percentage == null) return const [];
    final clamped = percentage.clamp(0, 100).toDouble();
    return [
      ProviderUsageMeasure(
        label: 'Usage',
        kind: ProviderUsageMeasureKind.quota,
        used: _decimal(clamped),
        total: '100',
        remaining: _decimal(100 - clamped),
        unit: '%',
        resetsAt: resetsAt,
      ),
    ];
  }

  static bool _hasQuotaNumber(
    Map<String, Object?> bucket, {
    required String totalKey,
  }) =>
      _finiteNonNegative(bucket['used']) != null ||
      _finiteNonNegative(bucket['remaining']) != null ||
      _finiteNonNegative(bucket[totalKey]) != null;

  static Map<String, Object?>? _asMap(Object? raw) {
    if (raw is! Map) return null;
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  static num? _finiteNonNegative(Object? raw) {
    final value = raw is num
        ? raw
        : raw is String
        ? num.tryParse(raw.trim())
        : null;
    if (value == null || !value.isFinite || value < 0) return null;
    return value;
  }

  static String? _decimal(Object? raw) {
    final value = _finiteNonNegative(raw);
    if (value == null) return null;
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toString();
  }

  static String? _unit(Object? raw, ManagedProvider provider) {
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    final configured = provider.displayConfig.unit?.trim() ?? '';
    return configured.isEmpty ? 'credits' : configured;
  }
}
