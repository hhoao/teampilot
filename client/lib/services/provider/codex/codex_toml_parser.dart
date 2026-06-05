/// Parses Codex `config.toml` snippets and detects CC Switch proxy takeover.
class CodexTomlParser {
  const CodexTomlParser._();

  static const proxyManagedToken = 'PROXY_MANAGED';

  static CodexTomlParts parse(String toml) {
    final model = RegExp(
      r'^\s*model\s*=\s*"([^"]+)"',
      multiLine: true,
    ).firstMatch(toml)?.group(1) ?? '';
    final baseUrl = RegExp(
      r'^\s*base_url\s*=\s*"([^"]+)"',
      multiLine: true,
    ).firstMatch(toml)?.group(1) ?? '';
    return CodexTomlParts(model: model, baseUrl: baseUrl);
  }

  static bool detectProxyTakeover({
    required String liveToml,
    required Map<String, Object?> liveAuth,
  }) {
    final apiKey = liveAuth['OPENAI_API_KEY']?.toString() ?? '';
    if (apiKey == proxyManagedToken) return true;
    if (liveToml.contains('experimental_bearer_token = "$proxyManagedToken"')) {
      return true;
    }
    final baseUrl = parse(liveToml).baseUrl.toLowerCase();
    if (baseUrl.isEmpty) return false;
    return baseUrl.contains('127.0.0.1') ||
        baseUrl.contains('localhost') ||
        baseUrl.contains(':15721');
  }
}

class CodexTomlParts {
  const CodexTomlParts({required this.model, required this.baseUrl});

  final String model;
  final String baseUrl;
}
