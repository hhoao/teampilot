import 'package:flutter/foundation.dart';
import 'package:equatable/equatable.dart';

enum ManagedProviderKind {
  apiBalance('apiBalance'),
  subscriptionQuota('subscriptionQuota'),
  customHttp('customHttp'),
  unknown('unknown');

  const ManagedProviderKind(this.value);
  final String value;

  static ManagedProviderKind fromJson(Object? raw) {
    for (final kind in values) {
      if (kind.value == raw?.toString().trim()) return kind;
    }
    return ManagedProviderKind.unknown;
  }
}

@immutable
class ManagedProviderBrand extends Equatable {
  factory ManagedProviderBrand({
    String name = '',
    String? iconUrl,
    String? iconColor,
    Map<String, Object?> unknownFields = const {},
  }) => ManagedProviderBrand._(
    name: _sanitizeRequiredText(name),
    iconUrl: _sanitizeOptionalUrl(iconUrl),
    iconColor: _sanitizeOptionalText(iconColor),
    unknownFields: _freezeFields(unknownFields, rejectCli: true),
  );

  const ManagedProviderBrand._({
    required this.name,
    this.iconUrl,
    this.iconColor,
    this.unknownFields = const {},
  });

  factory ManagedProviderBrand.fromJson(Map<String, Object?> json) =>
      ManagedProviderBrand(
        name: json['name'] as String? ?? '',
        iconUrl: json['iconUrl'] as String?,
        iconColor: json['iconColor'] as String?,
        unknownFields: _unknownFields(json, const {
          'name',
          'iconUrl',
          'iconColor',
        }, rejectCli: true),
      );

  final String name;
  final String? iconUrl;
  final String? iconColor;
  final Map<String, Object?> unknownFields;

  Map<String, Object?> toJson() => {
    ..._thawFields(unknownFields, rejectCli: true),
    'name': name,
    if (iconUrl != null) 'iconUrl': iconUrl,
    if (iconColor != null) 'iconColor': iconColor,
  };

  @override
  List<Object?> get props => [name, iconUrl, iconColor, unknownFields];
}

@immutable
class ManagedProviderEndpointConfig extends Equatable {
  factory ManagedProviderEndpointConfig({
    String url = '',
    String method = 'GET',
    String? responsePath,
    String? measuresPath,
    Map<String, Object?> fieldMappings = const {},
    Map<String, Object?> unknownFields = const {},
  }) => ManagedProviderEndpointConfig._(
    url: _sanitizeUrl(url),
    method: method,
    responsePath: responsePath,
    measuresPath: measuresPath,
    fieldMappings: _freezeMappingFields(fieldMappings),
    unknownFields: _freezeFields(unknownFields, rejectCli: true),
  );

  const ManagedProviderEndpointConfig._({
    required this.url,
    required this.method,
    this.responsePath,
    this.measuresPath,
    this.fieldMappings = const {},
    this.unknownFields = const {},
  });

  factory ManagedProviderEndpointConfig.fromJson(Map<String, Object?> json) {
    final mappings = json['fieldMappings'];
    return ManagedProviderEndpointConfig(
      url: json['url'] as String? ?? '',
      method: json['method'] as String? ?? 'GET',
      responsePath: json['responsePath'] as String?,
      measuresPath: json['measuresPath'] as String?,
      fieldMappings: mappings is Map
          ? Map<String, Object?>.from(mappings)
          : const {},
      unknownFields: _unknownFields(json, const {
        'url',
        'method',
        'responsePath',
        'measuresPath',
        'fieldMappings',
      }, rejectCli: true),
    );
  }

  final String url;
  final String method;
  final String? responsePath;
  final String? measuresPath;
  final Map<String, Object?> fieldMappings;
  final Map<String, Object?> unknownFields;

  Map<String, Object?> toJson() => {
    ..._thawFields(unknownFields, rejectCli: true),
    'url': url,
    'method': method,
    if (responsePath != null) 'responsePath': responsePath,
    if (measuresPath != null) 'measuresPath': measuresPath,
    if (fieldMappings.isNotEmpty)
      'fieldMappings': _thawMappingFields(fieldMappings),
  };

  @override
  List<Object?> get props => [
    url,
    method,
    responsePath,
    measuresPath,
    fieldMappings,
    unknownFields,
  ];
}

@immutable
class ManagedProviderDisplayConfig extends Equatable {
  factory ManagedProviderDisplayConfig({
    String? currency,
    String? unit,
    int? decimalPlaces,
    bool showPercent = false,
    Map<String, Object?> unknownFields = const {},
  }) => ManagedProviderDisplayConfig._(
    currency: _sanitizeOptionalText(currency),
    unit: _sanitizeOptionalText(unit),
    decimalPlaces: decimalPlaces,
    showPercent: showPercent,
    unknownFields: _freezeFields(unknownFields, rejectCli: true),
  );

  const ManagedProviderDisplayConfig._({
    this.currency,
    this.unit,
    this.decimalPlaces,
    this.showPercent = false,
    this.unknownFields = const {},
  });

  factory ManagedProviderDisplayConfig.fromJson(Map<String, Object?> json) =>
      ManagedProviderDisplayConfig(
        currency: json['currency'] as String?,
        unit: json['unit'] as String?,
        decimalPlaces: _parseIntegralInt(json['decimalPlaces']),
        showPercent: json['showPercent'] == true,
        unknownFields: _unknownFields(json, const {
          'currency',
          'unit',
          'decimalPlaces',
          'showPercent',
        }, rejectCli: true),
      );

  final String? currency;
  final String? unit;
  final int? decimalPlaces;
  final bool showPercent;
  final Map<String, Object?> unknownFields;

  Map<String, Object?> toJson() => {
    ..._thawFields(unknownFields, rejectCli: true),
    if (currency != null) 'currency': currency,
    if (unit != null) 'unit': unit,
    if (decimalPlaces != null) 'decimalPlaces': decimalPlaces,
    if (showPercent) 'showPercent': true,
  };

  @override
  List<Object?> get props => [
    currency,
    unit,
    decimalPlaces,
    showPercent,
    unknownFields,
  ];
}

@immutable
class ManagedProvider extends Equatable {
  factory ManagedProvider({
    required String id,
    required String name,
    required ManagedProviderKind kind,
    required String adapterId,
    ManagedProviderBrand? brand,
    String websiteUrl = '',
    ManagedProviderEndpointConfig? endpointConfig,
    String? credentialRef,
    ManagedProviderDisplayConfig? displayConfig,
    bool enabled = true,
    int createdAt = 0,
    int updatedAt = 0,
    int schemaVersion = 1,
    Map<String, Object?> unknownFields = const {},
  }) => ManagedProvider._(
    id: id,
    name: _sanitizeRequiredText(name),
    brand: brand ?? ManagedProviderBrand(),
    websiteUrl: _sanitizeUrl(websiteUrl),
    kind: kind,
    adapterId: _sanitizeRequiredText(adapterId),
    endpointConfig: endpointConfig ?? ManagedProviderEndpointConfig(),
    credentialRef: credentialRef,
    displayConfig: displayConfig ?? ManagedProviderDisplayConfig(),
    enabled: enabled,
    createdAt: createdAt,
    updatedAt: updatedAt,
    schemaVersion: schemaVersion,
    unknownFields: _freezeFields(unknownFields, rejectCli: true),
  );

  const ManagedProvider._({
    required this.id,
    required this.name,
    required this.brand,
    required this.websiteUrl,
    required this.kind,
    required this.adapterId,
    required this.endpointConfig,
    this.credentialRef,
    required this.displayConfig,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    required this.schemaVersion,
    required this.unknownFields,
  });

  factory ManagedProvider.fromJson(Map<String, Object?> json) =>
      ManagedProvider(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        brand: json['brand'] is Map
            ? ManagedProviderBrand.fromJson(
                Map<String, Object?>.from(json['brand'] as Map),
              )
            : null,
        websiteUrl: json['websiteUrl'] as String? ?? '',
        kind: ManagedProviderKind.fromJson(json['kind']),
        adapterId: json['adapterId'] as String? ?? '',
        endpointConfig: json['endpointConfig'] is Map
            ? ManagedProviderEndpointConfig.fromJson(
                Map<String, Object?>.from(json['endpointConfig'] as Map),
              )
            : null,
        credentialRef: json['credentialRef'] as String?,
        displayConfig: json['displayConfig'] is Map
            ? ManagedProviderDisplayConfig.fromJson(
                Map<String, Object?>.from(json['displayConfig'] as Map),
              )
            : null,
        enabled: json['enabled'] as bool? ?? true,
        createdAt: _parseIntegralInt(json['createdAt']) ?? 0,
        updatedAt: _parseIntegralInt(json['updatedAt']) ?? 0,
        schemaVersion: _parseIntegralInt(json['schemaVersion']) ?? 1,
        unknownFields: _unknownFields(json, const {
          'id',
          'name',
          'brand',
          'websiteUrl',
          'kind',
          'adapterId',
          'endpointConfig',
          'credentialRef',
          'displayConfig',
          'enabled',
          'createdAt',
          'updatedAt',
          'schemaVersion',
        }, rejectCli: true),
      );

  final String id;
  final String name;
  final ManagedProviderBrand brand;
  final String websiteUrl;
  final ManagedProviderKind kind;
  final String adapterId;
  final ManagedProviderEndpointConfig endpointConfig;
  final String? credentialRef;
  final ManagedProviderDisplayConfig displayConfig;
  final bool enabled;
  final int createdAt;
  final int updatedAt;
  final int schemaVersion;
  final Map<String, Object?> unknownFields;

  ManagedProvider copyWith({
    String? id,
    String? name,
    ManagedProviderBrand? brand,
    String? websiteUrl,
    ManagedProviderKind? kind,
    String? adapterId,
    ManagedProviderEndpointConfig? endpointConfig,
    String? credentialRef,
    ManagedProviderDisplayConfig? displayConfig,
    bool? enabled,
    int? createdAt,
    int? updatedAt,
    int? schemaVersion,
    Map<String, Object?>? unknownFields,
  }) => ManagedProvider(
    id: id ?? this.id,
    name: name ?? this.name,
    brand: brand ?? this.brand,
    websiteUrl: websiteUrl ?? this.websiteUrl,
    kind: kind ?? this.kind,
    adapterId: adapterId ?? this.adapterId,
    endpointConfig: endpointConfig ?? this.endpointConfig,
    credentialRef: credentialRef ?? this.credentialRef,
    displayConfig: displayConfig ?? this.displayConfig,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    unknownFields: unknownFields ?? this.unknownFields,
  );

  Map<String, Object?> toJson() => {
    ..._thawFields(unknownFields, rejectCli: true),
    'id': id,
    'name': name,
    'brand': brand.toJson(),
    'websiteUrl': websiteUrl,
    'kind': kind.value,
    'adapterId': adapterId,
    'endpointConfig': endpointConfig.toJson(),
    if (credentialRef != null) 'credentialRef': credentialRef,
    'displayConfig': displayConfig.toJson(),
    'enabled': enabled,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'schemaVersion': schemaVersion,
  };

  @override
  List<Object?> get props => [
    id,
    name,
    brand,
    websiteUrl,
    kind,
    adapterId,
    endpointConfig,
    credentialRef,
    displayConfig,
    enabled,
    createdAt,
    updatedAt,
    schemaVersion,
    unknownFields,
  ];
}

const _credentialKeys = {
  'apikey',
  'accesskey',
  'accesstoken',
  'authorization',
  'authtoken',
  'clientsecret',
  'credential',
  'credentials',
  'key',
  'oauthtoken',
  'password',
  'privatekey',
  'refreshtoken',
  'secret',
  'secretkey',
  'token',
};

String _normalizeKey(String key) => key
    .replaceAll('_', '')
    .replaceAll('-', '')
    .replaceAll(' ', '')
    .toLowerCase();

bool _isCredentialKey(String key) =>
    _credentialKeys.contains(_normalizeKey(key));

bool _containsCredentialMaterial(String value) => RegExp(
  r'''["']?(?:api[_\-\s]?key|access[_\-\s]?token|authorization|auth[_\-\s]?token|client[_\-\s]?secret|credential|private[_\-\s]?key|password|refresh[_\-\s]?token|oauth[_\-\s]?token|\bkey\b|\btoken\b)["']?\s*(?:=|:)\s*["']?\S+|bearer\s+\S+''',
  caseSensitive: false,
).hasMatch(value);

bool _isMappingCredentialKey(String key) =>
    _isCredentialKey(key) && _normalizeKey(key) != 'token';

bool _isMappingForbiddenKey(String key) =>
    _normalizeKey(key) == 'cli' || _isMappingCredentialKey(key);

String _sanitizeRequiredText(String value) =>
    _containsCredentialMaterial(value) ? '' : value;

String? _sanitizeOptionalText(String? value) {
  if (value == null || _containsCredentialMaterial(value)) return null;
  return value;
}

String? _sanitizeOptionalUrl(String? value) {
  if (value == null) return null;
  final sanitized = _sanitizeUrl(value);
  return sanitized.isEmpty && value.isNotEmpty ? null : sanitized;
}

String _sanitizeUrl(String value) {
  if (value.isEmpty) return value;
  late final Uri uri;
  try {
    uri = Uri.parse(value);
  } on FormatException {
    return _containsCredentialMaterial(value) || _containsUrlUserInfo(value)
        ? ''
        : value;
  }

  if (_containsCredentialMaterial(value) &&
      uri.queryParameters.isEmpty &&
      uri.fragment.isEmpty &&
      uri.userInfo.isEmpty) {
    return '';
  }

  var changed = uri.userInfo.isNotEmpty;
  final safeQuery = <String, String>{};
  for (final entry in uri.queryParameters.entries) {
    final unsafe =
        _isCredentialKey(entry.key) ||
        _containsCredentialMaterial(entry.value) ||
        _containsUrlUserInfo(entry.value);
    if (unsafe) {
      changed = true;
    } else {
      safeQuery[entry.key] = entry.value;
    }
  }
  final unsafeFragment =
      _containsCredentialMaterial(uri.fragment) ||
      _containsUrlUserInfo(uri.fragment);
  changed = changed || unsafeFragment;
  if (!changed) return value;

  var sanitized = uri
      .replace(
        userInfo: '',
        queryParameters: safeQuery,
        fragment: unsafeFragment ? '' : null,
      )
      .toString();
  sanitized = sanitized.replaceFirst(RegExp(r'\?(?=#|$)'), '');
  return unsafeFragment && sanitized.endsWith('#')
      ? sanitized.substring(0, sanitized.length - 1)
      : sanitized;
}

bool _containsUrlUserInfo(String value) => RegExp(
  r'''(?:(?:[a-z][a-z0-9+.-]*:)?//)[^/?#\s@]+(?::[^/?#\s@]*)?@''',
  caseSensitive: false,
).hasMatch(value);

int? _parseIntegralInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num && raw.isFinite && raw == raw.truncateToDouble()) {
    return raw.toInt();
  }
  return null;
}

class _RedactedMappingValue {
  const _RedactedMappingValue();
}

const _redactedMappingValue = _RedactedMappingValue();

Map<String, Object?> _freezeMappingFields(Map<String, Object?> fields) =>
    Map.unmodifiable({
      for (final entry in fields.entries)
        if (!_isMappingForbiddenKey(entry.key))
          ..._mappingEntry(entry.key, _freezeMappingValue(entry.value)),
    });

Map<String, Object?> _mappingEntry(String key, Object? value) =>
    value == _redactedMappingValue ? const {} : {key: value};

Object? _freezeMappingValue(Object? value) {
  if (value is Map) {
    return _freezeMappingFields(Map<String, Object?>.from(value));
  }
  if (value is List) {
    return List.unmodifiable(
      value.map((item) {
        final sanitized = _freezeMappingValue(item);
        return sanitized == _redactedMappingValue ? null : sanitized;
      }),
    );
  }
  if (value is String &&
      ((_isCredentialKey(value) && _normalizeKey(value) != 'token') ||
          _containsCredentialMaterial(value))) {
    return _redactedMappingValue;
  }
  return value;
}

Map<String, Object?> _thawMappingFields(Map<String, Object?> fields) => {
  for (final entry in fields.entries) entry.key: _thawMappingValue(entry.value),
};

Object? _thawMappingValue(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String)
          entry.key as String: _thawMappingValue(entry.value),
    };
  }
  if (value is List) return value.map(_thawMappingValue).toList();
  return value;
}

bool _isForbiddenKey(
  String key, {
  required bool rejectCli,
  bool filterCredentials = true,
}) =>
    filterCredentials && _isCredentialKey(key) ||
    rejectCli && _normalizeKey(key) == 'cli';

Map<String, Object?> _unknownFields(
  Map<String, Object?> json,
  Set<String> known, {
  required bool rejectCli,
}) => _freezeFields({
  for (final entry in json.entries)
    if (!known.contains(entry.key)) entry.key: entry.value,
}, rejectCli: rejectCli);

Map<String, Object?> _freezeFields(
  Map<String, Object?> fields, {
  bool rejectCli = false,
  bool filterCredentials = true,
}) => Map.unmodifiable({
  for (final entry in fields.entries)
    if (!_isForbiddenKey(
      entry.key,
      rejectCli: rejectCli,
      filterCredentials: filterCredentials,
    ))
      ..._mappingEntry(
        entry.key,
        _freezeValue(
          entry.value,
          rejectCli: rejectCli,
          filterCredentials: filterCredentials,
        ),
      ),
});

Object? _freezeValue(
  Object? value, {
  required bool rejectCli,
  bool filterCredentials = true,
}) {
  if (value is Map) {
    return Map.unmodifiable({
      for (final entry in value.entries)
        if (entry.key is String &&
            !_isForbiddenKey(
              entry.key as String,
              rejectCli: rejectCli,
              filterCredentials: filterCredentials,
            ))
          ..._mappingEntry(
            entry.key as String,
            _freezeValue(
              entry.value,
              rejectCli: rejectCli,
              filterCredentials: filterCredentials,
            ),
          ),
    });
  }
  if (value is List) {
    return List.unmodifiable(
      value.map((item) {
        final frozen = _freezeValue(
          item,
          rejectCli: rejectCli,
          filterCredentials: filterCredentials,
        );
        return frozen == _redactedMappingValue ? null : frozen;
      }),
    );
  }
  if (value is String && _containsCredentialMaterial(value)) {
    return _redactedMappingValue;
  }
  return value;
}

Map<String, Object?> _thawFields(
  Map<String, Object?> fields, {
  bool rejectCli = false,
  bool filterCredentials = true,
}) => {
  for (final entry in fields.entries)
    if (!_isForbiddenKey(
      entry.key,
      rejectCli: rejectCli,
      filterCredentials: filterCredentials,
    ))
      entry.key: _thawValue(
        entry.value,
        rejectCli: rejectCli,
        filterCredentials: filterCredentials,
      ),
};

Object? _thawValue(
  Object? value, {
  required bool rejectCli,
  bool filterCredentials = true,
}) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String &&
            !_isForbiddenKey(
              entry.key as String,
              rejectCli: rejectCli,
              filterCredentials: filterCredentials,
            ))
          entry.key as String: _thawValue(
            entry.value,
            rejectCli: rejectCli,
            filterCredentials: filterCredentials,
          ),
    };
  }
  if (value is List) {
    return value
        .map(
          (item) => _thawValue(
            item,
            rejectCli: rejectCli,
            filterCredentials: filterCredentials,
          ),
        )
        .toList();
  }
  return value;
}
