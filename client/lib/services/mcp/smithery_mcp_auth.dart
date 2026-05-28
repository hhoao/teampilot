/// Applies Smithery catalog [Authorization: Bearer] for MCP gateway URLs only.
///
/// Smithery **catalog** API keys (`api.smithery.ai`) are not MCP runtime OAuth
/// tokens. Deployed hosts such as `*.run.tools` require the user to complete
/// Claude Code's `/mcp` → Authenticate flow (OAuth tokens in secure storage).
class SmitheryMcpAuth {
  static const authorizationHeader = 'Authorization';

  /// Smithery MCP gateway proxy (`server.smithery.ai/@…`), not deployment hosts.
  static bool urlNeedsSmitheryCatalogBearer(String url) {
    final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
    if (host.isEmpty) return false;
    if (host == 'server.smithery.ai') return true;
    return host.endsWith('.smithery.ai') && host != 'api.smithery.ai';
  }

  static bool isRemoteHttpType(String? type) {
    final t = type?.trim().toLowerCase() ?? '';
    return t == 'http' || t == 'sse' || t == 'streamable-http';
  }

  static bool shouldApplyCatalogBearer(Map<String, Object?> spec) {
    if (!isRemoteHttpType(spec['type']?.toString())) return false;
    return urlNeedsSmitheryCatalogBearer(spec['url']?.toString() ?? '');
  }

  static Map<String, Object?> applyCatalogBearer(
    Map<String, Object?> spec,
    String? apiToken,
  ) {
    final token = apiToken?.trim() ?? '';
    if (token.isEmpty) return spec;
    if (!shouldApplyCatalogBearer(spec)) return spec;

    final out = Map<String, Object?>.from(spec);
    final rawHeaders = out['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        headers[entry.key.toString()] = entry.value.toString();
      }
    }
    headers[authorizationHeader] = 'Bearer $token';
    out['headers'] = headers;
    return out;
  }

  static Map<String, Map<String, Object?>> applyToCatalogServers(
    Map<String, Map<String, Object?>> servers,
    String? apiToken,
  ) {
    if (apiToken == null || apiToken.trim().isEmpty) return servers;
    return {
      for (final entry in servers.entries)
        entry.key: applyCatalogBearer(
          Map<String, Object?>.from(entry.value),
          apiToken,
        ).cast<String, Object?>(),
    };
  }
}
