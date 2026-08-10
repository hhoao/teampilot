import 'dart:convert';

import 'package:http/http.dart' as http;
import 'github_http.dart';

typedef GithubDeviceFlowHttpPost =
    Future<http.Response> Function(
      Uri url, {
      Map<String, String>? headers,
      Object? body,
      Encoding? encoding,
    });

sealed class GithubDeviceFlowPollResult {
  const GithubDeviceFlowPollResult();
}

final class GithubDeviceFlowPollPending extends GithubDeviceFlowPollResult {
  const GithubDeviceFlowPollPending();
}

final class GithubDeviceFlowPollSlowDown extends GithubDeviceFlowPollResult {
  const GithubDeviceFlowPollSlowDown(this.newInterval);

  final int newInterval;
}

final class GithubDeviceFlowPollDenied extends GithubDeviceFlowPollResult {
  const GithubDeviceFlowPollDenied();
}

final class GithubDeviceFlowPollExpired extends GithubDeviceFlowPollResult {
  const GithubDeviceFlowPollExpired();
}

final class GithubDeviceFlowPollSuccess extends GithubDeviceFlowPollResult {
  const GithubDeviceFlowPollSuccess(this.token);

  final String token;
}

class GithubDeviceFlowStartResult {
  const GithubDeviceFlowStartResult({
    required this.userCode,
    required this.deviceCode,
    required this.verificationUri,
    this.verificationUriComplete,
    required this.interval,
    required this.expiresIn,
  });

  final String userCode;
  final String deviceCode;
  final Uri verificationUri;
  final Uri? verificationUriComplete;
  final int interval;
  final int expiresIn;

  Uri get browserUri {
    final complete = verificationUriComplete;
    if (complete != null) return complete;
    return verificationUri;
  }
}

class GithubDeviceFlowAuth {
  GithubDeviceFlowAuth({
    required this.clientId,
    GithubDeviceFlowHttpPost? post,
  }) : _post = post ?? http.post;

  final String clientId;
  final GithubDeviceFlowHttpPost _post;

  static final _deviceCodeUri = Uri.parse(
    'https://github.com/login/device/code',
  );
  static final _accessTokenUri = Uri.parse(
    'https://github.com/login/oauth/access_token',
  );

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'User-Agent': kGithubHttpUserAgent,
    'Content-Type': 'application/x-www-form-urlencoded',
  };

  Future<GithubDeviceFlowStartResult> start() async {
    final response = await _post(
      _deviceCodeUri,
      headers: _headers,
      body: 'client_id=$clientId&scope=repo',
    );
    _ensureSuccess(response);

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final verificationUriCompleteRaw =
        (json['verification_uri_complete'] as String?)?.trim();

    return GithubDeviceFlowStartResult(
      userCode: json['user_code'] as String,
      deviceCode: json['device_code'] as String,
      verificationUri: Uri.parse(json['verification_uri'] as String),
      verificationUriComplete:
          verificationUriCompleteRaw != null &&
              verificationUriCompleteRaw.isNotEmpty
          ? Uri.parse(verificationUriCompleteRaw)
          : null,
      interval: json['interval'] as int,
      expiresIn: json['expires_in'] as int,
    );
  }

  Future<GithubDeviceFlowPollResult> pollOnce(
    String deviceCode, {
    required int interval,
  }) async {
    final response = await _post(
      _accessTokenUri,
      headers: _headers,
      body:
          'client_id=$clientId'
          '&device_code=$deviceCode'
          '&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code',
    );
    _ensureSuccess(response);

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final error = json['error'] as String?;
    if (error != null) {
      return switch (error) {
        'authorization_pending' => const GithubDeviceFlowPollPending(),
        'slow_down' => GithubDeviceFlowPollSlowDown(interval + 5),
        'access_denied' => const GithubDeviceFlowPollDenied(),
        'expired_token' => const GithubDeviceFlowPollExpired(),
        _ => throw GithubDeviceFlowException(
          'Unexpected GitHub Device Flow error: $error',
        ),
      };
    }

    final token = json['access_token'] as String?;
    if (token == null || token.isEmpty) {
      throw GithubDeviceFlowException(
        'GitHub Device Flow response missing access_token.',
      );
    }
    return GithubDeviceFlowPollSuccess(token);
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GithubDeviceFlowException(
        'GitHub Device Flow request failed with status '
        '${response.statusCode}.',
      );
    }
  }
}

class GithubDeviceFlowException implements Exception {
  GithubDeviceFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}
