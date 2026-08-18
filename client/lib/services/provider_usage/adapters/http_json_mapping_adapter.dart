import 'dart:convert';

import '../../../models/managed_provider.dart';
import '../../../models/provider_usage_snapshot.dart';
import '../managed_provider_usage_adapter.dart';

enum HttpJsonCredentialPlacement { header, query, jsonBody }

class HttpJsonCredentialConfig {
  const HttpJsonCredentialConfig({
    required this.field,
    this.name,
    this.placement = HttpJsonCredentialPlacement.header,
    this.prefix,
  });

  final String field;
  final String? name;
  final HttpJsonCredentialPlacement placement;
  final String? prefix;

  String get targetName => (name ?? field).trim();
}

/// Declarative request and response mapping. Paths are data paths only; no
/// expressions, scripts, or callbacks are evaluated.
class HttpJsonMappingConfig {
  const HttpJsonMappingConfig({
    this.method = 'GET',
    this.url = '',
    this.responsePath,
    this.measuresPath,
    this.labelPath,
    this.kindPath,
    this.totalPath,
    this.usedPath,
    this.remainingPath,
    this.unitPath,
    this.currencyPath,
    this.resetsAtPath,
    this.defaultLabel,
    this.defaultKind = ProviderUsageMeasureKind.balance,
    this.defaultUnit,
    this.defaultCurrency,
    this.credential,
    this.headers = const {},
    this.body = const {},
    this.staleAfter,
    this.adapterVersion,
  });

  final String method;
  final String url;
  final String? responsePath;
  final String? measuresPath;
  final String? labelPath;
  final String? kindPath;
  final String? totalPath;
  final String? usedPath;
  final String? remainingPath;
  final String? unitPath;
  final String? currencyPath;
  final String? resetsAtPath;
  final String? defaultLabel;
  final ProviderUsageMeasureKind defaultKind;
  final String? defaultUnit;
  final String? defaultCurrency;
  final HttpJsonCredentialConfig? credential;
  final Map<String, String> headers;
  final Map<String, Object?> body;
  final Duration? staleAfter;
  final String? adapterVersion;

  factory HttpJsonMappingConfig.fromProvider(ManagedProvider provider) {
    final endpoint = provider.endpointConfig;
    final mappings = endpoint.fieldMappings;
    String? mapping(String key) =>
        mappings[key] is String ? mappings[key] as String : null;
    return HttpJsonMappingConfig(
      method: endpoint.method,
      url: endpoint.url,
      responsePath: endpoint.responsePath,
      measuresPath: endpoint.measuresPath,
      labelPath: mapping('label'),
      kindPath: mapping('kind'),
      totalPath: mapping('total'),
      usedPath: mapping('used'),
      remainingPath: mapping('remaining'),
      unitPath: mapping('unit'),
      currencyPath: mapping('currency'),
      resetsAtPath: mapping('resetsAt'),
      defaultUnit: provider.displayConfig.unit,
      defaultCurrency: provider.displayConfig.currency,
    );
  }
}

class HttpJsonMappingAdapter implements ManagedProviderUsageAdapter {
  HttpJsonMappingAdapter({this.config});

  final HttpJsonMappingConfig? config;

  @override
  String get id => 'http-json';

  @override
  Future<ProviderUsageSnapshot> fetch(
    ManagedProvider provider, {
    required ProviderCredentialResolver credentials,
    required ProviderUsageHttpClient http,
    required DateTime now,
  }) async {
    final mapping = config ?? HttpJsonMappingConfig.fromProvider(provider);
    final uri = _validatedUri(mapping.url);
    final request = await _buildRequest(mapping, provider, credentials, uri);

    late final ProviderUsageHttpResponse response;
    try {
      response = await http.send(request);
    } on ManagedProviderUsageQueryError {
      rethrow;
    } on Object {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.networkFailed,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = response.statusCode == 401 || response.statusCode == 403
          ? ManagedProviderUsageQueryErrorCode.authenticationFailed
          : ManagedProviderUsageQueryErrorCode.httpFailed;
      throw ManagedProviderUsageQueryError(code);
    }

    final decoded = _decode(response.body);
    final responseRoot = _readPath(decoded, mapping.responsePath);
    if (responseRoot == null) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }
    final measuresRoot = _readPath(responseRoot, mapping.measuresPath);
    final items = mapping.measuresPath == null
        ? [responseRoot]
        : measuresRoot is List
        ? measuresRoot
        : measuresRoot == null
        ? const []
        : [measuresRoot];
    if (items.isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }

    final measures = <ProviderUsageMeasure>[];
    try {
      for (final item in items) {
        measures.add(_measure(item, mapping, provider));
      }
    } on FormatException {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    } on TypeError {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }

    return ProviderUsageSnapshot(
      providerId: provider.id,
      status: ProviderUsageStatus.ready,
      measures: measures,
      fetchedAt: now.millisecondsSinceEpoch,
      staleAt: mapping.staleAfter == null
          ? null
          : now.add(mapping.staleAfter!).millisecondsSinceEpoch,
      adapterVersion: mapping.adapterVersion,
    );
  }

  Future<ProviderUsageHttpRequest> _buildRequest(
    HttpJsonMappingConfig mapping,
    ManagedProvider provider,
    ProviderCredentialResolver credentials,
    Uri uri,
  ) async {
    final headers = <String, String>{...mapping.headers};
    final body = Map<String, Object?>.from(mapping.body);
    var requestUri = uri;
    final credential = mapping.credential;
    if (credential != null) {
      final scope = await _resolveCredentials(credentials, provider);
      final value = scope.valueFor(credential.field);
      if (value == null || value.isEmpty || credential.targetName.isEmpty) {
        throw const ManagedProviderUsageQueryError(
          ManagedProviderUsageQueryErrorCode.missingCredential,
        );
      }
      final supplied = '${credential.prefix ?? ''}$value';
      switch (credential.placement) {
        case HttpJsonCredentialPlacement.header:
          headers[credential.targetName] = supplied;
        case HttpJsonCredentialPlacement.query:
          requestUri = requestUri.replace(
            queryParameters: {
              ...requestUri.queryParameters,
              credential.targetName: supplied,
            },
          );
        case HttpJsonCredentialPlacement.jsonBody:
          body[credential.targetName] = supplied;
      }
    }

    final method = mapping.method.trim().toUpperCase();
    if (method != 'GET' && method != 'POST') {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
    }
    final hasBody = method == 'POST' || body.isNotEmpty;
    if (hasBody) headers.putIfAbsent('content-type', () => 'application/json');
    return ProviderUsageHttpRequest(
      method: method,
      uri: requestUri,
      headers: headers,
      body: hasBody ? jsonEncode(body) : null,
    );
  }

  Future<ProviderCredentialScope> _resolveCredentials(
    ProviderCredentialResolver resolver,
    ManagedProvider provider,
  ) async {
    try {
      final scope = await resolver.resolve(provider);
      if (scope == null || scope.isEmpty) {
        throw const ManagedProviderUsageQueryError(
          ManagedProviderUsageQueryErrorCode.missingCredential,
        );
      }
      return scope;
    } on ManagedProviderUsageQueryError {
      rethrow;
    } on Object {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
  }

  ProviderUsageMeasure _measure(
    Object? item,
    HttpJsonMappingConfig mapping,
    ManagedProvider provider,
  ) {
    final label =
        _stringValue(_readPath(item, mapping.labelPath)) ??
        mapping.defaultLabel ??
        provider.name;
    final kind = ProviderUsageMeasureKind.fromJson(
      _readPath(item, mapping.kindPath),
    );
    final resolvedKind = mapping.kindPath == null ? mapping.defaultKind : kind;
    final total = _decimalValue(_readPath(item, mapping.totalPath));
    final used = _decimalValue(_readPath(item, mapping.usedPath));
    final remaining = _decimalValue(_readPath(item, mapping.remainingPath));
    final unit =
        _stringValue(_readPath(item, mapping.unitPath)) ?? mapping.defaultUnit;
    final currency =
        _stringValue(_readPath(item, mapping.currencyPath)) ??
        mapping.defaultCurrency;
    final resetsAt = _timestampValue(_readPath(item, mapping.resetsAtPath));
    if (total == null && used == null && remaining == null) {
      throw const FormatException('usage measure has no numeric fields');
    }
    return ProviderUsageMeasure(
      label: label,
      kind: resolvedKind,
      total: total,
      used: used,
      remaining: remaining,
      unit: unit,
      currency: currency,
      resetsAt: resetsAt,
    );
  }

  static Uri _validatedUri(String raw) {
    final uri = Uri.tryParse(raw.trim());
    final host = uri?.host.toLowerCase();
    final loopback =
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '[::1]';
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.host.isEmpty ||
        uri.scheme != 'https' && !(uri.scheme == 'http' && loopback)) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
    }
    return uri;
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on Object {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }
  }

  static Object? _readPath(Object? root, String? path) {
    if (path == null || path.trim().isEmpty || path.trim() == r'$') {
      return root;
    }
    var remaining = path.trim();
    if (remaining.startsWith(r'$')) remaining = remaining.substring(1);
    if (remaining.startsWith('.')) remaining = remaining.substring(1);
    Object? current = root;
    for (final segment in remaining.split('.')) {
      if (segment.isEmpty) return null;
      var key = segment;
      final indexes = <int>[];
      final bracketStart = segment.indexOf('[');
      if (bracketStart >= 0) {
        key = segment.substring(0, bracketStart);
        var cursor = bracketStart;
        while (cursor < segment.length) {
          final open = segment.indexOf('[', cursor);
          final close = segment.indexOf(']', open + 1);
          if (open < 0 || close < 0) return null;
          final index = int.tryParse(segment.substring(open + 1, close));
          if (index == null || index < 0) return null;
          indexes.add(index);
          cursor = close + 1;
        }
      }
      if (key.isNotEmpty) {
        if (current is! Map || !current.containsKey(key)) return null;
        current = current[key];
      }
      for (final index in indexes) {
        if (current is! List || index >= current.length) return null;
        current = current[index];
      }
    }
    return current;
  }

  static String? _stringValue(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is num && value.isFinite) return value.toString();
    return null;
  }

  static String? _decimalValue(Object? value) {
    final result = _stringValue(value);
    if (result == null || result.isEmpty) return null;
    if (!RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(result)) {
      throw const FormatException('invalid decimal value');
    }
    return result;
  }

  static int? _timestampValue(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    if (value is String) {
      final integral = int.tryParse(value);
      if (integral != null) return integral;
      return DateTime.tryParse(value)?.millisecondsSinceEpoch;
    }
    return null;
  }
}
