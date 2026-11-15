@Tags(['integration'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/credential_lease_endpoint.dart';
import 'package:teampilot/services/provider/oauth_credential_authority.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  test('three concurrent seats share one refresh and all receive a lease',
      () async {
    final fs = InMemoryFilesystem();
    final refresher = _CountingRefresher();
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: refresher,
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    await authority.importFromLogin(
      'xai',
      utf8.encode(jsonEncode({
        'scope': {
          'key': 'old',
          'refresh_token': 'rt-old',
          'expires_at': '2026-11-14T10:00:00Z',
        }
      })),
    );
    final endpoint = CredentialLeaseEndpoint(
      authority: authority,
      sessionProviderId: (_) => 'xai',
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );

    final responses = await Future.wait([
      for (final id in ['s1', 's2', 's3'])
        endpoint.serve(
          sessionId: id,
          busToken: 'bus-$id',
          providerId: 'xai',
          forceRefresh: false,
        ),
    ]);

    expect(responses.map((r) => r.statusCode), [200, 200, 200]);
    expect(responses.map((r) => r.body['access_token']).toSet(), {'fresh'});
    // Single-flight holds at the endpoint layer: three concurrent seats
    // trigger exactly one IdP refresh, so nobody can race a rotation into
    // `invalid_grant`.
    expect(refresher.calls, 1);
    expect(
      jsonEncode([for (final r in responses) r.body]),
      isNot(contains('refresh_token')),
    );
  });
}

final class _CountingRefresher implements CredentialRefresher {
  int calls = 0;

  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return RefreshSucceeded(
      accessToken: 'fresh',
      refreshToken: 'rt-fresh',
      expiresAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
    );
  }
}
