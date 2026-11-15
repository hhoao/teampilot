import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/credential_lease_endpoint.dart';
import 'package:teampilot/services/provider/oauth_credential_authority.dart';

import '../../support/in_memory_filesystem.dart';

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
  final now = DateTime.utc(2026, 11, 14, 11, 0, 0);

  Future<CredentialLeaseEndpoint> build() async {
    final fs = InMemoryFilesystem();
    final authority = OAuthCredentialAuthority(
      fs: fs,
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
    return CredentialLeaseEndpoint(
      authority: authority,
      sessionProviderId: (sessionId) => 'xai',
      now: () => now,
    );
  }

  test('serves a lease with access_token and expires_in, never a refresh token',
      () async {
    final endpoint = await build();
    final response = await endpoint.serve(
      sessionId: 's1',
      busToken: 'bus-token',
      providerId: 'xai',
      forceRefresh: false,
    );

    expect(response.statusCode, 200);
    expect(response.body['access_token'], 'access-old');
    expect(response.body['expires_in'], 1800);
    expect(jsonEncode(response.body), isNot(contains('refresh_token')));
  });

  test('rejects a missing session or bus token', () async {
    final endpoint = await build();
    expect(
      (await endpoint.serve(
        sessionId: '',
        busToken: null,
        providerId: 'xai',
        forceRefresh: false,
      )).statusCode,
      401,
    );
  });

  test('rejects a providerId that does not belong to the session', () async {
    final endpoint = await build();
    expect(
      (await endpoint.serve(
        sessionId: 's1',
        busToken: 'bus-token',
        providerId: 'other',
        forceRefresh: false,
      )).statusCode,
      401,
    );
  });

  test('forceRefresh returns 409 with rejected health when RT is refused',
      () async {
    final fs = InMemoryFilesystem();
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _RejectRefresher(),
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
    final endpoint = CredentialLeaseEndpoint(
      authority: authority,
      sessionProviderId: (_) => 'xai',
      now: () => now,
    );

    final response = await endpoint.serve(
      sessionId: 's1',
      busToken: 'bus-token',
      providerId: 'xai',
      forceRefresh: true,
    );
    expect(response.statusCode, 409);
    expect(response.body['health'], 'rejected');
  });
}

final class _RejectRefresher implements CredentialRefresher {
  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async =>
      const RefreshRejected();
}
