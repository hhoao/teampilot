import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/credential_lease.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
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

/// Refresh call that stays in flight until the test completes it, so
/// interleavings (re-login, revoke, a newer refresh) are deterministic.
final class _ControlledRefresher implements CredentialRefresher {
  final List<Completer<CredentialRefreshOutcome>> pending = [];
  final List<String> refreshTokens = [];

  int get calls => pending.length;

  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) {
    refreshTokens.add(refreshToken);
    final completer = Completer<CredentialRefreshOutcome>();
    pending.add(completer);
    return completer.future;
  }
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

final class _ThrowingRefresher implements CredentialRefresher {
  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async =>
      throw const CredentialTransientException('503');
}

/// Pauses the next `credential.json` atomicWrite so a test can deterministically
/// interleave a concurrent import with a refresh commit's check-then-write.
final class _GatedCredentialFilesystem extends InMemoryFilesystem {
  Completer<void>? _gate;
  Completer<void>? _entered;
  Completer<void>? _pending;

  void armWriteGate() {
    _gate = Completer<void>();
    _pending = _gate;
    _entered = Completer<void>();
  }

  Future<void> get writeEntered => _entered!.future;

  void releaseWrite() => _pending?.complete();

  @override
  Future<void> atomicWrite(String path, String content) async {
    final gate = _gate;
    if (gate != null && path.endsWith('credential.json')) {
      _gate = null; // gate exactly one write
      _entered?.complete();
      await gate.future;
    }
    return super.atomicWrite(path, content);
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
    CredentialRefresher refresher,
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

  test('a transient refresh failure keeps the refresh token', () async {
    final fs = InMemoryFilesystem();
    final authority = build(fs, _ThrowingRefresher());
    await authority.importFromLogin(
      'xai',
      utf8.encode(_authJson(expiresAt: '2026-11-14T10:00:00Z')),
    );

    await expectLater(
      authority.lease(providerId: 'xai', sessionId: 's1'),
      throwsA(isA<CredentialTransientException>()),
    );

    // An IdP outage is not a sign-in: the RT and its health must survive.
    expect(await authority.status('xai'), CredentialHealth.expiring);
    final raw = await fs.readString('/tp/providers/grok/xai/credential.json');
    expect(raw, contains('rt-old'));
  });

  test(
    'credential.json is stored owner-only on a real filesystem',
    () async {
      final dir = await Directory.systemTemp.createTemp('tp-authority-');
      addTearDown(() => dir.delete(recursive: true));
      final authority = OAuthCredentialAuthority(
        fs: LocalFilesystem(),
        basePath: dir.path,
        cliNamespace: 'grok',
        refresher: _FakeRefresher(),
        now: () => now,
      );

      await authority.importFromLogin('xai', utf8.encode(_authJson()));

      final path = '${dir.path}/providers/grok/xai/credential.json';
      // Low 9 bits are the POSIX permission mask; 0x180 == 0600.
      expect(File(path).statSync().mode & 0x1FF, 0x180);
    },
    skip: Platform.isWindows,
  );

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

  test('re-login during an in-flight refresh is not clobbered', () async {
    final fs = InMemoryFilesystem();
    final refresher = _ControlledRefresher();
    final authority = build(fs, refresher);
    await authority.importFromLogin(
      'xai',
      utf8.encode(_authJson(expiresAt: '2026-11-14T10:00:00Z')),
    );

    final staleLease = authority.lease(providerId: 'xai', sessionId: 's1');
    await _pump();
    expect(refresher.pending, hasLength(1));

    expect(
      await authority.importFromLogin(
        'xai',
        utf8.encode(_authJson(key: 'access-new', refreshToken: 'rt-new')),
      ),
      isTrue,
    );

    refresher.pending.single.complete(
      RefreshSucceeded(
        accessToken: 'stale-access',
        refreshToken: 'rt-stale',
        expiresAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
      ),
    );
    final lease = await staleLease;

    final raw = await fs.readString('/tp/providers/grok/xai/credential.json');
    expect(raw, contains('rt-new'));
    expect(raw, isNot(contains('rt-stale')));
    expect(lease.accessToken, 'access-new');
    expect(lease.epoch, 1);
    expect(await authority.status('xai'), CredentialHealth.ready);
  });

  test('a late refresh cannot resurrect a revoked credential', () async {
    final fs = InMemoryFilesystem();
    final refresher = _ControlledRefresher();
    final authority = build(fs, refresher);
    await authority.importFromLogin(
      'xai',
      utf8.encode(_authJson(expiresAt: '2026-11-14T10:00:00Z')),
    );

    final lease = authority.lease(providerId: 'xai', sessionId: 's1');
    final rejection = expectLater(
      lease,
      throwsA(
        isA<CredentialUnavailableException>().having(
          (e) => e.health,
          'health',
          CredentialHealth.missing,
        ),
      ),
    );
    await _pump();
    expect(refresher.pending, hasLength(1));

    await authority.revoke('xai');
    refresher.pending.single.complete(
      RefreshSucceeded(
        accessToken: 'stale-access',
        refreshToken: 'rt-stale',
        expiresAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
      ),
    );
    await rejection;

    expect(await fs.readString('/tp/providers/grok/xai/credential.json'),
        isNull);
    expect(await authority.status('xai'), CredentialHealth.missing);
  });

  test('a completing refresh only clears its own in-flight entry', () async {
    final fs = InMemoryFilesystem();
    final refresher = _ControlledRefresher();
    final authority = build(fs, refresher);
    await authority.importFromLogin(
      'xai',
      utf8.encode(_authJson(expiresAt: '2026-11-14T10:00:00Z')),
    );

    final first = authority.lease(providerId: 'xai', sessionId: 's1');
    await _pump();
    expect(refresher.pending, hasLength(1));

    await authority.revoke('xai');
    await authority.importFromLogin(
      'xai',
      utf8.encode(_authJson(expiresAt: '2026-11-14T10:00:00Z')),
    );
    final second = authority.lease(providerId: 'xai', sessionId: 's2');
    await _pump();
    expect(refresher.pending, hasLength(2));

    // Refresh #1 finishes while #2 is still the registered single flight.
    refresher.pending[0].complete(
      RefreshSucceeded(
        accessToken: 'stale-1',
        refreshToken: 'rt-1',
        expiresAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
      ),
    );
    await first;
    await _pump();

    final third = authority.lease(providerId: 'xai', sessionId: 's3');
    await _pump();
    expect(
      refresher.pending,
      hasLength(2),
      reason: 'refresh #2 must stay registered as the single flight',
    );

    refresher.pending[1].complete(
      RefreshSucceeded(
        accessToken: 'fresh-2',
        refreshToken: 'rt-2',
        expiresAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
      ),
    );
    expect((await second).accessToken, 'fresh-2');
    expect((await third).accessToken, 'fresh-2');
    expect(refresher.calls, 2);
  });

  test('corrupt credential is recoverable via legacy auth.json migration',
      () async {
    final fs = InMemoryFilesystem();
    await fs.ensureDir('/tp/providers/grok/xai');
    await fs.atomicWrite(
      '/tp/providers/grok/xai/credential.json',
      '{"refresh_token": ',
    );
    await fs.atomicWrite('/tp/providers/grok/xai/auth.json', _authJson());
    final authority = build(fs, _FakeRefresher());

    expect(await authority.status('xai'), CredentialHealth.missing);

    expect(await authority.importLegacyAuthJson('xai'), isTrue);
    expect(await fs.readString('/tp/providers/grok/xai/auth.json'), isNull);
    expect(await authority.status('xai'), CredentialHealth.ready);
    final raw = await fs.readString('/tp/providers/grok/xai/credential.json');
    expect(raw, contains('rt-old'));
  });

  test('a rejected old RT during re-login keeps the new credential', () async {
    final fs = InMemoryFilesystem();
    final refresher = _ControlledRefresher();
    final authority = build(fs, refresher);
    await authority.importFromLogin(
      'xai',
      utf8.encode(_authJson(expiresAt: '2026-11-14T10:00:00Z')),
    );

    final staleLease = authority.lease(providerId: 'xai', sessionId: 's1');
    await _pump();
    expect(refresher.pending, hasLength(1));

    // Re-login while the OLD refresh token's refresh is in flight.
    expect(
      await authority.importFromLogin(
        'xai',
        utf8.encode(_authJson(key: 'access-new', refreshToken: 'rt-new')),
      ),
      isTrue,
    );

    // The old RT is rejected, but it must not delete the freshly imported
    // credential.json (the pre-fix bug).
    refresher.pending.single.complete(const RefreshRejected());
    final lease = await staleLease;

    final raw = await fs.readString('/tp/providers/grok/xai/credential.json');
    expect(raw, contains('rt-new'), reason: 're-login must not be deleted');
    expect(raw, isNot(contains('rt-old')));
    expect(await authority.status('xai'), isNot(CredentialHealth.rejected));
    expect(lease.accessToken, 'access-new');
  });

  test('refresh commit and import are serialized (no stale overwrite)',
      () async {
    final fs = _GatedCredentialFilesystem();
    final refresher = _ControlledRefresher();
    final authority = build(fs, refresher);
    await authority.importFromLogin(
      'xai',
      utf8.encode(_authJson(expiresAt: '2026-11-14T10:00:00Z')),
    );

    final staleLease = authority.lease(providerId: 'xai', sessionId: 's1');
    await _pump();
    expect(refresher.pending, hasLength(1));

    // Pause the refresh commit right at its credential.json write, then fire
    // a concurrent import. With the serial queue the import cannot interleave
    // into the load->persist window; without it the stale refresh persists
    // last and clobbers the fresh login.
    fs.armWriteGate();
    refresher.pending.single.complete(
      RefreshSucceeded(
        accessToken: 'stale-access',
        refreshToken: 'rt-stale',
        expiresAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
      ),
    );
    await fs.writeEntered.timeout(const Duration(seconds: 2));

    final importFuture = authority.importFromLogin(
      'xai',
      utf8.encode(_authJson(key: 'access-new', refreshToken: 'rt-new')),
    );
    await _pump();
    fs.releaseWrite();

    await staleLease;
    expect(await importFuture, isTrue);
    await _pump();

    final raw = await fs.readString('/tp/providers/grok/xai/credential.json');
    expect(raw, contains('rt-new'), reason: 'the fresh import must win');
    expect(
      raw,
      isNot(contains('rt-stale')),
      reason: 'the stale refresh must never overwrite the newer login',
    );
  });
}
