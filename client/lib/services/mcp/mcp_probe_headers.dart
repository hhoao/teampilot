import 'smithery_mcp_auth.dart';

enum McpProbeAuthDecision { proceed, needsAuth }

class McpProbeHeaderInput {
  const McpProbeHeaderInput({
    required this.spec,
    this.oauthApplicable = false,
    this.oauthAccessToken,
    this.smitheryApiToken,
    this.readEnv,
  });

  final Map<String, Object?> spec;
  final bool oauthApplicable;
  final String? oauthAccessToken;
  final String? smitheryApiToken;
  final String? Function(String name)? readEnv;
}

McpProbeAuthDecision mcpProbeAuthDecision(McpProbeHeaderInput input) {
  if (!input.oauthApplicable) return McpProbeAuthDecision.proceed;
  if ((input.oauthAccessToken ?? '').trim().isNotEmpty) {
    return McpProbeAuthDecision.proceed;
  }
  final authorization =
      buildMcpProbeHeaders(
        input,
      )[SmitheryMcpAuth.authorizationHeader]?.trim() ??
      '';
  if (authorization.isNotEmpty) return McpProbeAuthDecision.proceed;
  return McpProbeAuthDecision.needsAuth;
}

Map<String, String> buildMcpProbeHeaders(McpProbeHeaderInput input) {
  final spec = Map<String, Object?>.from(input.spec);
  final withSmithery = SmitheryMcpAuth.applyCatalogBearer(
    spec,
    input.smitheryApiToken,
  );
  final headers = <String, String>{};
  final raw = withSmithery['headers'];
  if (raw is Map) {
    for (final entry in raw.entries) {
      final value = entry.value.toString();
      if (value.isNotEmpty) headers[entry.key.toString()] = value;
    }
  }
  final oauth = input.oauthAccessToken?.trim() ?? '';
  if (oauth.isNotEmpty) {
    headers[SmitheryMcpAuth.authorizationHeader] = 'Bearer $oauth';
  }
  final envName = spec['bearer_token_env_var']?.toString().trim() ?? '';
  if (envName.isNotEmpty &&
      !headers.containsKey(SmitheryMcpAuth.authorizationHeader)) {
    final envVal = input.readEnv?.call(envName)?.trim() ?? '';
    if (envVal.isNotEmpty) {
      headers[SmitheryMcpAuth.authorizationHeader] = 'Bearer $envVal';
    }
  }
  return headers;
}
