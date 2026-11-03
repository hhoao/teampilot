import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/services/provider_usage/adapters/codebuddy_credits_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';

import '../../support/in_memory_filesystem.dart';

ManagedProvider _provider() => ManagedProvider(
  id: 'm1',
  name: 'CodeBuddy',
  kind: ManagedProviderKind.apiBalance,
  adapterId: 'codebuddy-credits',
  endpointConfig: ManagedProviderEndpointConfig(
    url: 'https://www.codebuddy.cn/billing/meter/get-user-resource-summary',
    method: 'POST',
    credentialSource: 'cli:codebuddy-mp-m1',
    credentialField: 'accessToken',
    credentialName: 'Authorization',
    credentialPrefix: 'Bearer ',
  ),
);

class _NoCredentials implements ProviderCredentialResolver {
  @override
  Future<ProviderCredentialScope?> resolve(ManagedProvider provider) async =>
      null;
}

class _FakeHttp implements ProviderUsageHttpClient {
  _FakeHttp({this.response});

  final ProviderUsageHttpResponse? response;
  final requests = <ProviderUsageHttpRequest>[];

  @override
  Future<ProviderUsageHttpResponse> send(
    ProviderUsageHttpRequest request,
  ) async {
    requests.add(request);
    return response!;
  }
}

void main() {
  late InMemoryFilesystem fs;
  final now = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
  final expiresAt = DateTime.now()
      .add(const Duration(days: 30))
      .millisecondsSinceEpoch;

  setUp(() {
    fs = InMemoryFilesystem();
  });

  Future<void> writeAuth({
    String accessToken = 'cb-token',
    String domain = 'www.codebuddy.cn',
    int? expires,
  }) => fs.writeString(
    '/tp/providers/codebuddy/codebuddy-mp-m1.auth.json',
    jsonEncode({
      'accessToken': accessToken,
      'expiresAt': expires ?? expiresAt,
      'domain': domain,
    }),
  );

  test('reads the per-entry login and maps total credits', () async {
    await writeAuth();
    final http = _FakeHttp(
      response: const ProviderUsageHttpResponse(
        statusCode: 200,
        body:
            '{"code":0,"msg":"OK","data":{"TotalCredits":"2476.53000001","CreditGroups":[]}}',
      ),
    );

    final snapshot = await CodebuddyCreditsUsageAdapter(
      fs: fs,
      basePath: '/tp',
    ).fetch(_provider(), credentials: _NoCredentials(), http: http, now: now);

    expect(snapshot.status, ProviderUsageStatus.ready);
    expect(snapshot.measures.single.remaining, '2476.53000001');
    expect(snapshot.measures.single.unit, 'credits');
    expect(snapshot.measures.single.kind, ProviderUsageMeasureKind.balance);
    final request = http.requests.single;
    expect(request.method, 'POST');
    expect(
      request.uri.toString(),
      'https://www.codebuddy.cn/billing/meter/get-user-resource-summary',
    );
    expect(request.headers['authorization'], 'Bearer cb-token');
    expect(request.body, '{}');
  });

  test('uses the account realm from the auth file', () async {
    await writeAuth(domain: 'www.codebuddy.ai');
    final http = _FakeHttp(
      response: const ProviderUsageHttpResponse(
        statusCode: 200,
        body: '{"code":0,"data":{"TotalCredits":"10"}}',
      ),
    );

    await CodebuddyCreditsUsageAdapter(
      fs: fs,
      basePath: '/tp',
    ).fetch(_provider(), credentials: _NoCredentials(), http: http, now: now);

    expect(
      http.requests.single.uri.toString(),
      'https://www.codebuddy.ai/billing/meter/get-user-resource-summary',
    );
  });

  test('missing login fails with missingCredential', () async {
    await expectLater(
      CodebuddyCreditsUsageAdapter(fs: fs, basePath: '/tp').fetch(
        _provider(),
        credentials: _NoCredentials(),
        http: _FakeHttp(),
        now: now,
      ),
      throwsA(
        isA<ManagedProviderUsageQueryError>().having(
          (error) => error.code,
          'code',
          ManagedProviderUsageQueryErrorCode.missingCredential,
        ),
      ),
    );
  });

  test('expired login fails with missingCredential', () async {
    await writeAuth(
      expires: now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
    );

    await expectLater(
      CodebuddyCreditsUsageAdapter(fs: fs, basePath: '/tp').fetch(
        _provider(),
        credentials: _NoCredentials(),
        http: _FakeHttp(),
        now: now,
      ),
      throwsA(
        isA<ManagedProviderUsageQueryError>().having(
          (error) => error.code,
          'code',
          ManagedProviderUsageQueryErrorCode.missingCredential,
        ),
      ),
    );
  });

  test('untrusted auth domain fails closed with unsupported', () async {
    await writeAuth(domain: 'evil.example');

    await expectLater(
      CodebuddyCreditsUsageAdapter(fs: fs, basePath: '/tp').fetch(
        _provider(),
        credentials: _NoCredentials(),
        http: _FakeHttp(),
        now: now,
      ),
      throwsA(
        isA<ManagedProviderUsageQueryError>().having(
          (error) => error.code,
          'code',
          ManagedProviderUsageQueryErrorCode.unsupported,
        ),
      ),
    );
  });

  test('rejected token maps to authenticationFailed', () async {
    await writeAuth();

    await expectLater(
      CodebuddyCreditsUsageAdapter(fs: fs, basePath: '/tp').fetch(
        _provider(),
        credentials: _NoCredentials(),
        http: _FakeHttp(
          response: const ProviderUsageHttpResponse(
            statusCode: 401,
            body: '{}',
          ),
        ),
        now: now,
      ),
      throwsA(
        isA<ManagedProviderUsageQueryError>().having(
          (error) => error.code,
          'code',
          ManagedProviderUsageQueryErrorCode.authenticationFailed,
        ),
      ),
    );
  });

  test('malformed summary maps to responseParseFailed', () async {
    await writeAuth();

    await expectLater(
      CodebuddyCreditsUsageAdapter(fs: fs, basePath: '/tp').fetch(
        _provider(),
        credentials: _NoCredentials(),
        http: _FakeHttp(
          response: const ProviderUsageHttpResponse(
            statusCode: 200,
            body: '{"code":0,"data":{}}',
          ),
        ),
        now: now,
      ),
      throwsA(
        isA<ManagedProviderUsageQueryError>().having(
          (error) => error.code,
          'code',
          ManagedProviderUsageQueryErrorCode.responseParseFailed,
        ),
      ),
    );
  });
}
