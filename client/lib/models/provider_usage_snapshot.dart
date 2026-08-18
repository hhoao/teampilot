import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:equatable/equatable.dart';

enum ProviderUsageStatus {
  loading('loading'),
  ready('ready'),
  stale('stale'),
  error('error'),
  unsupported('unsupported'),
  unknown('unknown');

  const ProviderUsageStatus(this.value);
  final String value;

  static ProviderUsageStatus fromJson(Object? raw) {
    for (final status in values) {
      if (status.value == raw?.toString().trim()) return status;
    }
    return ProviderUsageStatus.unknown;
  }
}

enum ProviderUsageMeasureKind {
  balance('balance'),
  quota('quota'),
  token('token'),
  rateLimit('rateLimit'),
  unknown('unknown');

  const ProviderUsageMeasureKind(this.value);
  final String value;

  static ProviderUsageMeasureKind fromJson(Object? raw) {
    for (final kind in values) {
      if (kind.value == raw?.toString().trim()) return kind;
    }
    return ProviderUsageMeasureKind.unknown;
  }
}

@immutable
class ProviderUsageMeasure extends Equatable {
  factory ProviderUsageMeasure({
    required String label,
    required ProviderUsageMeasureKind kind,
    String? total,
    String? used,
    String? remaining,
    String? unit,
    String? currency,
    int? resetsAt,
    Map<String, Object?> unknownFields = const {},
  }) => ProviderUsageMeasure._(
    label: _sanitizeRequiredText(label),
    kind: kind,
    total: _clampPercentage(_decimalString(total, 'total'), unit),
    used: _clampPercentage(_decimalString(used, 'used'), unit),
    remaining: _clampPercentage(_decimalString(remaining, 'remaining'), unit),
    unit: _sanitizeOptionalText(unit),
    currency: _sanitizeOptionalText(currency),
    resetsAt: resetsAt,
    unknownFields: _freezeFields(unknownFields),
  );

  const ProviderUsageMeasure._({
    required this.label,
    required this.kind,
    this.total,
    this.used,
    this.remaining,
    this.unit,
    this.currency,
    this.resetsAt,
    this.unknownFields = const {},
  });

  factory ProviderUsageMeasure.fromJson(Map<String, Object?> json) {
    final label = json['label'];
    final unit = json['unit'];
    final currency = json['currency'];
    final resetsAt = json['resetsAt'];
    final parsedResetsAt = _parseIntegralInt(resetsAt);
    if (label is! String || unit != null && unit is! String) {
      throw const FormatException('invalid provider usage measure');
    }
    if (currency != null && currency is! String ||
        resetsAt != null && parsedResetsAt == null ||
        json['total'] != null && json['total'] is! String ||
        json['used'] != null && json['used'] is! String ||
        json['remaining'] != null && json['remaining'] is! String) {
      throw const FormatException('invalid provider usage measure');
    }
    return ProviderUsageMeasure(
      label: label,
      kind: ProviderUsageMeasureKind.fromJson(json['kind']),
      total: json['total'] as String?,
      used: json['used'] as String?,
      remaining: json['remaining'] as String?,
      unit: unit as String?,
      currency: currency as String?,
      resetsAt: parsedResetsAt,
      unknownFields: _unknownFields(json, _measureKnownKeys),
    );
  }

  final String label;
  final ProviderUsageMeasureKind kind;
  final String? total;
  final String? used;
  final String? remaining;
  final String? unit;
  final String? currency;
  final int? resetsAt;
  final Map<String, Object?> unknownFields;

  ProviderUsageMeasure copyWith({
    String? label,
    ProviderUsageMeasureKind? kind,
    String? total,
    String? used,
    String? remaining,
    String? unit,
    String? currency,
    int? resetsAt,
    Map<String, Object?>? unknownFields,
  }) => ProviderUsageMeasure(
    label: label ?? this.label,
    kind: kind ?? this.kind,
    total: total ?? this.total,
    used: used ?? this.used,
    remaining: remaining ?? this.remaining,
    unit: unit ?? this.unit,
    currency: currency ?? this.currency,
    resetsAt: resetsAt ?? this.resetsAt,
    unknownFields: unknownFields ?? this.unknownFields,
  );

  Map<String, Object?> toJson() => {
    ..._thawFields(unknownFields),
    'label': label,
    'kind': kind.value,
    if (total != null) 'total': _clampPercentage(total, unit),
    if (used != null) 'used': _clampPercentage(used, unit),
    if (remaining != null) 'remaining': _clampPercentage(remaining, unit),
    if (unit != null) 'unit': unit,
    if (currency != null) 'currency': currency,
    if (resetsAt != null) 'resetsAt': resetsAt,
  };

  @override
  List<Object?> get props => [
    label,
    kind,
    total,
    used,
    remaining,
    unit,
    currency,
    resetsAt,
    unknownFields,
  ];
}

@immutable
class ProviderUsageSnapshot extends Equatable {
  factory ProviderUsageSnapshot({
    required String providerId,
    required ProviderUsageStatus status,
    List<ProviderUsageMeasure>? measures,
    int? fetchedAt,
    int? staleAt,
    String? lastErrorCode,
    String? lastErrorMessage,
    String? adapterVersion,
    int schemaVersion = 1,
    Map<String, Object?> unknownFields = const {},
  }) => ProviderUsageSnapshot._(
    providerId: providerId,
    status: status,
    measures: List.unmodifiable(measures ?? const []),
    fetchedAt: fetchedAt,
    staleAt: staleAt,
    lastErrorCode: _sanitizeOptionalText(lastErrorCode),
    lastErrorMessage: _safeErrorMessage(lastErrorMessage),
    adapterVersion: _sanitizeOptionalText(adapterVersion),
    schemaVersion: schemaVersion,
    unknownFields: _freezeFields(unknownFields),
  );

  const ProviderUsageSnapshot._({
    required this.providerId,
    required this.status,
    required this.measures,
    this.fetchedAt,
    this.staleAt,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.adapterVersion,
    this.schemaVersion = 1,
    this.unknownFields = const {},
  });

  factory ProviderUsageSnapshot.fromJson(Map<String, Object?> json) {
    final measures = <ProviderUsageMeasure>[];
    final rawMeasures = json['measures'];
    if (rawMeasures is List) {
      for (final raw in rawMeasures) {
        if (raw is! Map) continue;
        try {
          measures.add(
            ProviderUsageMeasure.fromJson(Map<String, Object?>.from(raw)),
          );
        } on FormatException {
          // Preserve valid cached measures when one entry is malformed.
        } on TypeError {
          // Preserve valid cached measures when one entry is malformed.
        }
      }
    }
    final errorCode = json['lastErrorCode'];
    final errorMessage = json['lastErrorMessage'];
    final adapterVersion = json['adapterVersion'];
    final fetchedAt = _parseIntegralInt(json['fetchedAt']);
    final staleAt = _parseIntegralInt(json['staleAt']);
    if (errorCode != null && errorCode is! String ||
        errorMessage != null && errorMessage is! String ||
        adapterVersion != null && adapterVersion is! String) {
      throw const FormatException('invalid provider usage snapshot');
    }
    return ProviderUsageSnapshot(
      providerId: json['providerId'] as String? ?? '',
      status: ProviderUsageStatus.fromJson(json['status']),
      measures: measures,
      fetchedAt: fetchedAt,
      staleAt: staleAt,
      lastErrorCode: errorCode as String?,
      lastErrorMessage: errorMessage as String?,
      adapterVersion: adapterVersion as String?,
      schemaVersion: _parseIntegralInt(json['schemaVersion']) ?? 1,
      unknownFields: _unknownFields(json, _snapshotKnownKeys),
    );
  }

  final String providerId;
  final ProviderUsageStatus status;
  final List<ProviderUsageMeasure> measures;
  final int? fetchedAt;
  final int? staleAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final String? adapterVersion;
  final int schemaVersion;
  final Map<String, Object?> unknownFields;

  ProviderUsageSnapshot copyWith({
    String? providerId,
    ProviderUsageStatus? status,
    List<ProviderUsageMeasure>? measures,
    int? fetchedAt,
    int? staleAt,
    String? lastErrorCode,
    String? lastErrorMessage,
    String? adapterVersion,
    int? schemaVersion,
    Map<String, Object?>? unknownFields,
  }) => ProviderUsageSnapshot(
    providerId: providerId ?? this.providerId,
    status: status ?? this.status,
    measures: measures ?? this.measures,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    staleAt: staleAt ?? this.staleAt,
    lastErrorCode: lastErrorCode ?? this.lastErrorCode,
    lastErrorMessage: lastErrorMessage ?? this.lastErrorMessage,
    adapterVersion: adapterVersion ?? this.adapterVersion,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    unknownFields: unknownFields ?? this.unknownFields,
  );

  Map<String, Object?> toJson() => {
    ..._thawFields(unknownFields),
    'providerId': providerId,
    'status': status.value,
    'measures': measures.map((measure) => measure.toJson()).toList(),
    if (fetchedAt != null) 'fetchedAt': fetchedAt,
    if (staleAt != null) 'staleAt': staleAt,
    if (lastErrorCode != null) 'lastErrorCode': lastErrorCode,
    if (lastErrorMessage != null) 'lastErrorMessage': lastErrorMessage,
    if (adapterVersion != null) 'adapterVersion': adapterVersion,
    'schemaVersion': schemaVersion,
  };

  @override
  List<Object?> get props => [
    providerId,
    status,
    measures,
    fetchedAt,
    staleAt,
    lastErrorCode,
    lastErrorMessage,
    adapterVersion,
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

bool _containsCredentialMaterial(String message) => RegExp(
  r'''["']?(?:api[_\-\s]?key|access[_\-\s]?token|authorization|auth[_\-\s]?token|client[_\-\s]?secret|credential|private[_\-\s]?key|password|refresh[_\-\s]?token|oauth[_\-\s]?token|\bkey\b|\btoken\b)["']?\s*(?:=|:)\s*["']?\S+|bearer\s+\S+''',
  caseSensitive: false,
).hasMatch(message);

String _sanitizeRequiredText(String value) =>
    _containsCredentialMaterial(value) ? '' : value;

String? _sanitizeOptionalText(String? value) {
  if (value == null || _containsCredentialMaterial(value)) return null;
  return value;
}

class _RedactedValue {
  const _RedactedValue();
}

const _redactedValue = _RedactedValue();

String? _safeErrorMessage(String? message) {
  if (message == null) return null;
  final sanitized = _sanitizeValue(message);
  return sanitized == _redactedValue ? null : sanitized as String?;
}

Map<String, Object?> _unknownFields(
  Map<String, Object?> json,
  Set<String> knownKeys,
) => _freezeFields({
  for (final entry in json.entries)
    if (!knownKeys.contains(entry.key)) entry.key: entry.value,
});

const _measureKnownKeys = {
  'label',
  'kind',
  'total',
  'used',
  'remaining',
  'unit',
  'currency',
  'resetsAt',
};

const _snapshotKnownKeys = {
  'providerId',
  'status',
  'measures',
  'fetchedAt',
  'staleAt',
  'lastErrorCode',
  'lastErrorMessage',
  'adapterVersion',
  'schemaVersion',
};

Map<String, Object?> _freezeFields(Map<String, Object?> fields) =>
    Map.unmodifiable({
      for (final entry in fields.entries)
        if (!_isCredentialKey(entry.key))
          ..._sanitizedEntry(entry.key, _sanitizeValue(entry.value)),
    });

Map<String, Object?> _sanitizedEntry(String key, Object? value) =>
    value == _redactedValue ? const {} : {key: value};

Object? _sanitizeValue(Object? value) {
  if (value is String) {
    if (!_containsCredentialMaterial(value)) return value;
    try {
      final decoded = jsonDecode(value);
      final sanitized = _sanitizeValue(decoded);
      if (sanitized == _redactedValue) return _redactedValue;
      return jsonEncode(sanitized);
    } on FormatException {
      return _redactedValue;
    }
  }
  if (value is Map) {
    return Map.unmodifiable({
      for (final entry in value.entries)
        if (entry.key is String && !_isCredentialKey(entry.key as String))
          ..._sanitizedEntry(entry.key as String, _sanitizeValue(entry.value)),
    });
  }
  if (value is List) {
    return List.unmodifiable(
      value.map((item) {
        final sanitized = _sanitizeValue(item);
        return sanitized == _redactedValue ? null : sanitized;
      }),
    );
  }
  return value;
}

Map<String, Object?> _thawFields(Map<String, Object?> fields) => {
  for (final entry in fields.entries)
    if (!_isCredentialKey(entry.key)) entry.key: _thawValue(entry.value),
};

Object? _thawValue(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String && !_isCredentialKey(entry.key as String))
          entry.key as String: _thawValue(entry.value),
    };
  }
  if (value is List) return value.map(_thawValue).toList();
  return value;
}

String? _decimalString(String? value, String field) {
  if (value == null) return null;
  if (!RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(value)) {
    throw FormatException('invalid decimal string for $field');
  }
  return value;
}

String? _clampPercentage(String? value, String? unit) {
  if (value == null || !_isPercentageUnit(unit)) return value;
  if (value.startsWith('-')) return '0';
  final parts = value.split('.');
  final integerPart = parts.first.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (integerPart.length > 3 ||
      integerPart.length == 3 && integerPart.compareTo('100') > 0 ||
      integerPart == '100' &&
          parts.length == 2 &&
          RegExp(r'[1-9]').hasMatch(parts[1])) {
    return '100';
  }
  return value;
}

bool _isPercentageUnit(String? unit) {
  final normalized = unit?.trim().toLowerCase();
  return normalized == '%' ||
      normalized == 'percent' ||
      normalized == 'percentage';
}

int? _parseIntegralInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num && raw.isFinite && raw == raw.truncateToDouble()) {
    return raw.toInt();
  }
  return null;
}
