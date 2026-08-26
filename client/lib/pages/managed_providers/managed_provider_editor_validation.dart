import 'dart:convert';

import '../../models/managed_provider.dart';

Map<String, Object?>? decodeJsonObject(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const {};
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;
    return Map<String, Object?>.from(decoded);
  } on Object {
    return null;
  }
}

bool mappingContainsCredentialKey(Object? mapping) =>
    mapping is Map<String, Object?> && _containsCredentialKey(mapping);

bool _containsCredentialKey(Map<String, Object?> value) {
  for (final entry in value.entries) {
    if (isManagedProviderCredentialKey(entry.key)) return true;
    final nested = entry.value;
    if (nested is Map &&
        _containsCredentialKey(Map<String, Object?>.from(nested))) {
      return true;
    }
    if (nested is List) {
      for (final item in nested) {
        if (item is Map &&
            _containsCredentialKey(Map<String, Object?>.from(item))) {
          return true;
        }
      }
    }
  }
  return false;
}

bool isAllowedManagedProviderEndpoint(
  String endpoint, {
  required bool allowHttpLocalhost,
}) {
  if (!allowHttpLocalhost) return true;
  final uri = Uri.tryParse(endpoint);
  if (uri == null || uri.host.isEmpty) return false;
  if (uri.scheme == 'https') return true;
  const loopback = {'localhost', '127.0.0.1', '::1'};
  return loopback.contains(uri.host.toLowerCase()) &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}
