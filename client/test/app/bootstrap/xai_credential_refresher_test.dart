import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/app/bootstrap/cli_bootstrap_wiring.dart';
import 'package:teampilot/models/credential_lease.dart';
import 'package:teampilot/services/provider/oauth_credential_authority.dart';

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
    return _FakeRequest(_FakeResponse(tokenStatus, tokenBody));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  XaiCredentialRefresher build(_FakeHttpClient client) =>
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

  test('401 is also permanent', () async {
    expect(
      await build(_FakeHttpClient(tokenStatus: 401)).refresh('rt'),
      isA<RefreshRejected>(),
    );
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

  test('a 200 without an access token is transient, not a rejection', () async {
    await expectLater(
      build(_FakeHttpClient(tokenBody: jsonEncode({'refresh_token': 'rt'})))
          .refresh('rt'),
      throwsA(isA<CredentialTransientException>()),
    );
  });
}
