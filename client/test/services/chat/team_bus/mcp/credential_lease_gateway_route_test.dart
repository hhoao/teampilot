import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/chat/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import 'package:teampilot/services/provider/credential_lease_endpoint.dart';
import 'package:teampilot/services/provider/oauth_credential_authority.dart';

import '../../../../support/in_memory_filesystem.dart';

final class _OkRefresher implements CredentialRefresher {
  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async =>
      RefreshSucceeded(
        accessToken: 'fresh',
        refreshToken: 'rt-fresh',
        expiresAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
      );
}

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  final now = DateTime.utc(2026, 11, 14, 11, 0, 0);

  late TeammateBusMcpGateway gateway;
  late HttpClient client;

  setUp(() async {
    final authority = OAuthCredentialAuthority(
      fs: InMemoryFilesystem(),
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _OkRefresher(),
      now: () => now,
    );
    await authority.importFromLogin(
      'xai',
      utf8.encode(jsonEncode({
        'scope': {
          'key': 'access-old',
          'refresh_token': 'rt-old',
          'expires_at': '2026-11-14T11:30:00Z',
        }
      })),
    );
    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    gateway.attachCredentialLeaseEndpoint(
      CredentialLeaseEndpoint(
        authority: authority,
        sessionProviderId: (_) => 'xai',
        now: () => now,
      ),
    );
    gateway.registerAgentStatusSession(sessionId: 'sess-a');
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await gateway.dispose();
  });

  Future<HttpClientResponse> postLease({
    required String sessionId,
    String? busToken,
  }) async {
    final req = await client.postUrl(
      Uri.parse(
        'http://127.0.0.1:${gateway.httpPort}${CredentialLeaseEndpoint.path}',
      ),
    );
    req.headers.set(teammateBusMcpSessionHeader, sessionId);
    if (busToken != null) {
      req.headers.set(teammateBusTokenHeader, busToken);
    }
    req.write(jsonEncode({'providerId': 'xai', 'forceRefresh': false}));
    return req.close();
  }

  test('local seat without a bus token → 200', () async {
    final resp = await postLease(sessionId: 'sess-a');

    expect(resp.statusCode, HttpStatus.ok);
    final body =
        jsonDecode(await resp.transform(utf8.decoder).join())
            as Map<String, Object?>;
    expect(body['access_token'], 'access-old');
  });

  test('local seat echoing its own session id as token → 200', () async {
    final resp = await postLease(sessionId: 'sess-a', busToken: 'sess-a');

    expect(resp.statusCode, HttpStatus.ok);
    final body =
        jsonDecode(await resp.transform(utf8.decoder).join())
            as Map<String, Object?>;
    expect(body['access_token'], 'access-old');
  });

  test('independent token for another session → 401', () async {
    final otherToken = gateway.registerAgentStatusSession(sessionId: 'sess-b');

    final resp = await postLease(sessionId: 'sess-a', busToken: otherToken);

    expect(resp.statusCode, HttpStatus.unauthorized);
    await resp.drain<void>();
  });

  test('unregistered standalone token → 401', () async {
    final resp = await postLease(sessionId: 'sess-a', busToken: 'not-a-token');

    expect(resp.statusCode, HttpStatus.unauthorized);
    await resp.drain<void>();
  });
}
