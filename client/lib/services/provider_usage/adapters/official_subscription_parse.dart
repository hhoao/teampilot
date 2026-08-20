import 'dart:convert';

import '../../../models/provider_usage_snapshot.dart';
import '../managed_provider_usage_adapter.dart';
import 'official_subscription_adapter.dart';

void throwOfficialHttpStatus(int statusCode) {
  if (statusCode == 401 || statusCode == 403) {
    throw const ManagedProviderUsageQueryError(
      ManagedProviderUsageQueryErrorCode.authenticationFailed,
    );
  }
  if (statusCode < 200 || statusCode >= 300) {
    throw const ManagedProviderUsageQueryError(
      ManagedProviderUsageQueryErrorCode.httpFailed,
    );
  }
}

Map<String, Object?> decodeOfficialJsonObject(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  } on ManagedProviderUsageQueryError {
    rethrow;
  } on Object {
    throw const ManagedProviderUsageQueryError(
      ManagedProviderUsageQueryErrorCode.responseParseFailed,
    );
  }
}

OfficialSubscriptionWindow officialPercentWindow({
  required String label,
  required num used,
  int? resetsAt,
}) {
  final clamped = used.clamp(0, 100);
  return OfficialSubscriptionWindow(
    label: label,
    kind: ProviderUsageMeasureKind.quota,
    total: '100',
    used: formatOfficialPercent(clamped),
    remaining: formatOfficialPercent((100 - clamped).clamp(0, 100)),
    unit: '%',
    resetsAt: resetsAt,
  );
}

String formatOfficialPercent(num value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toString();
}

num? readOfficialPercent(Object? raw) {
  if (raw is num) return raw;
  if (raw is String) return num.tryParse(raw.trim());
  return null;
}

int? parseOfficialResetAt(Object? raw) {
  if (raw is num) {
    final value = raw.toInt();
    return value > 10_000_000_000 ? value : value * 1000;
  }
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final numeric = num.tryParse(trimmed);
    if (numeric != null) {
      return parseOfficialResetAt(numeric);
    }
    return DateTime.tryParse(trimmed)?.millisecondsSinceEpoch;
  }
  return null;
}

String officialCodexWindowLabel(int? windowSeconds) {
  return switch (windowSeconds) {
    18000 => '5h',
    604800 => 'Weekly',
    2592000 => '30d',
    null => 'Quota',
    final seconds when seconds >= 86400 => '${seconds ~/ 86400}d',
    final seconds => '${seconds ~/ 3600}h',
  };
}
