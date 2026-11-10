import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/services/provider_usage/adapters/qoder_usage_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);

  ManagedProvider provider({
    String url = 'https://openapi.qoder.sh/api/v2/quota/usage',
  }) => ManagedProvider(
    id: 'qoder-1',
    name: 'Qoder',
    kind: ManagedProviderKind.subscriptionQuota,
    adapterId: 'qoder-usage',
    endpointConfig: ManagedProviderEndpointConfig(
      url: url,
      method: 'GET',
      credentialField: 'apiKey',
    ),
    displayConfig: ManagedProviderDisplayConfig(
      unit: 'credits',
      decimalPlaces: 2,
    ),
  );

  Future<ProviderUsageSnapshot> fetch(
    _QueueHttp http, {
    Map<String, String> credentials = const {'apiKey': 'pt-test'},
    String url = 'https://openapi.qoder.sh/api/v2/quota/usage',
  }) => QoderUsageAdapter().fetch(
    provider(url: url),
    credentials: _Credentials(credentials),
    http: http,
    now: now,
  );

  Matcher queryError(ManagedProviderUsageQueryErrorCode code) =>
      isA<ManagedProviderUsageQueryError>().having(
        (error) => error.code,
        'code',
        code,
      );

  test('exchanges a PAT and maps plan, add-on, and org credits', () async {
    final http = _QueueHttp([_exchangeOk, _usageOk]);

    final snapshot = await fetch(http);

    expect(http.requests, hasLength(2));
    final exchange = http.requests.first;
    expect(exchange.method, 'POST');
    expect(
      exchange.uri.toString(),
      'https://openapi.qoder.sh/api/v1/jobToken/exchange',
    );
    expect(exchange.headers['content-type'], 'application/json');
    expect(exchange.headers['accept'], 'application/json');
    expect(exchange.headers['user-agent'], 'teampilot-qoder-usage/1.0');
    expect(exchange.headers['cosy-version'], '1.0.1');
    expect(exchange.headers['cosy-clienttype'], '5');
    expect(jsonDecode(exchange.body!), {'personal_token': 'pt-test'});

    final usage = http.requests.last;
    expect(usage.method, 'GET');
    expect(
      usage.uri.toString(),
      'https://openapi.qoder.sh/api/v2/quota/usage',
    );
    expect(usage.headers['authorization'], 'Bearer jt-test');
    expect(usage.headers['accept'], 'application/json');
    expect(usage.headers['user-agent'], 'teampilot-qoder-usage/1.0');
    expect(usage.headers.containsKey('cosy-version'), isFalse);

    expect(snapshot.providerId, 'qoder-1');
    expect(snapshot.status, ProviderUsageStatus.ready);
    expect(snapshot.fetchedAt, now.millisecondsSinceEpoch);
    expect(snapshot.measures.map((measure) => measure.label), [
      'Plan',
      'Add-on',
      'Org',
    ]);

    final plan = snapshot.measures[0];
    expect(plan.used, '1200');
    expect(plan.total, '3000');
    expect(plan.remaining, '1800');
    expect(plan.unit, 'credits');
    expect(plan.kind, ProviderUsageMeasureKind.quota);
    expect(plan.resetsAt, 1790000000000);

    final addOn = snapshot.measures[1];
    expect(addOn.used, '50');
    expect(addOn.total, '50');
    expect(addOn.remaining, '0');

    final org = snapshot.measures[2];
    expect(org.used, '10');
    expect(org.total, '100');
    expect(org.remaining, '90');
    expect(org.resetsAt, 1790000000000);
  });

  test('uses the CN openapi host when the preset URL is CN', () async {
    final http = _QueueHttp([_exchangeOk, _usageOk]);

    await fetch(
      http,
      url: 'https://openapi.qoder.com.cn/api/v2/quota/usage',
    );

    expect(http.requests.map((request) => request.uri.host), [
      'openapi.qoder.com.cn',
      'openapi.qoder.com.cn',
    ]);
    expect(http.requests.first.uri.path, '/api/v1/jobToken/exchange');
    expect(http.requests.last.uri.path, '/api/v2/quota/usage');
  });

  test('rejects non-allowlisted or malformed URLs without sending', () async {
    const urls = [
      'https://evil.example/api/v2/quota/usage',
      'http://openapi.qoder.sh/api/v2/quota/usage',
      'https://openapi.qoder.sh/api/v2/quota/other',
      'https://openapi.qoder.sh/api/v2/quota/usage?x=1',
      'https://openapi.qoder.sh:8443/api/v2/quota/usage',
      'https://openapi.qoder.sh/api/v2/quota/usage#frag',
    ];
    for (final url in urls) {
      final http = _QueueHttp([_exchangeOk, _usageOk]);
      await expectLater(
        fetch(http, url: url),
        throwsA(queryError(ManagedProviderUsageQueryErrorCode.unsupported)),
        reason: url,
      );
      expect(http.requests, isEmpty, reason: url);
    }
  });

  test('missing PAT fails with missingCredential', () async {
    final http = _QueueHttp([_exchangeOk, _usageOk]);

    await expectLater(
      fetch(http, credentials: const {}),
      throwsA(
        queryError(ManagedProviderUsageQueryErrorCode.missingCredential),
      ),
    );
    expect(http.requests, isEmpty);
  });

  for (final status in [400, 401, 403]) {
    test('exchange status $status maps to authenticationFailed', () async {
      final http = _QueueHttp([
        ProviderUsageHttpResponse(statusCode: status, body: '{}'),
      ]);

      await expectLater(
        fetch(http),
        throwsA(
          queryError(
            ManagedProviderUsageQueryErrorCode.authenticationFailed,
          ),
        ),
      );
      expect(http.requests, hasLength(1));
    });
  }

  test('exchange 500 maps to httpFailed', () async {
    final http = _QueueHttp([
      const ProviderUsageHttpResponse(statusCode: 500, body: '{}'),
    ]);

    await expectLater(
      fetch(http),
      throwsA(queryError(ManagedProviderUsageQueryErrorCode.httpFailed)),
    );
  });

  test('usage 401 maps to authenticationFailed', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(statusCode: 401, body: '{}'),
    ]);

    await expectLater(
      fetch(http),
      throwsA(
        queryError(ManagedProviderUsageQueryErrorCode.authenticationFailed),
      ),
    );
  });

  test('usage 500 maps to httpFailed', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(statusCode: 500, body: '{}'),
    ]);

    await expectLater(
      fetch(http),
      throwsA(queryError(ManagedProviderUsageQueryErrorCode.httpFailed)),
    );
  });

  test('exchange response without a token fails with responseParseFailed', () async {
    final http = _QueueHttp([
      const ProviderUsageHttpResponse(statusCode: 200, body: '{}'),
    ]);

    await expectLater(
      fetch(http),
      throwsA(
        queryError(ManagedProviderUsageQueryErrorCode.responseParseFailed),
      ),
    );
  });

  test('usage response that is not JSON fails with responseParseFailed', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(statusCode: 200, body: 'not-json'),
    ]);

    await expectLater(
      fetch(http),
      throwsA(
        queryError(ManagedProviderUsageQueryErrorCode.responseParseFailed),
      ),
    );
  });

  test('usage response without buckets or percentage fails with responseParseFailed', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(
        statusCode: 200,
        body: '{"expiresAt":1790000000000}',
      ),
    ]);

    await expectLater(
      fetch(http),
      throwsA(
        queryError(ManagedProviderUsageQueryErrorCode.responseParseFailed),
      ),
    );
  });

  test('renders only buckets present in the response', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(
        statusCode: 200,
        body:
            '{"userQuota":{"total":10,"used":5,"remaining":5,"unit":"credits"}}',
      ),
    ]);

    final snapshot = await fetch(http);

    expect(snapshot.measures.map((measure) => measure.label), ['Plan']);
    expect(snapshot.measures.single.resetsAt, isNull);
  });

  test('org package falls back to total when cap is absent', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(
        statusCode: 200,
        body:
            '{"orgResourcePackage":{"total":100,"used":10,"remaining":90}}',
      ),
    ]);

    final snapshot = await fetch(http);

    expect(snapshot.measures.single.label, 'Org');
    expect(snapshot.measures.single.total, '100');
    expect(snapshot.measures.single.unit, 'credits');
  });

  test('falls back to totalUsagePercentage when no buckets exist', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(
        statusCode: 200,
        body: '{"totalUsagePercentage":40,"expiresAt":1790000000000}',
      ),
    ]);

    final snapshot = await fetch(http);

    final measure = snapshot.measures.single;
    expect(measure.label, 'Usage');
    expect(measure.used, '40');
    expect(measure.total, '100');
    expect(measure.remaining, '60');
    expect(measure.unit, '%');
    expect(measure.resetsAt, 1790000000000);
  });

  test('parses second-based expiresAt into milliseconds', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(
        statusCode: 200,
        body: '{"userQuota":{"total":10,"used":5},"expiresAt":1790000000}',
      ),
    ]);

    final snapshot = await fetch(http);

    expect(snapshot.measures.single.resetsAt, 1790000000000);
  });

  test('errors do not expose the PAT or job token', () async {
    final http = _QueueHttp([
      _exchangeOk,
      const ProviderUsageHttpResponse(statusCode: 401, body: '{}'),
    ]);

    try {
      await fetch(http);
      fail('expected the fetch to fail');
    } on ManagedProviderUsageQueryError catch (error) {
      expect(error.toString(), isNot(contains('pt-test')));
      expect(error.toString(), isNot(contains('jt-test')));
    }
  });
}

const _exchangeOk = ProviderUsageHttpResponse(
  statusCode: 200,
  body: '{"token":"jt-test","refresh_token":"jrt-test","expires_in":86400000}',
);

const _usageOk = ProviderUsageHttpResponse(
  statusCode: 200,
  body: '''
{
  "totalUsagePercentage": 40,
  "isQuotaExceeded": false,
  "expiresAt": 1790000000000,
  "userQuota": {"total": 3000, "used": 1200, "remaining": 1800, "unit": "credits"},
  "addOnQuota": {"total": 50, "used": 50, "remaining": 0, "unit": "credits"},
  "orgResourcePackage": {"cap": 100, "used": 10, "remaining": 90, "unit": "credits"}
}''',
);

class _Scope implements ProviderCredentialScope {
  _Scope(this._values);

  final Map<String, String> _values;

  @override
  bool get isEmpty => _values.isEmpty;

  @override
  Iterable<String> get fields => _values.keys;

  @override
  String? valueFor(String field) => _values[field];
}

class _Credentials implements ProviderCredentialResolver {
  _Credentials(this.values);

  final Map<String, String> values;

  @override
  Future<ProviderCredentialScope?> resolve(ManagedProvider provider) async =>
      _Scope(values);
}

class _QueueHttp implements ProviderUsageHttpClient {
  _QueueHttp(this.responses);

  final List<ProviderUsageHttpResponse> responses;
  final requests = <ProviderUsageHttpRequest>[];

  @override
  Future<ProviderUsageHttpResponse> send(
    ProviderUsageHttpRequest request,
  ) async {
    requests.add(request);
    return responses[requests.length - 1];
  }
}
