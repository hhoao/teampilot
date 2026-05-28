import 'dart:convert';

import 'package:http/http.dart' as http;

/// MCP OAuth discovery (RFC 9728 + RFC 8414), aligned with `@modelcontextprotocol/sdk`.
class McpOAuthDiscovery {
  McpOAuthDiscovery({http.Client? client}) : _client = client ?? http.Client();

  static const mcpProtocolVersion = '2025-11-25';

  final http.Client _client;

  Future<McpOAuthServerInfo> discoverServerInfo(
    String serverUrl, {
    Uri? resourceMetadataUrl,
  }) async {
    Map<String, Object?>? resourceMetadata;
    String? authorizationServerUrl;

    try {
      resourceMetadata = await discoverProtectedResourceMetadata(
        serverUrl,
        resourceMetadataUrl: resourceMetadataUrl,
      );
      final servers = resourceMetadata['authorization_servers'];
      if (servers is List && servers.isNotEmpty) {
        authorizationServerUrl = servers.first.toString();
      }
    } catch (_) {
      // RFC 9728 not supported — fall back below.
    }

    authorizationServerUrl ??= Uri.parse(serverUrl).replace(
      path: '/',
      query: '',
      fragment: '',
    ).toString();

    final metadata = await discoverAuthorizationServerMetadata(
      authorizationServerUrl,
    );
    if (metadata == null) {
      throw McpOAuthException(
        'Could not load OAuth authorization server metadata for $authorizationServerUrl',
      );
    }

    return McpOAuthServerInfo(
      authorizationServerUrl: authorizationServerUrl,
      authorizationServerMetadata: metadata,
      resourceMetadata: resourceMetadata,
    );
  }

  Future<Map<String, Object?>> discoverProtectedResourceMetadata(
    String serverUrl, {
    Uri? resourceMetadataUrl,
  }) async {
    final issuer = Uri.parse(serverUrl);
    final url = resourceMetadataUrl ??
        _wellKnownUrl(
          issuer,
          'oauth-protected-resource',
          prependPath: true,
        );
    final response = await _fetchMetadata(url);
    if (response.statusCode == 404) {
      throw McpOAuthException('Protected resource metadata not found');
    }
    if (response.statusCode != 200) {
      throw McpOAuthException(
        'HTTP ${response.statusCode} loading protected resource metadata',
      );
    }
    return jsonDecode(response.body) as Map<String, Object?>;
  }

  Future<Map<String, Object?>?> discoverAuthorizationServerMetadata(
    String authorizationServerUrl,
  ) async {
    for (final candidate in _authorizationDiscoveryUrls(authorizationServerUrl)) {
      final response = await _fetchMetadata(candidate.url);
      if (response.statusCode >= 400 && response.statusCode < 500) {
        continue;
      }
      if (response.statusCode != 200) {
        throw McpOAuthException(
          'HTTP ${response.statusCode} loading ${candidate.label} metadata',
        );
      }
      return jsonDecode(response.body) as Map<String, Object?>;
    }
    return null;
  }

  Future<http.Response> _fetchMetadata(Uri url) async {
    return _client.get(
      url,
      headers: {
        'Accept': 'application/json',
        'MCP-Protocol-Version': mcpProtocolVersion,
      },
    );
  }

  Uri _wellKnownUrl(Uri issuer, String wellKnownType, {required bool prependPath}) {
    var pathname = issuer.path;
    if (pathname.endsWith('/')) {
      pathname = pathname.substring(0, pathname.length - 1);
    }
    final path = prependPath
        ? '$pathname/.well-known/$wellKnownType'
        : '/.well-known/$wellKnownType$pathname';
    return issuer.replace(path: path, query: issuer.query, fragment: '');
  }

  List<_DiscoveryCandidate> _authorizationDiscoveryUrls(String authorizationServerUrl) {
    final url = Uri.parse(authorizationServerUrl);
    final hasPath = url.path != '/' && url.path.isNotEmpty;
    if (!hasPath) {
      return [
        _DiscoveryCandidate(
          Uri.parse('${url.origin}/.well-known/oauth-authorization-server'),
          'oauth',
        ),
        _DiscoveryCandidate(
          Uri.parse('${url.origin}/.well-known/openid-configuration'),
          'oidc',
        ),
      ];
    }
    var pathname = url.path;
    if (pathname.endsWith('/')) {
      pathname = pathname.substring(0, pathname.length - 1);
    }
    return [
      _DiscoveryCandidate(
        Uri.parse(
          '${url.origin}/.well-known/oauth-authorization-server$pathname',
        ),
        'oauth',
      ),
      _DiscoveryCandidate(
        Uri.parse('${url.origin}/.well-known/openid-configuration$pathname'),
        'oidc',
      ),
      _DiscoveryCandidate(
        Uri.parse('${url.origin}$pathname/.well-known/openid-configuration'),
        'oidc-path',
      ),
    ];
  }
}

class McpOAuthServerInfo {
  const McpOAuthServerInfo({
    required this.authorizationServerUrl,
    required this.authorizationServerMetadata,
    this.resourceMetadata,
  });

  final String authorizationServerUrl;
  final Map<String, Object?> authorizationServerMetadata;
  final Map<String, Object?>? resourceMetadata;
}

class _DiscoveryCandidate {
  const _DiscoveryCandidate(this.url, this.label);
  final Uri url;
  final String label;
}

class McpOAuthException implements Exception {
  McpOAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// User dismissed the connect dialog or closed the local callback listener.
class McpOAuthCancelledException implements Exception {
  const McpOAuthCancelledException();
  @override
  String toString() => 'Authentication cancelled';
}

Uri? selectMcpResourceUrl(
  String serverUrl,
  Map<String, Object?>? resourceMetadata,
) {
  if (resourceMetadata == null) return null;
  final resource = resourceMetadata['resource']?.toString();
  if (resource == null || resource.isEmpty) return null;
  final configured = Uri.parse(resource);
  final requested = Uri.parse(serverUrl).replace(fragment: '');
  if (requested.origin != configured.origin) {
    throw McpOAuthException(
      'Protected resource $resource does not match MCP server URL',
    );
  }
  return configured;
}
