import 'dart:convert';

/// Validates OpenCode `auth.json` provider entries.
abstract final class OpencodeAuthArtifacts {
  OpencodeAuthArtifacts._();

  static bool authJsonIndicatesReady(String? content, String providerKey) {
    if (content == null || content.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) return false;
      return entryIndicatesReady(
        decoded.cast<String, Object?>(),
        providerKey,
      );
    } on Object {
      return false;
    }
  }

  static bool entryIndicatesReady(
    Map<String, Object?> auth,
    String providerKey,
  ) {
    final key = providerKey.trim();
    if (key.isEmpty) return false;
    final entry = auth[key];
    if (entry is! Map) return false;
    final map = entry.cast<String, Object?>();
    if (map.isEmpty) return false;

    final type = map['type']?.toString().trim() ?? '';
    if (type == 'api') {
      return (map['key']?.toString().trim() ?? '').isNotEmpty;
    }
    if (type == 'oauth') {
      return (map['access']?.toString().trim() ?? '').isNotEmpty;
    }
    if (type == 'wellknown') {
      return (map['token']?.toString().trim() ?? '').isNotEmpty;
    }
    return map.isNotEmpty;
  }
}
