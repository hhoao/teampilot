import 'dart:convert';

import '../../../models/provider_usage_snapshot.dart';
import '../managed_provider_usage_adapter.dart';

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

String formatOfficialPercent(num value) {
  if (!value.isFinite) return '0';
  final rounded = (value * 10).roundToDouble() / 10;
  if (rounded == rounded.roundToDouble()) {
    return rounded.round().toString();
  }
  return rounded.toStringAsFixed(1);
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
