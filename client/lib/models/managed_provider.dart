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
    final value = raw?.toString().trim();
    for (final kind in values) {
      if (kind.value == value) return kind;
    }
    return ManagedProviderKind.unknown;
  }
}

/// Non-sensitive provider branding used by the global provider catalog.
@immutable
class ManagedProviderBrand extends Equatable {
  const ManagedProviderBrand({
    this.name = '',
    this.iconUrl,
    this.iconColor,
    this.unknownFields = const {},
  });

  factory ManagedProviderBrand.fromJson(Map<String, Object?> json) {
    return ManagedProviderBrand(
      name: json['name'] as String? ?? '',
      iconUrl: json['iconUrl'] as String?,
      iconColor: json['iconColor'] as String?,
      unknownFields: _unknownFields(json, _knownKeys),
    );
  }

  static const _knownKeys = {'name', 'iconUrl', 'iconColor'};

  final String name;
  final String? iconUrl;
  final String? iconColor;
  final Map<String, Object?> unknownFields;

  Map<String, Object?> toJson() => {
    ..._safeUnknownFields(unknownFields),
    'name': name,
    if (iconUrl != null) 'iconUrl': iconUrl,
    if (iconColor != null) 'iconColor': iconColor,
  };

  @override
  List<Object?> get props => [name, iconUrl, iconColor, unknownFields];
}

/// Non-sensitive endpoint and response mapping settings for a usage adapter.
@immutable
class ManagedProviderEndpointConfig extends Equatable {
  const ManagedProviderEndpointConfig({
    this.url = '',
    this.method = 'GET',
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
          ? _safeUnknownFields(Map<String, Object?>.from(mappings))
          : const {},
      unknownFields: _unknownFields(json, _knownKeys),
    );
  }

  static const _knownKeys = {
    'url',
    'method',
    'responsePath',
    'measuresPath',
    'fieldMappings',
  };

  final String url;
  final String method;
  final String? responsePath;
  final String? measuresPath;
  final Map<String, Object?> fieldMappings;
  final Map<String, Object?> unknownFields;

  Map<String, Object?> toJson() => {
    ..._safeUnknownFields(unknownFields),
    'url': url,
    'method': method,
    if (responsePath != null) 'responsePath': responsePath,
    if (measuresPath != null) 'measuresPath': measuresPath,
    if (fieldMappings.isNotEmpty)
      'fieldMappings': _safeUnknownFields(fieldMappings),
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

/// Formatting preferences only; credentials and response data do not belong here.
@immutable
class ManagedProviderDisplayConfig extends Equatable {
  const ManagedProviderDisplayConfig({
    this.currency,
    this.unit,
    this.decimalPlaces,
    this.showPercent = false,
    this.unknownFields = const {},
  });

  factory ManagedProviderDisplayConfig.fromJson(Map<String, Object?> json) {
    return ManagedProviderDisplayConfig(
      currency: json['currency'] as String?,
      unit: json['unit'] as String?,
      decimalPlaces: (json['decimalPlaces'] as num?)?.toInt(),
      showPercent: json['showPercent'] == true,
      unknownFields: _unknownFields(json, _knownKeys),
    );
  }

  static const _knownKeys = {
    'currency',
    'unit',
    'decimalPlaces',
    'showPercent',
  };

  final String? currency;
  final String? unit;
  final int? decimalPlaces;
  final bool showPercent;
  final Map<String, Object?> unknownFields;

  Map<String, Object?> toJson() => {
    ..._safeUnknownFields(unknownFields),
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

/// A provider managed independently from CLI-scoped provider configuration.
@immutable
class ManagedProvider extends Equatable {
  const ManagedProvider({
    required this.id,
    required this.name,
    required this.kind,
    required this.adapterId,
    this.brand = const ManagedProviderBrand(),
    this.websiteUrl = '',
    this.endpointConfig = const ManagedProviderEndpointConfig(),
    this.credentialRef,
    this.displayConfig = const ManagedProviderDisplayConfig(),
    this.enabled = true,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.schemaVersion = 1,
    this.unknownFields = const {},
  });

  factory ManagedProvider.fromJson(Map<String, Object?> json) {
    final brand = json['brand'];
    final endpointConfig = json['endpointConfig'];
    final displayConfig = json['displayConfig'];
    return ManagedProvider(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      brand: brand is Map
          ? ManagedProviderBrand.fromJson(Map<String, Object?>.from(brand))
          : const ManagedProviderBrand(),
      websiteUrl: json['websiteUrl'] as String? ?? '',
      kind: ManagedProviderKind.fromJson(json['kind']),
      adapterId: json['adapterId'] as String? ?? '',
      endpointConfig: endpointConfig is Map
          ? ManagedProviderEndpointConfig.fromJson(
              Map<String, Object?>.from(endpointConfig),
            )
          : const ManagedProviderEndpointConfig(),
      credentialRef: json['credentialRef'] as String?,
      displayConfig: displayConfig is Map
          ? ManagedProviderDisplayConfig.fromJson(
              Map<String, Object?>.from(displayConfig),
            )
          : const ManagedProviderDisplayConfig(),
      enabled: json['enabled'] as bool? ?? true,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      unknownFields: _unknownFields(json, _knownKeys),
    );
  }

  static const _knownKeys = {
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
  };

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
    ..._safeUnknownFields(unknownFields),
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

const _credentialKeyFragments = {
  'apikey',
  'accesstoken',
  'authorization',
  'clientsecret',
  'password',
  'secret',
  'token',
};

bool _isCredentialKey(String key) {
  final normalized = key.replaceAll('_', '').replaceAll('-', '').toLowerCase();
  return _credentialKeyFragments.any(normalized.contains) ||
      normalized == 'cli';
}

Map<String, Object?> _unknownFields(
  Map<String, Object?> json,
  Set<String> knownKeys,
) => {
  for (final entry in json.entries)
    if (!knownKeys.contains(entry.key) && !_isCredentialKey(entry.key))
      entry.key: _sanitizeUnknown(entry.value),
};

Map<String, Object?> _safeUnknownFields(Map<String, Object?> fields) => {
  for (final entry in fields.entries)
    if (!_isCredentialKey(entry.key)) entry.key: _sanitizeUnknown(entry.value),
};

Object? _sanitizeUnknown(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String && !_isCredentialKey(entry.key as String))
          entry.key as String: _sanitizeUnknown(entry.value),
    };
  }
  if (value is List) return value.map(_sanitizeUnknown).toList(growable: false);
  return value;
}
