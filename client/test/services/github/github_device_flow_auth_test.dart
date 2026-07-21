import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:teampilot/services/github/github_device_flow_auth.dart';
import 'package:teampilot/services/github/github_http.dart';

void main() {
  const clientId = 'test-client-id';

  group('GithubDeviceFlowAuth.start', () {
    test('parses device code response fields', () async {
      final requests = <_RecordedRequest>[];
      final auth = GithubDeviceFlowAuth(
        clientId: clientId,
        post: (url, {headers, body, encoding}) async {
          requests.add(_RecordedRequest(url, headers, body));
          return http.Response(
            jsonEncode({
              'device_code': 'device-abc',
              'user_code': 'ABCD-1234',
              'verification_uri': 'https://github.com/login/device',
              'verification_uri_complete':
                  'https://github.com/login/device?user_code=ABCD-1234',
              'expires_in': 900,
              'interval': 5,
            }),
            200,
          );
        },
      );

      final result = await auth.start();

      expect(requests, hasLength(1));
      expect(
        requests.single.url,
        Uri.parse('https://github.com/login/device/code'),
      );
      expect(requests.single.headers?['Accept'], 'application/json');
      expect(requests.single.headers?['User-Agent'], kGithubHttpUserAgent);
      expect(
        requests.single.body,
        'client_id=$clientId&scope=repo',
      );

      expect(result.userCode, 'ABCD-1234');
      expect(result.deviceCode, 'device-abc');
      expect(
        result.verificationUri,
        Uri.parse('https://github.com/login/device'),
      );
      expect(
        result.verificationUriComplete,
        Uri.parse('https://github.com/login/device?user_code=ABCD-1234'),
      );
      expect(result.interval, 5);
      expect(result.expiresIn, 900);
    });

    test('omits verification_uri_complete when absent', () async {
      final auth = GithubDeviceFlowAuth(
        clientId: clientId,
        post: (url, {headers, body, encoding}) async => http.Response(
          jsonEncode({
            'device_code': 'device-abc',
            'user_code': 'ABCD-1234',
            'verification_uri': 'https://github.com/login/device',
            'expires_in': 900,
            'interval': 5,
          }),
          200,
        ),
      );

      final result = await auth.start();

      expect(result.verificationUriComplete, isNull);
    });
  });

  group('GithubDeviceFlowStartResult.browserUri', () {
    test('prefers verification_uri_complete when non-empty', () {
      final result = GithubDeviceFlowStartResult(
        userCode: 'ABCD-1234',
        deviceCode: 'device-abc',
        verificationUri: Uri.parse('https://github.com/login/device'),
        verificationUriComplete:
            Uri.parse('https://github.com/login/device?user_code=ABCD-1234'),
        interval: 5,
        expiresIn: 900,
      );

      expect(
        result.browserUri,
        Uri.parse('https://github.com/login/device?user_code=ABCD-1234'),
      );
    });

    test('falls back to verification_uri when complete is null', () {
      final result = GithubDeviceFlowStartResult(
        userCode: 'ABCD-1234',
        deviceCode: 'device-abc',
        verificationUri: Uri.parse('https://github.com/login/device'),
        interval: 5,
        expiresIn: 900,
      );

      expect(result.browserUri, Uri.parse('https://github.com/login/device'));
    });
  });

  group('GithubDeviceFlowAuth.pollOnce', () {
    Future<GithubDeviceFlowPollResult> pollWithResponse(
      Map<String, Object?> json, {
      int interval = 5,
    }) async {
      final auth = GithubDeviceFlowAuth(
        clientId: clientId,
        post: (url, {headers, body, encoding}) async {
          expect(
            url,
            Uri.parse('https://github.com/login/oauth/access_token'),
          );
          expect(headers?['Accept'], 'application/json');
          expect(headers?['User-Agent'], kGithubHttpUserAgent);
          expect(
            body,
            'client_id=$clientId'
            '&device_code=device-abc'
            '&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code',
          );
          return http.Response(jsonEncode(json), 200);
        },
      );

      return auth.pollOnce('device-abc', interval: interval);
    }

    test('returns pending for authorization_pending', () async {
      final result = await pollWithResponse({
        'error': 'authorization_pending',
        'error_description': 'The authorization request is still pending.',
      });

      expect(result, isA<GithubDeviceFlowPollPending>());
    });

    test('returns slowDown with interval increased by 5', () async {
      final result = await pollWithResponse(
        {
          'error': 'slow_down',
          'error_description': 'You are polling too quickly.',
        },
        interval: 8,
      );

      expect(result, isA<GithubDeviceFlowPollSlowDown>());
      expect((result as GithubDeviceFlowPollSlowDown).newInterval, 13);
    });

    test('returns denied for access_denied', () async {
      final result = await pollWithResponse({
        'error': 'access_denied',
        'error_description': 'The user denied the authorization request.',
      });

      expect(result, isA<GithubDeviceFlowPollDenied>());
    });

    test('returns expired for expired_token', () async {
      final result = await pollWithResponse({
        'error': 'expired_token',
        'error_description': 'The device code has expired.',
      });

      expect(result, isA<GithubDeviceFlowPollExpired>());
    });

    test('returns success with access token', () async {
      final result = await pollWithResponse({
        'access_token': 'gho_test_token',
        'token_type': 'bearer',
        'scope': 'repo',
      });

      expect(result, isA<GithubDeviceFlowPollSuccess>());
      expect((result as GithubDeviceFlowPollSuccess).token, 'gho_test_token');
    });
  });
}

class _RecordedRequest {
  _RecordedRequest(this.url, this.headers, this.body);

  final Uri url;
  final Map<String, String>? headers;
  final Object? body;
}
