import 'dart:convert';

import 'codex_toml_parser.dart';

/// Validates Codex `auth.json` contents under a provider or session [CODEX_HOME].
abstract final class CodexAuthArtifacts {
  CodexAuthArtifacts._();

  static const authFileName = 'auth.json';

  static bool authJsonIndicatesReady(String? content) {
    if (content == null || content.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(content);
      return decoded is Map && _mapIndicatesReady(decoded.cast<String, Object?>());
    } on Object {
      return false;
    }
  }

  static bool mapIndicatesReady(Map<String, Object?> auth) {
    return _mapIndicatesReady(auth);
  }

  static bool _mapIndicatesReady(Map<String, Object?> auth) {
    if (auth.isEmpty) return false;

    final apiKey = auth['OPENAI_API_KEY']?.toString().trim() ?? '';
    if (apiKey.isNotEmpty && apiKey != CodexTomlParser.proxyManagedToken) {
      return true;
    }

    const oauthHints = <String>[
      'tokens',
      'refresh_token',
      'access_token',
      'account_id',
      'last_refresh',
    ];
    for (final key in oauthHints) {
      if (auth.containsKey(key)) return true;
    }

    for (final value in auth.values) {
      if (value is Map && value.isNotEmpty) return true;
    }
    return false;
  }
}
