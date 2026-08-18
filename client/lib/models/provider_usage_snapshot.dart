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
    final value = raw?.toString().trim();
    for (final status in values) {
      if (status.value == value) return status;
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
    final value = raw?.toString().trim();
    for (final kind in values) {
      if (kind.value == value) return kind;
    }
    return ProviderUsageMeasureKind.unknown;
  }
}

@immutable
class ProviderUsageMeasure extends Equatable {
  const ProviderUsageMeasure({
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
    if (label is! String || unit != null && unit is! String) {
      throw const FormatException('invalid provider usage measure');
    }
    final unitString = unit is String ? unit : null;

    final total = _decimalString(json['total'], 'total');
    final used = _decimalString(json['used'], 'used');
    final remaining = _decimalString(json['remaining'], 'remaining');
    final currency = json['currency'];
    if (currency != null && currency is! String) {
      throw const FormatException('invalid provider usage currency');
    }
    final resetsAt = json['resetsAt'];
    if (resetsAt != null && resetsAt is! num) {
      throw const FormatException('invalid provider usage reset time');
    }

    return ProviderUsageMeasure(
      label: label,
      kind: ProviderUsageMeasureKind.fromJson(json['kind']),
      total: _clampPercentage(total, unitString),
      used: _clampPercentage(used, unitString),
      remaining: _clampPercentage(remaining, unitString),
      unit: unitString,
      currency: currency as String?,
      resetsAt: (resetsAt as num?)?.toInt(),
      unknownFields: _unknownFields(json, _knownKeys),
    );
  }

  static const _knownKeys = {
    'label',
    'kind',
    'total',
    'used',
    'remaining',
    'unit',
    'currency',
    'resetsAt',
  };

  final String label;
  final ProviderUsageMeasureKind kind;
  final String? total;
  final String? used;
  final String? remaining;
  final String? unit;
  final String? currency;
  final int? resetsAt;
  final Map<String, Object?> unknownFields;

  Map<String, Object?> toJson() => {
    ..._safeUnknownFields(unknownFields),
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
  const ProviderUsageSnapshot({
    required this.providerId,
    required this.status,
    this.measures = const [],
    this.fetchedAt,
    this.staleAt,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.adapterVersion,
    this.schemaVersion = 1,
    this.unknownFields = const {},
  });

  factory ProviderUsageSnapshot.fromJson(Map<String, Object?> json) {
    final rawMeasures = json['measures'];
    final measures = <ProviderUsageMeasure>[];
    if (rawMeasures is List) {
      for (final raw in rawMeasures) {
        if (raw is! Map) continue;
        try {
          measures.add(
            ProviderUsageMeasure.fromJson(Map<String, Object?>.from(raw)),
          );
        } on FormatException {
          // A malformed measure must not discard the other cached measures.
        } on TypeError {
          // A malformed measure must not discard the other cached measures.
        }
      }
    }

    final lastErrorCode = json['lastErrorCode'];
    final lastErrorMessage = json['lastErrorMessage'];
    final adapterVersion = json['adapterVersion'];
    if (lastErrorCode != null && lastErrorCode is! String ||
        lastErrorMessage != null && lastErrorMessage is! String ||
        adapterVersion != null && adapterVersion is! String) {
      throw const FormatException('invalid provider usage snapshot');
    }

    return ProviderUsageSnapshot(
      providerId: json['providerId'] as String? ?? '',
      status: ProviderUsageStatus.fromJson(json['status']),
      measures: List.unmodifiable(measures),
      fetchedAt: (json['fetchedAt'] as num?)?.toInt(),
      staleAt: (json['staleAt'] as num?)?.toInt(),
      lastErrorCode: lastErrorCode as String?,
      lastErrorMessage: lastErrorMessage as String?,
      adapterVersion: adapterVersion as String?,
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      unknownFields: _unknownFields(json, _knownKeys),
    );
  }

  static const _knownKeys = {
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
    ..._safeUnknownFields(unknownFields),
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
  return _credentialKeyFragments.any(normalized.contains);
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

String? _decimalString(Object? raw, String field) {
  if (raw == null) return null;
  if (raw is! String || !RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(raw)) {
    throw FormatException('invalid decimal string for $field');
  }
  return raw;
}

String? _clampPercentage(String? value, String? unit) {
  if (value == null || !_isPercentageUnit(unit)) return value;
  if (value.startsWith('-')) return '0';
  final unsigned = value;
  final parts = unsigned.split('.');
  final integerPart = parts.first.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (integerPart.length > 3 ||
      integerPart.length == 3 && integerPart.compareTo('100') > 0) {
    return '100';
  }
  if (integerPart == '100' &&
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
