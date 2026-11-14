import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/credential_lease.dart';
import 'package:teampilot/services/provider/oauth_credential_authority.dart';

import '../../support/in_memory_filesystem.dart';

final class _FakeRefresher implements CredentialRefresher {
  _FakeRefresher({this.outcome, this.delay = Duration.zero});

  CredentialRefreshOutcome? outcome;
  Duration delay;
  int calls = 0;

  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async {
    calls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return outcome ??
        RefreshSucceeded(
          accessToken: 'fresh-$calls',
          refreshToken: 'rt-$calls',
          expiresAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
        );
  }
}

String _authJson({
  String key = 'access-old',
  String refreshToken = 'rt-old',
  String expiresAt = '2026-11-14T11:30:00Z',
}) =>
    jsonEncode({
      'https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828': {
        'key': key,
        'refresh_token': refreshToken,
        'expires_at': expiresAt,
        'auth_mode': 'Oidc',
      },
    });

void main() {
  final now = DateTime.utc(2026, 11, 14, 11, 0, 0);

  OAuthCredentialAuthority build(
    InMemoryFilesystem fs,
    _FakeRefresher refresher,
  ) =>
      OAuthCredentialAuthority(
        fs: fs,
        basePath: '/tp',
        cliNamespace: 'grok',
        refresher: refresher,
        now: () => now,
      );

  test('importFromLogin parses grok auth.json and persists RT on control plane',
      () async {
    final fs = InMemoryFilesystem();
    final authority = build(fs, _FakeRefresher());

    final ok = await authority.importFromLogin(
      'xai',
      utf8.encode(_authJson()),
    );

    expect(ok, isTrue);
    final raw = await fs.readString('/tp/providers/grok/xai/credential.json');
    expect(raw, isNotNull);
    expect(raw, contains('rt-old'));
    expect(await authority.status('xai'), CredentialHealth.ready);
  });

  test('importFromLogin rejects an empty / malformed credential', () async {
    final fs = InMemoryFilesystem();
    final authority = build(fs, _FakeRefresher());

    expect(await authority.importFromLogin('xai', utf8.encode('{}')), isFalse);
    expect(await authority.importFromLogin('xai', utf8.encode('not json')),
        isFalse);
    expect(await authority.status('xai'), CredentialHealth.missing);
    expect(await fs.readString('/tp/providers/grok/xai/credential.json'),
        isNull);
  });

  test('concurrent leases share a single refresh (single-flight)', () async {
    final fs = InMemoryFilesystem();
    final refresher = _FakeRefresher(
      delay: const Duration(milliseconds: 20),
    );
    final authority = build(fs, refresher);
    await authority.importFromLogin(
      'xai',
      utf8.encode(_authJson(expiresAt: '2026-11-14T10:00:00Z')),
    );

    final results = await Future.wait([
      authority.lease(providerId: 'xai', sessionId: 's1'),
      authority.lease(providerId: 'xai', sessionId: 's2'),
      authority.lease(providerId: 'xai', sessionId: 's3'),
    ]);

    expect(refresher.calls, 1);
    expect(results.map((e) => e.accessToken).toSet(), {'fresh-1'});
    expect(results.map((e) => e.epoch).toSet(), {1});
  });

  test('invalid_grant marks rejected, deletes RT, never writes an empty store',
      () async {
    final fs = InMemoryFilesystem();
    final refresher = _FakeRefresher(outcome: RefreshRejected());
    final authority = build(fs, refresher);
    await authority.importFromLogin(
      'xai',
      utf8.encode(_authJson(expiresAt: '2026-11-14T10:00:00Z')),
    );

    await expectLater(
      authority.lease(providerId: 'xai', sessionId: 's1'),
      throwsA(
        isA<CredentialUnavailableException>().having(
          (e) => e.health,
          'health',
          CredentialHealth.rejected,
        ),
      ),
    );

    expect(await authority.status('xai'), CredentialHealth.rejected);
    expect(await fs.readString('/tp/providers/grok/xai/credential.json'),
        isNull);
    expect(authority.healthChanges.value['xai'], CredentialHealth.rejected);
  });

  test('forceRefresh mints a new lease and bumps epoch', () async {
    final fs = InMemoryFilesystem();
    final authority = build(fs, _FakeRefresher());
    await authority.importFromLogin('xai', utf8.encode(_authJson()));

    final first = await authority.lease(providerId: 'xai', sessionId: 's1');
    final forced = await authority.lease(
      providerId: 'xai',
      sessionId: 's1',
      forceRefresh: true,
    );

    expect(first.epoch, 0);
    expect(forced.epoch, 1);
    expect(forced.accessToken, 'fresh-1');
  });

  test('importLegacyAuthJson migrates once then deletes the old file',
      () async {
    final fs = InMemoryFilesystem();
    await fs.ensureDir('/tp/providers/grok/xai');
    await fs.atomicWrite('/tp/providers/grok/xai/auth.json', _authJson());
    final authority = build(fs, _FakeRefresher());

    expect(await authority.importLegacyAuthJson('xai'), isTrue);
    expect(await authority.status('xai'), CredentialHealth.ready);
    expect(await fs.readString('/tp/providers/grok/xai/auth.json'), isNull);

    expect(await authority.importLegacyAuthJson('xai'), isFalse);
  });

  test('revoke removes the credential and clears rejected state', () async {
    final fs = InMemoryFilesystem();
    final authority = build(fs, _FakeRefresher());
    await authority.importFromLogin('xai', utf8.encode(_authJson()));

    await authority.revoke('xai');

    expect(await authority.status('xai'), CredentialHealth.missing);
    expect(await fs.readString('/tp/providers/grok/xai/credential.json'),
        isNull);
  });

  test('expired access token with a live RT reports expiring, not missing',
      () async {
    final fs = InMemoryFilesystem();
    final authority = build(fs, _FakeRefresher());
    await authority.importFromLogin(
      'xai',
      utf8.encode(_authJson(expiresAt: '2026-11-14T10:00:00Z')),
    );

    expect(await authority.status('xai'), CredentialHealth.expiring);
  });
}
