/// Parses Claude `settings.json` snippets and detects CC Switch proxy takeover.
abstract final class ClaudeSettingsParser {
  ClaudeSettingsParser._();

  static const proxyManagedToken = 'PROXY_MANAGED';

  static const _authTokenKeys = ['ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY'];

  static Map<String, Object?> envFromSettings(Map<String, Object?> settings) {
    final raw = settings['env'];
    if (raw is! Map) return const {};
    return Map<String, Object?>.from(raw);
  }

  static bool detectProxyTakeover(Map<String, Object?> env) {
    for (final key in _authTokenKeys) {
      if (env[key]?.toString() == proxyManagedToken) return true;
    }
    final baseUrl = env['ANTHROPIC_BASE_URL']?.toString().toLowerCase() ?? '';
    if (baseUrl.isEmpty) return false;
    return baseUrl.contains('127.0.0.1') ||
        baseUrl.contains('localhost') ||
        baseUrl.contains(':15721');
  }
}
