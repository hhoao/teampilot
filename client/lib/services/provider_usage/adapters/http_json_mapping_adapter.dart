import 'dart:convert';
import 'dart:io';

import '../../../models/managed_provider.dart';
import '../../../models/provider_usage_snapshot.dart';
import '../cli_credential_source.dart';
import '../http_json_template.dart';
import '../managed_provider_usage_adapter.dart';
import 'official_subscription_parse.dart';

enum HttpJsonCredentialPlacement { header, query, jsonBody, unsupported }

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
    this.credentialSource = 'secret',
    this.credentialTemplate,
    this.credentialName,
    this.credentialPlacement = 'header',
    this.headers = const {},
    this.body = const {},
    this.windows = const [],
    this.staleAfter = const Duration(minutes: 10),
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
  final String credentialSource;
  final String? credentialTemplate;
  final String? credentialName;
  final String credentialPlacement;
  final Map<String, String> headers;
  final Map<String, Object?> body;
  final List<ManagedProviderUsageWindow> windows;
  final Duration? staleAfter;
  final String? adapterVersion;

  factory HttpJsonMappingConfig.fromProvider(ManagedProvider provider) {
    final endpoint = provider.endpointConfig;
    final mappings = endpoint.fieldMappings;
    String? mapping(String key) =>
        mappings[key] is String ? mappings[key] as String : null;
    return HttpJsonMappingConfig(
      method: endpoint.method,
      url: endpoint.hadUnsafeUrl ? '' : endpoint.url,
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
      credential: endpoint.credentialField == null
          ? null
          : HttpJsonCredentialConfig(
              field: endpoint.credentialField!,
              name: endpoint.credentialName,
              placement: _credentialPlacement(endpoint.credentialPlacement),
              prefix: endpoint.credentialPrefix,
            ),
      credentialSource: endpoint.credentialSource,
      credentialTemplate: endpoint.credentialTemplate,
      credentialName: endpoint.credentialName,
      credentialPlacement: endpoint.credentialPlacement,
      headers: endpoint.headers,
      body: endpoint.body,
      windows: endpoint.windows,
    );
  }

  static HttpJsonCredentialPlacement _credentialPlacement(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'header' => HttpJsonCredentialPlacement.header,
        'query' => HttpJsonCredentialPlacement.query,
        'jsonbody' || 'body' => HttpJsonCredentialPlacement.jsonBody,
        _ => HttpJsonCredentialPlacement.unsupported,
      };
}

class HttpJsonMappingAdapter implements ManagedProviderUsageAdapter {
  HttpJsonMappingAdapter({this.config, this.cliCredentials});

  final HttpJsonMappingConfig? config;
  final CliCredentialSourceResolver? cliCredentials;

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
    _validatePaths(mapping);
    final uri = _validatedUri(mapping.url);
    late final ProviderUsageHttpRequest request;
    try {
      request = await _buildRequest(mapping, provider, credentials, uri);
    } on ManagedProviderUsageQueryError {
      rethrow;
    } on Object {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
    }

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
    final responseRoot = mapping.responsePath == null
        ? _PathLookup.presentValue(decoded)
        : _lookupPath(decoded, mapping.responsePath);
    if (!responseRoot.present || responseRoot.value == null) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }
    final measures = <ProviderUsageMeasure>[];
    try {
      if (mapping.windows.isNotEmpty) {
        for (final window in mapping.windows) {
          final measure = _measureFromWindow(
            responseRoot.value,
            window,
            provider,
          );
          if (measure != null) {
            measures.add(measure);
          }
        }
      } else {
        final measuresRoot = mapping.measuresPath == null
            ? _PathLookup.presentValue(responseRoot.value)
            : _lookupPath(responseRoot.value, mapping.measuresPath);
        final items = mapping.measuresPath == null
            ? [responseRoot.value]
            : measuresRoot.present && measuresRoot.value is List
            ? measuresRoot.value as List<Object?>
            : !measuresRoot.present || measuresRoot.value == null
            ? const []
            : [measuresRoot.value];
        if (items.isEmpty) {
          throw const ManagedProviderUsageQueryError(
            ManagedProviderUsageQueryErrorCode.responseParseFailed,
          );
        }
        for (final item in items) {
          measures.add(_measure(item, mapping, provider));
        }
      }
    } on FormatException {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    } on TypeError {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    } on Object {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }
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
    final method = mapping.method.trim().toUpperCase();
    if (method != 'GET' && method != 'POST') {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
    }
    if (mapping.credential?.placement ==
        HttpJsonCredentialPlacement.unsupported) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
    }

    for (final entry in mapping.headers.entries) {
      _validateRequestText(entry.key);
      _validateRequestText(entry.value);
    }
    final headers = <String, String>{};
    final body = Map<String, Object?>.from(mapping.body);
    var requestUri = uri;
    final credential = mapping.credential;
    final needsCredentialScope =
        credential != null ||
        mapping.credentialSource.startsWith('cli:') ||
        (mapping.credentialTemplate != null &&
            mapping.credentialTemplate!.trim().isNotEmpty) ||
        mapping.headers.values.any((value) => value.contains('{'));
    if (needsCredentialScope) {
      try {
        final scope = await _resolveCredentialScope(
          mapping,
          provider,
          credentials,
        );
        final values = fillAccountIdFromJwt(_scopeToValues(scope));
        for (final entry in mapping.headers.entries) {
          final expanded = expandHttpJsonTemplate(entry.value, values);
          if (expanded.isNotEmpty) {
            headers[entry.key] = expanded;
          }
        }
        if (credential != null) {
          _validateRequestText(credential.field);
          _validateRequestText(credential.targetName);
          if (credential.prefix != null) {
            _validateRequestText(credential.prefix!);
          }
          if (credential.targetName.isEmpty) {
            throw const ManagedProviderUsageQueryError(
              ManagedProviderUsageQueryErrorCode.missingCredential,
            );
          }
          final supplied = _credentialValue(mapping, credential, values);
          _validateRequestText(supplied);
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
            case HttpJsonCredentialPlacement.unsupported:
              throw const ManagedProviderUsageQueryError(
                ManagedProviderUsageQueryErrorCode.unsupported,
              );
          }
        } else {
          final template = mapping.credentialTemplate?.trim();
          final name = mapping.credentialName?.trim();
          if (template != null &&
              template.isNotEmpty &&
              name != null &&
              name.isNotEmpty) {
            final supplied = expandHttpJsonTemplate(template, values);
            if (supplied.isEmpty) {
              throw const ManagedProviderUsageQueryError(
                ManagedProviderUsageQueryErrorCode.missingCredential,
              );
            }
            _validateRequestText(name);
            _validateRequestText(supplied);
            switch (HttpJsonMappingConfig._credentialPlacement(
              mapping.credentialPlacement,
            )) {
              case HttpJsonCredentialPlacement.header:
                headers[name] = supplied;
              case HttpJsonCredentialPlacement.query:
                requestUri = requestUri.replace(
                  queryParameters: {
                    ...requestUri.queryParameters,
                    name: supplied,
                  },
                );
              case HttpJsonCredentialPlacement.jsonBody:
                body[name] = supplied;
              case HttpJsonCredentialPlacement.unsupported:
                throw const ManagedProviderUsageQueryError(
                  ManagedProviderUsageQueryErrorCode.unsupported,
                );
            }
          }
        }
      } on ManagedProviderUsageQueryError {
        rethrow;
      } on Object {
        throw const ManagedProviderUsageQueryError(
          ManagedProviderUsageQueryErrorCode.missingCredential,
        );
      }
    } else {
      headers.addAll(mapping.headers);
    }

    final hasBody = method == 'POST' || body.isNotEmpty;
    if (hasBody) headers.putIfAbsent('content-type', () => 'application/json');
    try {
      return ProviderUsageHttpRequest(
        method: method,
        uri: requestUri,
        headers: headers,
        body: hasBody ? jsonEncode(body) : null,
      );
    } on Object {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
    }
  }

  Future<ProviderCredentialScope> _resolveCredentialScope(
    HttpJsonMappingConfig mapping,
    ManagedProvider provider,
    ProviderCredentialResolver credentials,
  ) async {
    if (mapping.credentialSource.startsWith('cli:')) {
      final resolver = cliCredentials;
      if (resolver == null) {
        throw const ManagedProviderUsageQueryError(
          ManagedProviderUsageQueryErrorCode.missingCredential,
        );
      }
      return resolver.read(mapping.credentialSource);
    }
    return _resolveCredentials(credentials, provider);
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

  static String _credentialValue(
    HttpJsonMappingConfig mapping,
    HttpJsonCredentialConfig credential,
    Map<String, String> values,
  ) {
    final template = mapping.credentialTemplate?.trim();
    if (template != null && template.isNotEmpty) {
      final expanded = expandHttpJsonTemplate(template, values);
      if (expanded.isEmpty) {
        throw const ManagedProviderUsageQueryError(
          ManagedProviderUsageQueryErrorCode.missingCredential,
        );
      }
      return expanded;
    }
    final value = values[credential.field];
    if (value == null || value.isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    return '${credential.prefix ?? ''}$value';
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

  ProviderUsageMeasure? _measureFromWindow(
    Object? root,
    ManagedProviderUsageWindow window,
    ManagedProvider provider,
  ) {
    final used = _windowNumericValue(_lookupPath(root, window.used));
    final total = _windowNumericValue(_lookupPath(root, window.total));
    final remaining = _windowNumericValue(_lookupPath(root, window.remaining));
    if (used == null && total == null && remaining == null) {
      return null;
    }

    var resolvedUsed = used;
    var resolvedTotal = total;
    var resolvedRemaining = remaining;
    if (window.unit == '%' &&
        resolvedUsed != null &&
        resolvedTotal == null &&
        resolvedRemaining == null) {
      final percent =
          readOfficialPercent(_lookupPath(root, window.used).value) ?? 0;
      final clamped = percent.clamp(0, 100);
      resolvedUsed = formatOfficialPercent(clamped);
      resolvedTotal = '100';
      resolvedRemaining = formatOfficialPercent(
        (100 - clamped).clamp(0, 100),
      );
    }

    final kind = window.kind == null || window.kind!.trim().isEmpty
        ? ProviderUsageMeasureKind.quota
        : ProviderUsageMeasureKind.fromJson(window.kind);
    final resetsAt = window.resetsAt == null
        ? null
        : parseOfficialResetAt(_lookupPath(root, window.resetsAt).value);

    return ProviderUsageMeasure(
      label: window.label.isEmpty ? provider.name : window.label,
      kind: kind,
      total: resolvedTotal,
      used: resolvedUsed,
      remaining: resolvedRemaining,
      unit: window.unit,
      resetsAt: resetsAt,
    );
  }

  ProviderUsageMeasure _measure(
    Object? item,
    HttpJsonMappingConfig mapping,
    ManagedProvider provider,
  ) {
    final labelLookup = _lookupPath(item, mapping.labelPath);
    final label = labelLookup.present && labelLookup.value != null
        ? _requiredString(labelLookup.value)
        : mapping.defaultLabel ?? provider.name;
    final kindLookup = _lookupPath(item, mapping.kindPath);
    if (kindLookup.present &&
        kindLookup.value != null &&
        kindLookup.value is! String) {
      throw const FormatException('invalid usage kind');
    }
    final resolvedKind = kindLookup.present && kindLookup.value != null
        ? ProviderUsageMeasureKind.fromJson(kindLookup.value)
        : mapping.defaultKind;
    final total = _decimalValue(_lookupPath(item, mapping.totalPath));
    final used = _decimalValue(_lookupPath(item, mapping.usedPath));
    final remaining = _decimalValue(_lookupPath(item, mapping.remainingPath));
    final unitLookup = _lookupPath(item, mapping.unitPath);
    final unit = unitLookup.present && unitLookup.value != null
        ? _requiredString(unitLookup.value)
        : mapping.defaultUnit;
    final currencyLookup = _lookupPath(item, mapping.currencyPath);
    final currency = currencyLookup.present && currencyLookup.value != null
        ? _requiredString(currencyLookup.value)
        : mapping.defaultCurrency;
    final resetsAt = _timestampValue(_lookupPath(item, mapping.resetsAtPath));
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
    final parsedAddress = host == null ? null : InternetAddress.tryParse(host);
    final loopback =
        host == 'localhost' ||
        host == 'localhost.' ||
        parsedAddress?.isLoopback == true;
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.host.isEmpty ||
        uri.queryParameters.keys.any(_hasControlCharacters) ||
        uri.queryParameters.values.any(_hasControlCharacters) ||
        uri.queryParameters.keys.any(_isCredentialQueryName) ||
        uri.queryParameters.values.any(_isCredentialQueryValue) ||
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

  static void _validatePaths(HttpJsonMappingConfig config) {
    for (final path in [
      config.responsePath,
      config.measuresPath,
      config.labelPath,
      config.kindPath,
      config.totalPath,
      config.usedPath,
      config.remainingPath,
      config.unitPath,
      config.currencyPath,
      config.resetsAtPath,
    ]) {
      _parsePath(path);
    }
    for (final window in config.windows) {
      for (final path in [
        window.used,
        window.total,
        window.remaining,
        window.resetsAt,
      ]) {
        _parsePath(path);
      }
    }
  }

  static List<_PathToken> _parsePath(String? path) {
    if (path == null) return const [];
    final trimmed = path.trim();
    if (trimmed.isEmpty || trimmed != path) _throwUnsupported();
    if (trimmed == r'$') return const [];
    var remaining = trimmed;
    if (remaining.startsWith(r'$')) {
      remaining = remaining.substring(1);
      if (remaining.startsWith('.')) {
        remaining = remaining.substring(1);
      } else if (!remaining.startsWith('[')) {
        _throwUnsupported();
      }
    }
    if (remaining.isEmpty) _throwUnsupported();
    final tokens = <_PathToken>[];
    for (final segment in remaining.split('.')) {
      if (segment.isEmpty) _throwUnsupported();
      var cursor = 0;
      final bracket = segment.indexOf('[');
      final key = bracket < 0 ? segment : segment.substring(0, bracket);
      if (key.isNotEmpty && !RegExp(r'^[^\s.\[\]]+$').hasMatch(key)) {
        _throwUnsupported();
      }
      if (key.isNotEmpty) tokens.add(_PathToken.key(key));
      if (bracket >= 0) {
        cursor = bracket;
        while (cursor < segment.length) {
          if (segment[cursor] != '[') _throwUnsupported();
          final close = segment.indexOf(']', cursor + 1);
          if (close < 0 || close == cursor + 1) _throwUnsupported();
          final index = int.tryParse(segment.substring(cursor + 1, close));
          if (index == null || index < 0) _throwUnsupported();
          tokens.add(_PathToken.index(index));
          cursor = close + 1;
        }
      }
    }
    return tokens;
  }

  static _PathLookup _lookupPath(Object? root, String? path) {
    if (path == null) return const _PathLookup.absent();
    final tokens = _parsePath(path);
    Object? current = root;
    for (final token in tokens) {
      if (token.key != null) {
        if (current is! Map || !current.containsKey(token.key)) {
          return const _PathLookup.absent();
        }
        current = current[token.key];
      } else {
        final index = token.index!;
        if (current is! List || index >= current.length) {
          return const _PathLookup.absent();
        }
        current = current[index];
      }
    }
    return _PathLookup.presentValue(current);
  }

  static String _requiredString(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const FormatException('invalid mapped string');
    }
    return value;
  }

  static String? _decimalValue(_PathLookup lookup) {
    if (!lookup.present || lookup.value == null) return null;
    final value = lookup.value;
    // jsonDecode may materialize JSON decimals as double, losing their
    // original lexeme and precision. Require mapped amounts to be strings.
    if (value is! String || value.isEmpty) {
      throw const FormatException('invalid decimal value');
    }
    if (!RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(value)) {
      throw const FormatException('invalid decimal value');
    }
    return value;
  }

  static String? _windowNumericValue(_PathLookup lookup) {
    if (!lookup.present || lookup.value == null) return null;
    final value = lookup.value;
    if (value is num && value.isFinite) {
      return formatOfficialPercent(value);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      if (RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(trimmed)) {
        return trimmed;
      }
      return null;
    }
    return null;
  }

  static int? _timestampValue(_PathLookup lookup) {
    if (!lookup.present || lookup.value == null) return null;
    final value = lookup.value;
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    if (value is String) {
      final integral = int.tryParse(value);
      if (integral != null) return integral;
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    throw const FormatException('invalid reset timestamp');
  }

  static void _validateRequestText(String value) {
    if (_hasControlCharacters(value)) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
    }
  }

  static bool _hasControlCharacters(String value) =>
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);

  static bool _isCredentialQueryName(String name) {
    return isManagedProviderCredentialKey(name);
  }

  static bool _isCredentialQueryValue(String value) {
    final normalized = value
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toLowerCase();
    return RegExp(
          r'''bearer\s+\S+|basic\s+\S+|(?:api[_-]?key|token|secret|password|authorization)\s*[:=]\s*\S+''',
          caseSensitive: false,
        ).hasMatch(value) ||
        normalized.contains('apikey') ||
        normalized.contains('accesstoken') ||
        normalized.contains('clientsecret') ||
        normalized.contains('privatekey') ||
        normalized.contains('password') ||
        normalized.contains('secret') ||
        normalized.contains('credential');
  }

  static Never _throwUnsupported() =>
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
}

class _PathToken {
  const _PathToken.key(this.key) : index = null;
  const _PathToken.index(this.index) : key = null;

  final String? key;
  final int? index;
}

class _PathLookup {
  const _PathLookup.absent() : present = false, value = null;
  const _PathLookup.presentValue(this.value) : present = true;

  final bool present;
  final Object? value;
}
