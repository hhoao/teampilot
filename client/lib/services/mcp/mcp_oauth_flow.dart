import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../storage/app_storage.dart';
import '../cli/cli_data_layout.dart';
import 'mcp_credentials_store.dart';
import 'mcp_oauth_callback_server.dart';
import 'mcp_oauth_discovery.dart';
import 'mcp_oauth_pkce.dart';
import 'mcp_oauth_server_key.dart';

/// Claude Code MCP OAuth (PKCE + `.credentials.json`), without a local Node runtime.
class McpOAuthFlow {
  McpOAuthFlow({
    McpOAuthDiscovery? discovery,
    McpCredentialsStore? credentialsStore,
    http.Client? httpClient,
  }) : _discovery = discovery ?? McpOAuthDiscovery(),
       _credentials = credentialsStore ?? McpCredentialsStore(),
       _http = httpClient ?? http.Client();

  /// CIMD client id (SEP-991), same as Claude Code.
  static const clientMetadataUrl =
      'https://claude.ai/oauth/claude-code-client-metadata';

  final McpOAuthDiscovery _discovery;
  final McpCredentialsStore _credentials;
  final http.Client _http;

  static String claudeAppConfigDir() {
    return CliDataLayout(teampilotRoot: AppStorage.appDataRoot).appToolRoot(
      'claude',
    );
  }

  Future<McpOAuthFlowResult> authenticate({
    required String configDir,
    required String serverName,
    required Map<String, Object?> serverConfig,
    required void Function(Uri authorizationUrl) onAuthorizationUrl,
    bool useLocalCallback = true,
    Future<Uri> Function()? waitForManualCallback,
    McpOAuthCallbackServer? callbackServer,
    int callbackPort = 3118,
  }) async {
    final url = serverConfig['url']?.toString().trim() ?? '';
    if (url.isEmpty) {
      throw McpOAuthException('MCP server URL is required for OAuth');
    }

    await _credentials.clearServerTokens(
      configDir: configDir,
      serverName: serverName,
      serverConfig: serverConfig,
    );

    final serverInfo = await _discovery.discoverServerInfo(url);
    final metadata = serverInfo.authorizationServerMetadata;
    final resource = selectMcpResourceUrl(url, serverInfo.resourceMetadata);

    final scope = _resolveScope(serverInfo.resourceMetadata, metadata);
    final redirectUri = Uri.parse('http://localhost:$callbackPort/callback');
    final client = await _ensureClient(
      configDir: configDir,
      serverName: serverName,
      serverConfig: serverConfig,
      serverInfo: serverInfo,
      scope: scope,
      redirectUri: redirectUri,
    );
    final state = McpOAuthPkce.generateState();
    final codeVerifier = McpOAuthPkce.generateCodeVerifier();
    final authorizationUrl = _buildAuthorizationUrl(
      metadata: metadata,
      clientId: client.clientId,
      redirectUri: redirectUri,
      state: state,
      codeVerifier: codeVerifier,
      scope: scope,
      resource: resource,
    );

    final Uri callbackUri;
    if (useLocalCallback && !Platform.isAndroid) {
      final ownsServer = callbackServer == null;
      final server = callbackServer ?? McpOAuthCallbackServer(port: callbackPort);
      try {
        final localFuture = server.listen(expectedState: state);
        onAuthorizationUrl(authorizationUrl);
        if (waitForManualCallback != null) {
          callbackUri = await Future.any([
            localFuture,
            waitForManualCallback(),
          ]);
        } else {
          callbackUri = await localFuture;
        }
      } finally {
        if (ownsServer) {
          await server.close();
        }
      }
    } else {
      onAuthorizationUrl(authorizationUrl);
      if (waitForManualCallback == null) {
        throw McpOAuthException(
          'Local callback is unavailable; paste the redirect URL instead.',
        );
      }
      callbackUri = await waitForManualCallback();
    }
    _validateCallback(callbackUri, state);

    final code = callbackUri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw McpOAuthException('Missing authorization code in callback URL');
    }

    final tokens = await _exchangeAuthorizationCode(
      serverInfo: serverInfo,
      client: client,
      code: code,
      codeVerifier: codeVerifier,
      redirectUri: redirectUri,
      resource: resource,
    );

    final expiresIn = tokens['expires_in'];
    final expiresAtMs = DateTime.now().millisecondsSinceEpoch +
        ((expiresIn is num ? expiresIn.toInt() : 3600) * 1000);

    await _credentials.saveOAuthTokens(
      configDir: configDir,
      serverName: serverName,
      serverConfig: serverConfig,
      accessToken: tokens['access_token']!.toString(),
      refreshToken: tokens['refresh_token']?.toString(),
      expiresAtMs: expiresAtMs,
      scope: tokens['scope']?.toString(),
      clientId: client.clientId,
      clientSecret: client.clientSecret,
      discoveryState: {
        'authorizationServerUrl': serverInfo.authorizationServerUrl,
        if (serverInfo.resourceMetadata != null)
          'resourceMetadata': serverInfo.resourceMetadata,
        'authorizationServerMetadata': metadata,
      },
    );

    return McpOAuthFlowResult(
      serverKey: mcpOAuthServerKey(serverName, serverConfig),
      configDir: configDir,
    );
  }

  void _validateCallback(Uri callbackUri, String expectedState) {
    final error = callbackUri.queryParameters['error'];
    if (error != null) {
      final description = callbackUri.queryParameters['error_description'] ?? '';
      throw McpOAuthException('OAuth error: $error $description');
    }
    final state = callbackUri.queryParameters['state'];
    if (state != expectedState) {
      throw McpOAuthException('OAuth state mismatch');
    }
  }

  String? _resolveScope(
    Map<String, Object?>? resourceMetadata,
    Map<String, Object?> metadata,
  ) {
    final fromResource = resourceMetadata?['scopes_supported'];
    if (fromResource is List && fromResource.isNotEmpty) {
      return fromResource.map((e) => e.toString()).join(' ');
    }
    final fromMetadata = metadata['scopes_supported'];
    if (fromMetadata is List && fromMetadata.isNotEmpty) {
      return fromMetadata.map((e) => e.toString()).join(' ');
    }
    return null;
  }

  Future<_OAuthClient> _ensureClient({
    required String configDir,
    required String serverName,
    required Map<String, Object?> serverConfig,
    required McpOAuthServerInfo serverInfo,
    required String? scope,
    required Uri redirectUri,
  }) async {
    final data = await _credentials.read(configDir);
    final key = mcpOAuthServerKey(serverName, serverConfig);
    final existing = _credentials.oauthEntry(data, key);
    final existingId = existing?['clientId']?.toString();
    if (existingId != null && existingId.isNotEmpty) {
      return _OAuthClient(
        clientId: existingId,
        clientSecret: existing?['clientSecret']?.toString(),
      );
    }

    final metadata = serverInfo.authorizationServerMetadata;
    if (metadata['client_id_metadata_document_supported'] == true) {
      const clientId = clientMetadataUrl;
      await _credentials.saveClientInformation(
        configDir: configDir,
        serverName: serverName,
        serverConfig: serverConfig,
        clientId: clientId,
      );
      return const _OAuthClient(clientId: clientId);
    }

    final registrationEndpoint = metadata['registration_endpoint']?.toString();
    if (registrationEndpoint == null || registrationEndpoint.isEmpty) {
      throw McpOAuthException(
        'Authorization server does not support dynamic client registration',
      );
    }

    final body = <String, Object?>{
      'client_name': 'TeamPilot ($serverName)',
      'redirect_uris': [redirectUri.toString()],
      'grant_types': ['authorization_code', 'refresh_token'],
      'response_types': ['code'],
      'token_endpoint_auth_method': 'none',
      if (scope != null) 'scope': scope,
    };

    final response = await _http.post(
      Uri.parse(registrationEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw McpOAuthException(
        'Client registration failed: HTTP ${response.statusCode} ${response.body}',
      );
    }
    final registered = jsonDecode(response.body) as Map<String, Object?>;
    final clientId = registered['client_id']?.toString() ?? '';
    if (clientId.isEmpty) {
      throw McpOAuthException('Client registration returned no client_id');
    }
    final clientSecret = registered['client_secret']?.toString();
    await _credentials.saveClientInformation(
      configDir: configDir,
      serverName: serverName,
      serverConfig: serverConfig,
      clientId: clientId,
      clientSecret: clientSecret,
    );
    return _OAuthClient(clientId: clientId, clientSecret: clientSecret);
  }

  Uri _buildAuthorizationUrl({
    required Map<String, Object?> metadata,
    required String clientId,
    required Uri redirectUri,
    required String state,
    required String codeVerifier,
    required String? scope,
    required Uri? resource,
  }) {
    final endpoint = metadata['authorization_endpoint']?.toString();
    if (endpoint == null || endpoint.isEmpty) {
      throw McpOAuthException('Missing authorization_endpoint in metadata');
    }
    final challenge = McpOAuthPkce.codeChallengeS256(codeVerifier);
    final base = Uri.parse(endpoint);
    return base.replace(
      queryParameters: {
        ...base.queryParameters,
        'response_type': 'code',
        'client_id': clientId,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'redirect_uri': redirectUri.toString(),
        'state': state,
        if (scope != null && scope.isNotEmpty) 'scope': scope,
        if (resource != null) 'resource': resource.toString(),
      },
    );
  }

  Future<Map<String, Object?>> _exchangeAuthorizationCode({
    required McpOAuthServerInfo serverInfo,
    required _OAuthClient client,
    required String code,
    required String codeVerifier,
    required Uri redirectUri,
    required Uri? resource,
  }) async {
    final metadata = serverInfo.authorizationServerMetadata;
    final tokenEndpoint = metadata['token_endpoint']?.toString();
    if (tokenEndpoint == null || tokenEndpoint.isEmpty) {
      throw McpOAuthException('Missing token_endpoint in metadata');
    }

    final params = {
      'grant_type': 'authorization_code',
      'code': code,
      'code_verifier': codeVerifier,
      'redirect_uri': redirectUri.toString(),
      'client_id': client.clientId,
      if (resource != null) 'resource': resource.toString(),
    };

    final response = await _http.post(
      Uri.parse(tokenEndpoint),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&'),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw McpOAuthException(
        'Token exchange failed: HTTP ${response.statusCode} ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, Object?>;
  }
}

class McpOAuthFlowResult {
  const McpOAuthFlowResult({
    required this.serverKey,
    required this.configDir,
  });

  final String serverKey;
  final String configDir;
}

class _OAuthClient {
  const _OAuthClient({required this.clientId, this.clientSecret});
  final String clientId;
  final String? clientSecret;
}
