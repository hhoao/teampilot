import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/services/provider_usage/adapters/grok_dashboard_usage_adapter.dart';
import 'package:teampilot/services/provider_usage/cli_credential_source.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);

  ManagedProvider provider({
    String url =
        'https://grok.com/dashboard/api/dashboard/v2/usage-status?scope=user',
    String credentialSource = 'cli:cursor-mp-p1',
  }) => ManagedProvider(
    id: 'p1',
    name: 'Grok / Cursor / X',
    kind: ManagedProviderKind.subscriptionQuota,
    adapterId: 'grok-dashboard-usage',
    endpointConfig: ManagedProviderEndpointConfig(
      url: url,
      method: 'GET',
      credentialSource: credentialSource,
    ),
  );

  GrokDashboardUsageAdapter adapter({
    OfficialSubscriptionAuthReader? reader = const _CursorReader(
      _Scope({'accessToken': 'jwt-token', 'accountId': 'user'}),
    ),
    bool withCliCredentials = true,
  }) => GrokDashboardUsageAdapter(
    cliCredentials: withCliCredentials
        ? CliCredentialSourceResolver(
            readers: {if (reader != null) 'cursor': reader},
          )
        : null,
  );

  Future<ProviderUsageSnapshot> fetch(
    ProviderUsageHttpClient http, {
    String url =
        'https://grok.com/dashboard/api/dashboard/v2/usage-status?scope=user',
    OfficialSubscriptionAuthReader? reader = const _CursorReader(
      _Scope({'accessToken': 'jwt-token', 'accountId': 'user'}),
    ),
    bool withCliCredentials = true,
  }) => adapter(reader: reader, withCliCredentials: withCliCredentials).fetch(
    provider(url: url),
    credentials: const _UnusedCredentials(),
    http: http,
    now: now,
  );

  Matcher queryError(ManagedProviderUsageQueryErrorCode code) =>
      isA<ManagedProviderUsageQueryError>().having(
        (error) => error.code,
        'code',
        code,
      );

  test(
    'maps weekly percent and prepaid dollars from the cursor cookie',
    () async {
      final http = _QueueHttp([_usageOk, _prepaidOk]);

      final snapshot = await fetch(http);

      expect(http.requests, hasLength(2));
      final usage = http.requests.first;
      expect(usage.method, 'GET');
      expect(
        usage.uri.toString(),
        'https://cursor.com/api/dashboard/v2/usage-status?scope=user',
      );
      expect(usage.body, isNull);
      expect(usage.headers['Accept'], 'application/json');
      expect(usage.headers['Origin'], 'https://cursor.com');
      expect(usage.headers['Referer'], 'https://cursor.com/dashboard');
      expect(usage.headers['User-Agent'], 'TeamPilot');
      expect(usage.headers['x-cursor-dashboard-surface'], 'v2');
      expect(
        usage.headers['Cookie'],
        'WorkosCursorSessionToken=user%3A%3Ajwt-token',
      );
      expect(usage.headers['Cookie'], isNot(contains('cf_clearance')));
      expect(usage.headers.containsKey('WorkosCursorXaiOrigin'), isFalse);

      final prepaid = http.requests.last;
      expect(prepaid.method, 'POST');
      expect(
        prepaid.uri.toString(),
        'https://cursor.com/api/dashboard/get-user-prepaid-billing',
      );
      expect(jsonDecode(prepaid.body!), <String, Object?>{});
      expect(prepaid.headers['content-type'], 'application/json');
      expect(prepaid.headers['Accept'], 'application/json');
      expect(prepaid.headers['Origin'], 'https://cursor.com');
      expect(prepaid.headers['Referer'], 'https://cursor.com/dashboard');
      expect(prepaid.headers['x-cursor-dashboard-surface'], 'v2');
      expect(
        prepaid.headers['Cookie'],
        'WorkosCursorSessionToken=user%3A%3Ajwt-token',
      );

      expect(snapshot.providerId, 'p1');
      expect(snapshot.status, ProviderUsageStatus.ready);
      expect(snapshot.fetchedAt, now.millisecondsSinceEpoch);
      expect(snapshot.measures.map((measure) => measure.label), [
        'Weekly',
        'Prepaid',
      ]);

      final weekly = snapshot.measures[0];
      expect(weekly.kind, ProviderUsageMeasureKind.quota);
      expect(weekly.unit, '%');
      expect(weekly.used, '42');
      expect(weekly.total, '100');
      expect(weekly.remaining, '58');
      expect(
        weekly.resetsAt,
        DateTime.parse('2026-11-17T00:00:00.000Z').millisecondsSinceEpoch,
      );

      final balance = snapshot.measures[1];
      expect(balance.kind, ProviderUsageMeasureKind.balance);
      expect(balance.unit, 'USD');
      expect(balance.remaining, '12.50');
      expect(balance.resetsAt, isNull);
    },
  );

  test('prepaid 401 keeps only the weekly measure', () async {
    final http = _QueueHttp([
      _usageOk,
      const ProviderUsageHttpResponse(statusCode: 401, body: '{}'),
    ]);

    final snapshot = await fetch(http);

    expect(snapshot.status, ProviderUsageStatus.ready);
    expect(snapshot.measures.map((measure) => measure.label), ['Weekly']);
    expect(snapshot.measures.single.used, '42');
    expect(snapshot.measures.single.remaining, '58');
  });

  test(
    'usage-status 401 is authenticationFailed and hides the token',
    () async {
      final http = _QueueHttp([
        const ProviderUsageHttpResponse(statusCode: 401, body: 'jwt-token'),
      ]);

      try {
        await fetch(http);
        fail('expected the fetch to fail');
      } on ManagedProviderUsageQueryError catch (error) {
        expect(
          error.code,
          ManagedProviderUsageQueryErrorCode.authenticationFailed,
        );
        expect(error.toString(), isNot(contains('jwt-token')));
      }
      expect(http.requests, hasLength(1));
    },
  );

  test('rejects non-allowlisted or malformed URLs without sending', () async {
    const urls = [
      'https://evil.test/usage-status?scope=user',
      'http://grok.com/dashboard/api/dashboard/v2/usage-status?scope=user',
      'https://grok.com/dashboard/api/dashboard/v2/other?scope=user',
      'https://grok.com/dashboard/api/dashboard/v2/usage-status',
      'https://grok.com/dashboard/api/dashboard/v2/usage-status?scope=team',
      'https://grok.com/dashboard/api/dashboard/v2/usage-status?scope=user&extra=1',
      'https://grok.com:8443/dashboard/api/dashboard/v2/usage-status?scope=user',
      'https://grok.com/dashboard/api/dashboard/v2/usage-status?scope=user#frag',
      'https://user@grok.com/dashboard/api/dashboard/v2/usage-status?scope=user',
      'https://cursor.com/dashboard/api/dashboard/v2/usage-status?scope=user',
      'https://cursor.com/api/dashboard/v2/usage-status',
    ];
    for (final url in urls) {
      final http = _QueueHttp([_usageOk, _prepaidOk]);
      await expectLater(
        fetch(http, url: url),
        throwsA(queryError(ManagedProviderUsageQueryErrorCode.unsupported)),
        reason: url,
      );
      expect(http.requests, isEmpty, reason: url);
    }
  });

  test(
    'zero budget with an empty prepaid body fails with responseParseFailed',
    () async {
      final http = _QueueHttp([
        const ProviderUsageHttpResponse(
          statusCode: 200,
          body:
              '{"availability":"available","weeklyIncludedUsage":{"usedCents":10,"budgetCents":0}}',
        ),
        const ProviderUsageHttpResponse(statusCode: 401, body: '{}'),
        const ProviderUsageHttpResponse(statusCode: 200, body: '{}'),
      ]);

      await expectLater(
        fetch(http),
        throwsA(
          queryError(ManagedProviderUsageQueryErrorCode.responseParseFailed),
        ),
      );
      expect(http.requests, hasLength(3));
    },
  );

  test('missing cli credentials fails before any request', () async {
    final http = _QueueHttp([_usageOk, _prepaidOk]);

    await expectLater(
      fetch(http, withCliCredentials: false),
      throwsA(queryError(ManagedProviderUsageQueryErrorCode.missingCredential)),
    );
    expect(http.requests, isEmpty);
  });

  test('a scope without an access token fails before any request', () async {
    final http = _QueueHttp([_usageOk, _prepaidOk]);

    await expectLater(
      fetch(http, reader: const _CursorReader(_Scope({'accountId': 'user'}))),
      throwsA(queryError(ManagedProviderUsageQueryErrorCode.missingCredential)),
    );
    expect(http.requests, isEmpty);
  });

  test('fills accountId from jwt sub when the scope omits it', () async {
    final payload = base64Url
        .encode(utf8.encode('{"sub":"user_01ABC"}'))
        .replaceAll('=', '');
    final jwt = 'eyJhbGciOiJub25lIn0.$payload.sig';
    final http = _QueueHttp([_usageOk, _prepaidOk]);

    await fetch(http, reader: _CursorReader(_Scope({'accessToken': jwt})));

    expect(
      http.requests.first.headers['Cookie'],
      'WorkosCursorSessionToken=user_01ABC%3A%3A$jwt',
    );
  });

  test('drops empty accountId colons in the session cookie', () async {
    final http = _QueueHttp([_usageOk, _prepaidOk]);

    await fetch(
      http,
      reader: const _CursorReader(_Scope({'accessToken': 'tok'})),
    );

    expect(
      http.requests.first.headers['Cookie'],
      'WorkosCursorSessionToken=tok',
    );
  });

  test(
    'usage-status 403 is authenticationFailed and hides the token',
    () async {
      final http = _QueueHttp([
        const ProviderUsageHttpResponse(statusCode: 403, body: 'jwt-token'),
      ]);

      try {
        await fetch(http);
        fail('expected the fetch to fail');
      } on ManagedProviderUsageQueryError catch (error) {
        expect(
          error.code,
          ManagedProviderUsageQueryErrorCode.authenticationFailed,
        );
        expect(error.toString(), isNot(contains('jwt-token')));
      }
      expect(http.requests, hasLength(1));
    },
  );

  test('usage-status 500 maps to httpFailed', () async {
    final http = _QueueHttp([
      const ProviderUsageHttpResponse(statusCode: 500, body: '{}'),
    ]);

    await expectLater(
      fetch(http),
      throwsA(queryError(ManagedProviderUsageQueryErrorCode.httpFailed)),
    );
    expect(http.requests, hasLength(1));
  });

  test('usage-status transport failure maps to networkFailed', () async {
    final http = _ThrowingHttp();

    await expectLater(
      fetch(http),
      throwsA(queryError(ManagedProviderUsageQueryErrorCode.networkFailed)),
    );
    expect(http.sends, 1);
  });

  test('usage-status that is not a JSON object fails parse', () async {
    final http = _QueueHttp([
      const ProviderUsageHttpResponse(statusCode: 200, body: 'not-json'),
    ]);

    await expectLater(
      fetch(http),
      throwsA(
        queryError(ManagedProviderUsageQueryErrorCode.responseParseFailed),
      ),
    );
    expect(http.requests, hasLength(1));
  });

  test('prepaid transport failure keeps the weekly measure', () async {
    final http = _ThrowAfterFirst(_usageOk);

    final snapshot = await fetch(http);

    expect(snapshot.measures.map((measure) => measure.label), ['Weekly']);
    expect(http.sends, 2);
  });

  test('parses decimal-string cents and whole prepaid dollars', () async {
    final http = _QueueHttp([
      const ProviderUsageHttpResponse(
        statusCode: 200,
        body:
            '{"availability":"available","weeklyIncludedUsage":{"usedCents":"2500","budgetCents":"10000"}}',
      ),
      const ProviderUsageHttpResponse(
        statusCode: 200,
        body:
            '{"billingMode":"PREPAID_BILLING_MODE_PREPAID","eligible":true,"availableCents":1000}',
      ),
    ]);

    final snapshot = await fetch(http);

    expect(snapshot.measures[0].used, '25');
    expect(snapshot.measures[0].total, '100');
    expect(snapshot.measures[0].remaining, '75');
    expect(snapshot.measures[0].resetsAt, isNull);
    expect(snapshot.measures[1].remaining, '10');
    expect(snapshot.measures[1].unit, 'USD');
  });

  test('clamps weekly percent and omits ineligible prepaid', () async {
    final http = _QueueHttp([
      const ProviderUsageHttpResponse(
        statusCode: 200,
        body:
            '{"availability":"available","weeklyIncludedUsage":{"usedCents":15000,"budgetCents":10000},"windows":[{"used":1}]}',
      ),
      const ProviderUsageHttpResponse(
        statusCode: 200,
        body:
            '{"billingMode":"PREPAID_BILLING_MODE_PREPAID","eligible":false,"availableCents":1250}',
      ),
    ]);

    final snapshot = await fetch(http);

    expect(snapshot.measures, hasLength(1));
    expect(snapshot.measures.single.label, 'Weekly');
    expect(snapshot.measures.single.used, '100');
    expect(snapshot.measures.single.remaining, '0');
  });

  test(
    'unavailable weekly still returns prepaid, including zero cents',
    () async {
      final http = _QueueHttp([
        const ProviderUsageHttpResponse(
          statusCode: 200,
          body:
              '{"availability":"unavailable","weeklyIncludedUsage":{"usedCents":4200,"budgetCents":10000}}',
        ),
        const ProviderUsageHttpResponse(statusCode: 401, body: '{}'),
        const ProviderUsageHttpResponse(
          statusCode: 200,
          body:
              '{"billingMode":"PREPAID_BILLING_MODE_PREPAID","eligible":true}',
        ),
      ]);

      final snapshot = await fetch(http);

      expect(snapshot.measures.map((measure) => measure.label), ['Prepaid']);
      expect(snapshot.measures.single.remaining, '0');
      expect(snapshot.measures.single.resetsAt, isNull);
      expect(http.requests.map((request) => request.uri.path), [
        '/api/dashboard/v2/usage-status',
        '/api/dashboard/get-sand-usage-status',
        '/api/dashboard/get-user-prepaid-billing',
      ]);
    },
  );

  test('rewrites grok.com config URLs onto cursor.com', () async {
    final http = _QueueHttp([_usageOk, _prepaidOk]);

    await fetch(
      http,
      url:
          'https://GROK.COM/dashboard/api/dashboard/v2/usage-status?scope=user',
    );

    expect(http.requests.map((request) => request.uri.toString()), [
      'https://cursor.com/api/dashboard/v2/usage-status?scope=user',
      'https://cursor.com/api/dashboard/get-user-prepaid-billing',
    ]);
  });

  test(
    'accepts the cursor.com usage-status URL without rewriting host',
    () async {
      final http = _QueueHttp([_usageOk, _prepaidOk]);

      await fetch(
        http,
        url: 'https://cursor.com/api/dashboard/v2/usage-status?scope=user',
      );

      expect(
        http.requests.first.uri.toString(),
        'https://cursor.com/api/dashboard/v2/usage-status?scope=user',
      );
    },
  );

  test(
    'falls back to sand weekly usage when usage-status has no weekly pool',
    () async {
      final http = _QueueHttp([
        const ProviderUsageHttpResponse(
          statusCode: 200,
          body: '{"availability":"unavailable"}',
        ),
        const ProviderUsageHttpResponse(
          statusCode: 200,
          body:
              '{"usagePercent":42,"nextResetTimestampUtc":"2026-11-17T00:00:00.000Z","hasNonZeroIncludedLimit":true,"isUnified":true}',
        ),
        _prepaidOk,
      ]);

      final snapshot = await fetch(http);

      expect(http.requests.map((request) => request.uri.toString()), [
        'https://cursor.com/api/dashboard/v2/usage-status?scope=user',
        'https://cursor.com/api/dashboard/get-sand-usage-status',
        'https://cursor.com/api/dashboard/get-user-prepaid-billing',
      ]);
      expect(http.requests[1].method, 'POST');
      expect(jsonDecode(http.requests[1].body!), <String, Object?>{});
      expect(snapshot.measures.map((measure) => measure.label), [
        'Weekly',
        'Prepaid',
      ]);
      expect(snapshot.measures[0].used, '42');
      expect(snapshot.measures[0].remaining, '58');
      expect(
        snapshot.measures[0].resetsAt,
        DateTime.parse('2026-11-17T00:00:00.000Z').millisecondsSinceEpoch,
      );
    },
  );
}

const _usageOk = ProviderUsageHttpResponse(
  statusCode: 200,
  body:
      '{"availability":"available","weeklyIncludedUsage":{"usedCents":4200,"budgetCents":10000,"resetsAt":"2026-11-17T00:00:00.000Z"}}',
);

const _prepaidOk = ProviderUsageHttpResponse(
  statusCode: 200,
  body:
      '{"billingMode":"PREPAID_BILLING_MODE_PREPAID","eligible":true,"availableCents":1250}',
);

class _Scope implements ProviderCredentialScope {
  const _Scope(this._values);

  final Map<String, String> _values;

  @override
  bool get isEmpty => _values.isEmpty;

  @override
  Iterable<String> get fields => _values.keys;

  @override
  String? valueFor(String field) => _values[field];
}

class _CursorReader implements OfficialSubscriptionAuthReader {
  const _CursorReader(this.scope);

  final ProviderCredentialScope scope;

  @override
  Future<ProviderCredentialScope?> read(ManagedProvider provider) async =>
      scope;
}

class _UnusedCredentials implements ProviderCredentialResolver {
  const _UnusedCredentials();

  @override
  Future<ProviderCredentialScope?> resolve(ManagedProvider provider) async =>
      null;
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

class _ThrowingHttp implements ProviderUsageHttpClient {
  int sends = 0;

  @override
  Future<ProviderUsageHttpResponse> send(
    ProviderUsageHttpRequest request,
  ) async {
    sends++;
    throw StateError('offline');
  }
}

class _ThrowAfterFirst implements ProviderUsageHttpClient {
  _ThrowAfterFirst(this.first);

  final ProviderUsageHttpResponse first;
  int sends = 0;

  @override
  Future<ProviderUsageHttpResponse> send(
    ProviderUsageHttpRequest request,
  ) async {
    sends++;
    if (sends == 1) return first;
    throw StateError('offline');
  }
}
