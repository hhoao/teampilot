import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/app/bootstrap/cli_bootstrap_wiring.dart';
import 'package:teampilot/models/credential_lease.dart';
import 'package:teampilot/services/provider/oauth_credential_authority.dart';

import '../../support/in_memory_filesystem.dart';

/// Minimal `HttpClient` doubles: the refresher only calls `getUrl` (OIDC
/// discovery) and `postUrl` (token exchange), sets `headers.contentType`,
/// `write`s a body, and reads `statusCode` + the body stream.
final class _FakeHeaders implements HttpHeaders {
  @override
  ContentType? contentType;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.response);

  final HttpClientResponse response;

  @override
  final HttpHeaders headers = _FakeHeaders();

  String body = '';

  @override
  void write(Object? object) => body = object?.toString() ?? '';

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeResponse(this.statusCode, this.body);

  @override
  final int statusCode;

  final String body;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable([
    utf8.encode(body),
  ]).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({
    this.tokenStatus = 200,
    this.tokenBody = '',
    this.discoveryStatus = 200,
    this.tokenError,
  });

  final int tokenStatus;
  final String tokenBody;
  final int discoveryStatus;
  final Object? tokenError;

  var tokenRequests = 0;

  /// Last token request, so a test can assert the wire encoding.
  _FakeRequest? lastTokenRequest;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeRequest(
    _FakeResponse(
      discoveryStatus,
      jsonEncode({'token_endpoint': 'https://auth.x.ai/oauth2/token'}),
    ),
  );

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    tokenRequests++;
    final error = tokenError;
    if (error != null) throw error;
    final request = _FakeRequest(_FakeResponse(tokenStatus, tokenBody));
    lastTokenRequest = request;
    return request;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Never completes its requests: drives the request-level timeout.
final class _HangingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      Completer<HttpClientRequest>().future;

  @override
  Future<HttpClientRequest> postUrl(Uri url) =>
      Completer<HttpClientRequest>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  XaiCredentialRefresher build(HttpClient client) =>
      XaiCredentialRefresher(client: client);

  test('a rejected grant is permanent', () async {
    final client = _FakeHttpClient(
      tokenStatus: 400,
      tokenBody: '{"error":"invalid_grant"}',
    );

    expect(
      await build(client).refresh('rt'),
      isA<RefreshRejected>(),
      reason: '400 invalid_grant means the RT was rotated away',
    );
    expect(client.tokenRequests, 1);
  });

  test('401 invalid_token is permanent', () async {
    expect(
      await build(
        _FakeHttpClient(
          tokenStatus: 401,
          tokenBody: '{"error":"invalid_token"}',
        ),
      ).refresh('rt'),
      isA<RefreshRejected>(),
    );
  });

  test('400 invalid_client is our config error, not a bad RT (transient)',
      () async {
    await expectLater(
      build(
        _FakeHttpClient(
          tokenStatus: 400,
          tokenBody: '{"error":"invalid_client"}',
        ),
      ).refresh('rt'),
      throwsA(isA<CredentialTransientException>()),
    );
  });

  test('a 400/401 without invalid_grant/invalid_token is transient', () async {
    // An empty or unsupported body (e.g. unsupported_grant_type) must not be
    // read as a dead RT: the seat-shared credential survives.
    await expectLater(
      build(_FakeHttpClient(tokenStatus: 401)).refresh('rt'),
      throwsA(isA<CredentialTransientException>()),
    );
    await expectLater(
      build(
        _FakeHttpClient(
          tokenStatus: 400,
          tokenBody: '{"error":"unsupported_grant_type"}',
        ),
      ).refresh('rt'),
      throwsA(isA<CredentialTransientException>()),
    );
  });

  test('invalid_client keeps credential.json on the control plane', () async {
    final client = _FakeHttpClient(
      tokenStatus: 400,
      tokenBody: '{"error":"invalid_client"}',
    );
    final fs = InMemoryFilesystem();
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: build(client),
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    final path = '/tp/providers/grok/xai/credential.json';
    await fs.atomicWrite(
      path,
      jsonEncode({
        'provider_id': 'xai',
        'refresh_token': 'rt-old',
        'access_token': 'access-old',
        'expires_at': '2026-11-14T10:00:00Z', // expired -> forces refresh
        'epoch': 0,
      }),
    );

    await expectLater(
      authority.lease(providerId: 'xai', sessionId: 's1'),
      throwsA(isA<CredentialTransientException>()),
    );

    final raw = await fs.readString(path);
    expect(raw, isNotNull, reason: 'invalid_client must not delete the shared RT');
    expect(raw, contains('rt-old'));
  });

  test('a hanging IdP is bounded by the request timeout', () {
    fakeAsync((async) {
      Object? caught;
      unawaited(() async {
        try {
          await build(_HangingHttpClient()).refresh('rt');
        } on Object catch (error) {
          caught = error;
        }
      }());
      async.flushMicrotasks();
      expect(caught, isNull, reason: 'request still in flight');

      async.elapse(const Duration(seconds: 16));
      async.flushMicrotasks();
      expect(caught, isA<CredentialTransientException>());
    });
  });

  test('5xx and 429 keep the refresh token (transient)', () async {
    for (final status in [500, 503, 429]) {
      await expectLater(
        build(_FakeHttpClient(tokenStatus: status)).refresh('rt'),
        throwsA(isA<CredentialTransientException>()),
        reason: 'HTTP $status must not delete a still-valid RT',
      );
    }
  });

  test('a network error is transient', () async {
    await expectLater(
      build(
        _FakeHttpClient(tokenError: const SocketException('offline')),
      ).refresh('rt'),
      throwsA(isA<CredentialTransientException>()),
    );
  });

  test('discovery failure is transient', () async {
    await expectLater(
      build(_FakeHttpClient(discoveryStatus: 503)).refresh('rt'),
      throwsA(isA<CredentialTransientException>()),
    );
  });

  test('an unparsable token response is transient', () async {
    await expectLater(
      build(_FakeHttpClient(tokenBody: 'not json')).refresh('rt'),
      throwsA(isA<CredentialTransientException>()),
    );
  });

  test('a successful exchange returns the rotated tokens', () async {
    final outcome = await build(
      _FakeHttpClient(
        tokenBody: jsonEncode({
          'access_token': 'access-new',
          'refresh_token': 'rt-new',
          'expires_in': 120,
        }),
      ),
    ).refresh('rt-old');

    final succeeded = outcome as RefreshSucceeded;
    expect(succeeded.accessToken, 'access-new');
    expect(succeeded.refreshToken, 'rt-new');
    expect(
      succeeded.expiresAt.isAfter(
        DateTime.now().toUtc().add(const Duration(seconds: 60)),
      ),
      isTrue,
    );
  });

  test('the token request is form-encoded, not JSON', () async {
    final client = _FakeHttpClient(
      tokenBody: jsonEncode({'access_token': 'a', 'expires_in': 60}),
    );
    await build(client).refresh('rt-old');

    final request = client.lastTokenRequest!;
    expect(
      request.headers.contentType?.mimeType,
      'application/x-www-form-urlencoded',
      reason: 'the IdP answers a JSON token request with 415',
    );
    final params = Uri.splitQueryString(request.body);
    expect(params['grant_type'], 'refresh_token');
    expect(params['refresh_token'], 'rt-old');
    expect(params['client_id'], isNotEmpty);
  });

  test('a 200 without an access token is transient, not a rejection', () async {
    await expectLater(
      build(_FakeHttpClient(tokenBody: jsonEncode({'refresh_token': 'rt'})))
          .refresh('rt'),
      throwsA(isA<CredentialTransientException>()),
    );
  });
}
