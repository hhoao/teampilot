import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/services/provider_usage/managed_provider_presets.dart';
import 'package:teampilot/services/provider_usage/adapters/http_json_mapping_adapter.dart';
import 'package:teampilot/services/provider_usage/cli_credential_source.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_registry.dart';

import 'http_json_mapping_test_support.dart';

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true);

  test(
    'maps multiple plans without converting decimal amounts to double',
    () async {
      final fakeHttp = FakeProviderUsageHttpClient(
        response: const ProviderUsageHttpResponse(
          statusCode: 200,
          body:
              '{"data":[{"planName":"5h","remaining":"12.50","total":"20.00","unit":"USD"},{"planName":"weekly","remaining":"0.75","total":"10.00","unit":"USD"}]}',
        ),
      );
      final adapter = HttpJsonMappingAdapter(
        config: mappingConfig(
          url: 'https://example.test/v1/balance',
          windows: [
            usageWindow(
              label: '5h',
              remaining: r'$.data[0].remaining',
              total: r'$.data[0].total',
              unit: 'USD',
            ),
            usageWindow(
              label: 'weekly',
              remaining: r'$.data[1].remaining',
              total: r'$.data[1].total',
              unit: 'USD',
            ),
          ],
        ),
      );

      final snapshot = await adapter.fetch(
        _provider(),
        credentials: const _Resolver(_Credentials({'apiKey': 'secret'})),
        http: fakeHttp,
        now: now,
      );

      expect(snapshot.status, ProviderUsageStatus.ready);
      expect(snapshot.measures.map((m) => m.remaining), ['12.50', '0.75']);
      expect(snapshot.measures.map((m) => m.total), ['20.00', '10.00']);
      expect(snapshot.measures.map((m) => m.label), ['5h', 'weekly']);
      expect(fakeHttp.requests.single.method, 'GET');
      expect(
        fakeHttp.requests.single.uri.toString(),
        'https://example.test/v1/balance',
      );
    },
  );

  test(
    'marks a successful HTTP/JSON snapshot stale after ten minutes',
    () async {
      final adapter = HttpJsonMappingAdapter(
        config: mappingConfig(url: 'https://example.test/usage'),
      );

      final snapshot = await adapter.fetch(
        _provider(),
        credentials: const _Resolver(null),
        http: FakeProviderUsageHttpClient(
          response: const ProviderUsageHttpResponse(
            statusCode: 200,
            body: '{"remaining":"3.25"}',
          ),
        ),
        now: now,
      );

      expect(
        snapshot.staleAt,
        now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
      );
    },
  );

  test(
    'places an API key in the explicitly configured POST JSON field',
    () async {
      final fakeHttp = FakeProviderUsageHttpClient(
        response: const ProviderUsageHttpResponse(
          statusCode: 200,
          body: '{"remaining":"3.25"}',
        ),
      );
      final adapter = HttpJsonMappingAdapter(
        config: mappingConfig(
          method: 'POST',
          url: 'https://example.test/usage',
          credential: const HttpJsonCredentialConfig(
            field: 'apiKey',
            name: 'api_key',
            placement: HttpJsonCredentialPlacement.jsonBody,
          ),
        ),
      );

      final snapshot = await adapter.fetch(
        _provider(),
        credentials: const _Resolver(_Credentials({'apiKey': 'do-not-log'})),
        http: fakeHttp,
        now: now,
      );

      expect(snapshot.measures.single.remaining, '3.25');
      expect(fakeHttp.requests.single.method, 'POST');
      expect(
        fakeHttp.requests.single.headers['content-type'],
        'application/json',
      );
      expect(fakeHttp.requests.single.body, contains('"api_key":"do-not-log"'));
      expect(fakeHttp.requests.single.uri.query, isEmpty);
    },
  );

  test(
    'places credentials in explicitly configured headers and query params',
    () async {
      for (final placement in [
        HttpJsonCredentialPlacement.header,
        HttpJsonCredentialPlacement.query,
      ]) {
        final fakeHttp = FakeProviderUsageHttpClient(
          response: const ProviderUsageHttpResponse(
            statusCode: 200,
            body: '{"remaining":"3.25"}',
          ),
        );
        final adapter = HttpJsonMappingAdapter(
          config: mappingConfig(
            url: 'https://example.test/usage?region=us',
            credential: HttpJsonCredentialConfig(
              field: 'apiKey',
              name: 'X-API-Key',
              placement: placement,
            ),
          ),
        );

        await adapter.fetch(
          _provider(),
          credentials: const _Resolver(_Credentials({'apiKey': 'secret-key'})),
          http: fakeHttp,
          now: now,
        );

        final request = fakeHttp.requests.single;
        if (placement == HttpJsonCredentialPlacement.header) {
          expect(request.headers['X-API-Key'], 'secret-key');
          expect(request.uri.query, 'region=us');
        } else {
          expect(request.headers.containsKey('X-API-Key'), isFalse);
          expect(request.uri.queryParameters['X-API-Key'], 'secret-key');
        }
      }
    },
  );

  test('supports window paths, unit, and reset timestamps', () async {
    final adapter = HttpJsonMappingAdapter(
      config: mappingConfig(
        url: 'https://example.test/usage',
        responsePath: r'$.result',
        windows: [
          usageWindow(
            label: 'Balance',
            used: r'$.used',
            remaining: r'$.remaining',
            unit: 'credits',
            resetsAt: r'$.resetAt',
          ),
        ],
      ),
    );

    final snapshot = await adapter.fetch(
      _provider(),
      credentials: const _Resolver(null),
      http: FakeProviderUsageHttpClient(
        response: const ProviderUsageHttpResponse(
          statusCode: 200,
          body:
              '{"result":{"name":"Balance","used":"1.25","remaining":"8.75","unit":"credits","currency":"USD","resetAt":"2026-08-19T00:00:00Z"}}',
        ),
      ),
      now: now,
    );

    final measure = snapshot.measures.single;
    expect(measure.label, 'Balance');
    expect(measure.used, '1.25');
    expect(measure.remaining, '8.75');
    expect(measure.unit, 'credits');
    expect(
      measure.resetsAt,
      DateTime.parse('2026-08-19T00:00:00Z').millisecondsSinceEpoch,
    );
  });

  test('accepts integral finite numeric reset timestamps', () async {
    final snapshot =
        await HttpJsonMappingAdapter(
          config: mappingConfig(
            url: 'https://example.test/usage',
            windows: [
              usageWindow(
                remaining: r'$.remaining',
                resetsAt: r'$.resetsAt',
              ),
            ],
          ),
        ).fetch(
          _provider(),
          credentials: const _Resolver(null),
          http: FakeProviderUsageHttpClient(
            response: const ProviderUsageHttpResponse(
              statusCode: 200,
              body: '{"remaining":"1.00","resetsAt":1700000000000.0}',
            ),
          ),
          now: now,
        );

    expect(snapshot.measures.single.resetsAt, 1700000000000);
  });

  test('skips windows without numeric values', () async {
    final exactSnapshot =
        await HttpJsonMappingAdapter(
          config: mappingConfig(url: 'https://example.test/usage'),
        ).fetch(
          _provider(),
          credentials: const _Resolver(null),
          http: FakeProviderUsageHttpClient(
            response: const ProviderUsageHttpResponse(
              statusCode: 200,
              body: '{"remaining":"1.2300000000000000000001"}',
            ),
          ),
          now: now,
        );
    expect(exactSnapshot.measures.single.remaining, '1.2300000000000000000001');

    final error = await _capture(
      () =>
          HttpJsonMappingAdapter(
            config: mappingConfig(url: 'https://example.test/usage'),
          ).fetch(
            _provider(),
            credentials: const _Resolver(null),
            http: FakeProviderUsageHttpClient(
              response: const ProviderUsageHttpResponse(
                statusCode: 200,
                body: '{"remaining":"not-a-number"}',
              ),
            ),
            now: now,
          ),
    );

    expect(error, isA<ManagedProviderUsageQueryError>());
    expect(
      (error as ManagedProviderUsageQueryError).code,
      ManagedProviderUsageQueryErrorCode.responseParseFailed,
    );
  });

  test('rejects non-HTTPS non-loopback URLs before using the client', () async {
    final fakeHttp = FakeProviderUsageHttpClient(
      response: const ProviderUsageHttpResponse(statusCode: 200, body: '{}'),
    );
    final adapter = HttpJsonMappingAdapter(
      config: mappingConfig(
        url: 'http://example.test/usage',
        windows: const [],
      ),
    );

    await expectLater(
      adapter.fetch(
        _provider(),
        credentials: const _Resolver(null),
        http: fakeHttp,
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
    expect(fakeHttp.requests, isEmpty);
  });

  test('rejects endpoint userinfo and credential-bearing query data', () async {
    final credentialQueryNames = [
      'apiKey',
      'access_key',
      'accessToken',
      'authorization',
      'authToken',
      'clientSecret',
      'credential',
      'credentials',
      'key',
      'oauthToken',
      'password',
      'privateKey',
      'refreshToken',
      'secret',
      'secretKey',
      'token',
      'X-Auth-Token',
      'Bearer-Token',
    ];
    for (final url in [
      'https://user:pass@example.test/usage',
      ...credentialQueryNames.map(
        (name) => 'https://example.test/usage?$name=query-secret',
      ),
      'https://example.test/usage?value=Bearer%20query-secret',
    ]) {
      final fakeHttp = FakeProviderUsageHttpClient(
        response: const ProviderUsageHttpResponse(statusCode: 200, body: '{}'),
      );
      final error = await _capture(
        () =>
            HttpJsonMappingAdapter(
              config: mappingConfig(
                url: url,
                windows: const [],
              ),
            ).fetch(
              _provider(),
              credentials: const _Resolver(null),
              http: fakeHttp,
              now: now,
            ),
      );

      expect(error, isA<ManagedProviderUsageQueryError>());
      expect(
        (error as ManagedProviderUsageQueryError).code,
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
      expect(error.toString(), isNot(contains('query-secret')));
      expect(fakeHttp.requests, isEmpty);
    }
  });

  test('allows safe tokenCount and ordinary endpoint query mappings', () async {
    final fakeHttp = FakeProviderUsageHttpClient(
      response: const ProviderUsageHttpResponse(
        statusCode: 200,
        body: '{"remaining":"1.00"}',
      ),
    );

    await HttpJsonMappingAdapter(
      config: mappingConfig(
        url: 'https://example.test/usage?tokenCount=2&region=us',
      ),
    ).fetch(
      _provider(),
      credentials: const _Resolver(null),
      http: fakeHttp,
      now: now,
    );

    expect(fakeHttp.requests.single.uri.query, 'tokenCount=2&region=us');
  });

  test('rejects persisted providers whose unsafe URL was sanitized', () async {
    final provider = _provider().copyWith(
      endpointConfig: ManagedProviderEndpointConfig(
        url: 'https://example.test/usage?apiKey=query-secret',
        windows: const [
          ManagedProviderUsageWindow(
            label: 'Usage',
            remaining: r'$.remaining',
          ),
        ],
      ),
    );
    final fakeHttp = FakeProviderUsageHttpClient(
      response: const ProviderUsageHttpResponse(
        statusCode: 200,
        body: '{"remaining":"1.00"}',
      ),
    );

    expect(provider.endpointConfig.hadUnsafeUrl, isTrue);
    final error = await _capture(
      () => HttpJsonMappingAdapter().fetch(
        provider,
        credentials: const _Resolver(null),
        http: fakeHttp,
        now: now,
      ),
    );

    expect(error, isA<ManagedProviderUsageQueryError>());
    expect(
      (error as ManagedProviderUsageQueryError).code,
      ManagedProviderUsageQueryErrorCode.unsupported,
    );
    expect(fakeHttp.requests, isEmpty);
  });

  test('accepts parsed loopback IP variants for HTTP endpoints', () async {
    for (final url in [
      'http://127.0.0.2/usage',
      'http://[::1]/usage',
      'http://[0:0:0:0:0:0:0:1]/usage',
      'http://localhost./usage',
    ]) {
      final fakeHttp = FakeProviderUsageHttpClient(
        response: const ProviderUsageHttpResponse(
          statusCode: 200,
          body: '{"remaining":"1.00"}',
        ),
      );
      await HttpJsonMappingAdapter(
        config: mappingConfig(url: url),
      ).fetch(
        _provider(),
        credentials: const _Resolver(null),
        http: fakeHttp,
        now: now,
      );
      expect(fakeHttp.requests, hasLength(1));
    }
  });

  test('maps malformed configured paths to typed unsupported errors', () async {
    final fakeHttp = FakeProviderUsageHttpClient(
      response: const ProviderUsageHttpResponse(
        statusCode: 200,
        body: '{"data":[{"remaining":"1.00"}]}',
      ),
    );
    final error = await _capture(
      () =>
          HttpJsonMappingAdapter(
            config: mappingConfig(
              url: 'https://example.test/usage',
              windows: [usageWindow(remaining: r'$.data[0]junk')],
            ),
          ).fetch(
            _provider(),
            credentials: const _Resolver(null),
            http: fakeHttp,
            now: now,
          ),
    );

    expect(error, isA<ManagedProviderUsageQueryError>());
    expect(
      (error as ManagedProviderUsageQueryError).code,
      ManagedProviderUsageQueryErrorCode.unsupported,
    );
    expect(fakeHttp.requests, isEmpty);
  });

  test(
    'maps present malformed mapped values to response parse errors',
    () async {
      final cases = <HttpJsonMappingConfig>[
        mappingConfig(
          url: 'https://example.test/usage',
          windows: [usageWindow(remaining: r'$.remaining')],
        ),
        mappingConfig(
          url: 'https://example.test/usage',
          windows: [usageWindow(remaining: r'$.missing')],
        ),
      ];
      final bodies = [
        '{"remaining":"not-decimal"}',
        '{"remaining":"1.00"}',
      ];

      for (var i = 0; i < cases.length; i++) {
        final error = await _capture(
          () => HttpJsonMappingAdapter(config: cases[i]).fetch(
            _provider(),
            credentials: const _Resolver(null),
            http: FakeProviderUsageHttpClient(
              response: ProviderUsageHttpResponse(
                statusCode: 200,
                body: bodies[i],
              ),
            ),
            now: now,
          ),
        );
        expect(error, isA<ManagedProviderUsageQueryError>());
        expect(
          (error as ManagedProviderUsageQueryError).code,
          ManagedProviderUsageQueryErrorCode.responseParseFailed,
        );
      }
    },
  );

  test('maps missing credentials to a typed redacted error', () async {
    final adapter = HttpJsonMappingAdapter(
      config: mappingConfig(
        url: 'https://example.test/usage',
        credential: const HttpJsonCredentialConfig(field: 'apiKey'),
      ),
    );

    final error = await _capture(
      () => adapter.fetch(
        _provider(),
        credentials: const _Resolver(null),
        http: FakeProviderUsageHttpClient(
          response: const ProviderUsageHttpResponse(
            statusCode: 200,
            body: '{}',
          ),
        ),
        now: now,
      ),
    );

    expect(error, isA<ManagedProviderUsageQueryError>());
    expect(
      (error as ManagedProviderUsageQueryError).code,
      ManagedProviderUsageQueryErrorCode.missingCredential,
    );
    expect(error.toString(), isNot(contains('secret')));
  });

  test(
    'maps HTTP, network, and malformed JSON failures without response secrets',
    () async {
      final configs = [
        (
          FakeProviderUsageHttpClient(
            response: const ProviderUsageHttpResponse(
              statusCode: 401,
              body: '{"token":"response-secret"}',
            ),
          ),
          ManagedProviderUsageQueryErrorCode.authenticationFailed,
        ),
        (
          FakeProviderUsageHttpClient(
            response: const ProviderUsageHttpResponse(
              statusCode: 500,
              body: '{"token":"response-secret"}',
            ),
          ),
          ManagedProviderUsageQueryErrorCode.httpFailed,
        ),
        (
          FakeProviderUsageHttpClient(error: StateError('network secret')),
          ManagedProviderUsageQueryErrorCode.networkFailed,
        ),
        (
          FakeProviderUsageHttpClient(
            response: const ProviderUsageHttpResponse(
              statusCode: 200,
              body: 'not-json',
            ),
          ),
          ManagedProviderUsageQueryErrorCode.responseParseFailed,
        ),
      ];

      for (final item in configs) {
        final error = await _capture(
          () =>
              HttpJsonMappingAdapter(
                config: mappingConfig(url: 'https://example.test/usage'),
              ).fetch(
                _provider(),
                credentials: const _Resolver(null),
                http: item.$1,
                now: now,
              ),
        );
        expect(error, isA<ManagedProviderUsageQueryError>());
        expect((error as ManagedProviderUsageQueryError).code, item.$2);
        expect(error.toString(), isNot(contains('secret')));
        expect(error.toString(), isNot(contains('response-secret')));
      }
    },
  );

  test(
    'maps resolver and request-body construction failures to redacted errors',
    () async {
      final resolverError = await _capture(
        () =>
            HttpJsonMappingAdapter(
              config: mappingConfig(
                url: 'https://example.test/usage',
                credential: const HttpJsonCredentialConfig(field: 'apiKey'),
              ),
            ).fetch(
              _provider(),
              credentials: const _ThrowingResolver(),
              http: FakeProviderUsageHttpClient(
                response: const ProviderUsageHttpResponse(
                  statusCode: 200,
                  body: '{"remaining":"1.00"}',
                ),
              ),
              now: now,
            ),
      );
      expect(resolverError, isA<ManagedProviderUsageQueryError>());
      expect(
        (resolverError as ManagedProviderUsageQueryError).code,
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
      expect(resolverError.toString(), isNot(contains('resolver-secret')));

      final bodyError = await _capture(
        () =>
            HttpJsonMappingAdapter(
              config: mappingConfig(
                method: 'POST',
                url: 'https://example.test/usage',
                body: {'unsupported': _NonJsonValue()},
              ),
            ).fetch(
              _provider(),
              credentials: const _Resolver(null),
              http: FakeProviderUsageHttpClient(
                response: const ProviderUsageHttpResponse(
                  statusCode: 200,
                  body: '{"remaining":"1.00"}',
                ),
              ),
              now: now,
            ),
      );
      expect(bodyError, isA<ManagedProviderUsageQueryError>());
      expect(
        (bodyError as ManagedProviderUsageQueryError).code,
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
      expect(bodyError.toString(), isNot(contains('body-secret')));
    },
  );

  test(
    'validates method and credential placement before resolving credentials',
    () async {
      for (final config in [
        mappingConfig(
          method: 'PATCH',
          url: 'https://example.test/usage',
          credential: const HttpJsonCredentialConfig(field: 'apiKey'),
        ),
        mappingConfig(
          url: 'https://example.test/usage',
          credential: const HttpJsonCredentialConfig(
            field: 'apiKey',
            placement: HttpJsonCredentialPlacement.unsupported,
          ),
        ),
      ]) {
        final error = await _capture(
          () => HttpJsonMappingAdapter(config: config).fetch(
            _provider(),
            credentials: const _ThrowingResolver(),
            http: FakeProviderUsageHttpClient(
              response: const ProviderUsageHttpResponse(
                statusCode: 200,
                body: '{"remaining":"1.00"}',
              ),
            ),
            now: now,
          ),
        );
        expect(error, isA<ManagedProviderUsageQueryError>());
        expect(
          (error as ManagedProviderUsageQueryError).code,
          ManagedProviderUsageQueryErrorCode.unsupported,
        );
        expect(error.toString(), isNot(contains('resolver-secret')));
      }
    },
  );

  test(
    'rejects control characters in request headers and credentials',
    () async {
      final configs = [
        mappingConfig(
          url: 'https://example.test/usage',
          headers: {'X-Test': 'safe\r\nInjected: yes'},
        ),
        mappingConfig(
          url: 'https://example.test/usage',
          headers: {'X-Test\r\nInjected': 'safe'},
        ),
        mappingConfig(
          url: 'https://example.test/usage',
          credential: const HttpJsonCredentialConfig(
            field: 'apiKey',
            name: 'X-API\nKey',
          ),
        ),
        mappingConfig(
          url: 'https://example.test/usage',
          credential: const HttpJsonCredentialConfig(
            field: 'apiKey',
            prefix: 'Bearer\r\n',
          ),
        ),
      ];
      for (final config in configs) {
        final error = await _capture(
          () => HttpJsonMappingAdapter(config: config).fetch(
            _provider(),
            credentials: const _Resolver(_Credentials({'apiKey': 'secret'})),
            http: FakeProviderUsageHttpClient(
              response: const ProviderUsageHttpResponse(
                statusCode: 200,
                body: '{"remaining":"1.00"}',
              ),
            ),
            now: now,
          ),
        );
        expect(error, isA<ManagedProviderUsageQueryError>());
        expect(
          (error as ManagedProviderUsageQueryError).code,
          ManagedProviderUsageQueryErrorCode.unsupported,
        );
        expect(error.toString(), isNot(contains('secret')));
      }

      final valueError = await _capture(
        () =>
            HttpJsonMappingAdapter(
              config: mappingConfig(
                url: 'https://example.test/usage',
                credential: const HttpJsonCredentialConfig(field: 'apiKey'),
              ),
            ).fetch(
              _provider(),
              credentials: const _Resolver(
                _Credentials({'apiKey': 'secret\nInjected: yes'}),
              ),
              http: FakeProviderUsageHttpClient(
                response: const ProviderUsageHttpResponse(
                  statusCode: 200,
                  body: '{"remaining":"1.00"}',
                ),
              ),
              now: now,
            ),
      );
      expect(valueError, isA<ManagedProviderUsageQueryError>());
      expect(
        (valueError as ManagedProviderUsageQueryError).code,
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
      expect(valueError.toString(), isNot(contains('secret')));
    },
  );

  test(
    'fromProvider preserves and consumes safe request configuration',
    () async {
      final provider = _provider().copyWith(
        credentialRef: 'managed-provider:p1',
        endpointConfig: ManagedProviderEndpointConfig(
          url: 'https://example.test/usage?region=us',
          method: 'POST',
          credentialField: 'apiKey',
          credentialName: 'X-API-Key',
          credentialPlacement: 'header',
          credentialPrefix: 'Bearer ',
          headers: {'X-Region': 'us'},
          body: {'scope': 'all'},
          windows: const [
            ManagedProviderUsageWindow(
              label: 'Usage',
              remaining: r'$.remaining',
            ),
          ],
        ),
      );
      final fakeHttp = FakeProviderUsageHttpClient(
        response: const ProviderUsageHttpResponse(
          statusCode: 200,
          body: '{"remaining":"1.20"}',
        ),
      );

      final snapshot = await HttpJsonMappingAdapter().fetch(
        provider,
        credentials: const _Resolver(_Credentials({'apiKey': 'secret-key'})),
        http: fakeHttp,
        now: now,
      );

      expect(snapshot.measures.single.remaining, '1.20');
      expect(fakeHttp.requests.single.method, 'POST');
      expect(fakeHttp.requests.single.headers['X-Region'], 'us');
      expect(
        fakeHttp.requests.single.headers['X-API-Key'],
        'Bearer secret-key',
      );
      expect(fakeHttp.requests.single.body, contains('"scope":"all"'));
    },
  );

  test('maps named windows and skips paths that have no numbers', () async {
    final adapter = HttpJsonMappingAdapter();
    final provider = ManagedProvider(
      id: 'p1',
      name: 'Cursor',
      kind: ManagedProviderKind.subscriptionQuota,
      adapterId: 'http-json',
      endpointConfig: ManagedProviderEndpointConfig(
        url: 'https://cursor.com/api/usage-summary',
        windows: const [
          ManagedProviderUsageWindow(
            label: 'Plan',
            used: r'$.individualUsage.plan.totalPercentUsed',
            unit: '%',
            resetsAt: r'$.billingCycleEnd',
          ),
          ManagedProviderUsageWindow(
            label: 'Team',
            used: r'$.teamUsage.pooled.used',
            total: r'$.teamUsage.pooled.limit',
          ),
        ],
      ),
    );
    final snapshot = await adapter.fetch(
      provider,
      credentials: const _Resolver(null),
      http: FakeProviderUsageHttpClient(
        response: const ProviderUsageHttpResponse(
          statusCode: 200,
          body:
              '{"billingCycleEnd":"2026-04-01T00:00:00Z","individualUsage":{"plan":{"totalPercentUsed":30}}}',
        ),
      ),
      now: now,
    );
    expect(snapshot.measures, hasLength(1));
    expect(snapshot.measures.single.label, 'Plan');
    expect(snapshot.measures.single.used, '30');
    expect(snapshot.measures.single.total, '100');
    expect(snapshot.measures.single.unit, '%');
  });

  test(
    'throws responseParseFailed when all named windows are missing numbers',
    () async {
      final adapter = HttpJsonMappingAdapter();
      final provider = ManagedProvider(
        id: 'p1',
        name: 'Cursor',
        kind: ManagedProviderKind.subscriptionQuota,
        adapterId: 'http-json',
        endpointConfig: ManagedProviderEndpointConfig(
          url: 'https://cursor.com/api/usage-summary',
          
          windows: const [
            ManagedProviderUsageWindow(
              label: 'Plan',
              used: r'$.individualUsage.plan.totalPercentUsed',
              unit: '%',
            ),
            ManagedProviderUsageWindow(
              label: 'Team',
              used: r'$.teamUsage.pooled.used',
              total: r'$.teamUsage.pooled.limit',
            ),
          ],
        ),
      );
      final error = await _capture(
        () => adapter.fetch(
          provider,
          credentials: const _Resolver(null),
          http: FakeProviderUsageHttpClient(
            response: const ProviderUsageHttpResponse(
              statusCode: 200,
              body: '{"remaining":"5.00"}',
            ),
          ),
          now: now,
        ),
      );
      expect(error, isA<ManagedProviderUsageQueryError>());
      expect(
        (error as ManagedProviderUsageQueryError).code,
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    },
  );

  test('omits templated headers whose value expands empty', () async {
    final http = FakeProviderUsageHttpClient(
      response: const ProviderUsageHttpResponse(
        statusCode: 200,
        body: '{"remaining":"1"}',
      ),
    );
    await HttpJsonMappingAdapter().fetch(
      ManagedProvider(
        id: 'p1',
        name: 'Codex',
        kind: ManagedProviderKind.subscriptionQuota,
        adapterId: 'http-json',
        endpointConfig: ManagedProviderEndpointConfig(
          url: 'https://chatgpt.com/backend-api/wham/usage',
          credentialField: 'accessToken',
          credentialName: 'Authorization',
          credentialPrefix: 'Bearer ',
          windows: const [
            ManagedProviderUsageWindow(
              label: 'Usage',
              remaining: r'$.remaining',
            ),
          ],
          headers: {
            'ChatGPT-Account-Id': '{accountId}',
            'Accept': 'application/json',
          },
        ),
      ),
      credentials: const _Resolver(_Credentials({'accessToken': 'tok'})),
      http: http,
      now: now,
    );
    expect(http.requests.single.headers['Authorization'], 'Bearer tok');
    expect(http.requests.single.headers.containsKey('ChatGPT-Account-Id'), isFalse);
    expect(http.requests.single.headers['Accept'], 'application/json');
  });

  test('builds cursor cookie from cli credential source', () async {
    final http = FakeProviderUsageHttpClient(
      response: const ProviderUsageHttpResponse(
        statusCode: 200,
        body: '{"individualUsage":{"plan":{"totalPercentUsed":30}}}',
      ),
    );
    await HttpJsonMappingAdapter(
      cliCredentials: CliCredentialSourceResolver(
        readers: {
          'cursor': _CliReader(
            const _Credentials({
              'accessToken': 'jwt-token',
              'accountId': 'user',
            }),
          ),
        },
      ),
    ).fetch(
      ManagedProvider(
        id: 'p1',
        name: 'Cursor',
        kind: ManagedProviderKind.subscriptionQuota,
        adapterId: 'http-json',
        endpointConfig: ManagedProviderEndpointConfig(
          url: 'https://cursor.com/api/usage-summary',
          credentialSource: 'cli:cursor-account',
          credentialName: 'Cookie',
          credentialTemplate:
              'WorkosCursorSessionToken={accountId}::{accessToken}',
          windows: const [
            ManagedProviderUsageWindow(
              label: 'Plan',
              used: r'$.individualUsage.plan.totalPercentUsed',
              unit: '%',
            ),
          ],
        ),
      ),
      credentials: const _Resolver(null),
      http: http,
      now: now,
    );
    expect(
      http.requests.single.headers['Cookie'],
      'WorkosCursorSessionToken=user::jwt-token',
    );
  });

  test('custom provider matches cursor cookie template behavior', () async {
    final http = FakeProviderUsageHttpClient(
      response: const ProviderUsageHttpResponse(
        statusCode: 200,
        body: '{"individualUsage":{"plan":{"totalPercentUsed":30}}}',
      ),
    );
    await HttpJsonMappingAdapter(
      cliCredentials: CliCredentialSourceResolver(
        readers: {
          'cursor': _CliReader(
            const _Credentials({
              'accessToken': 'jwt-token',
              'accountId': 'user',
            }),
          ),
        },
      ),
    ).fetch(
      ManagedProvider(
        id: 'custom-cursor',
        name: 'My Cursor',
        kind: ManagedProviderKind.customHttp,
        adapterId: 'http-json',
        endpointConfig: ManagedProviderEndpointConfig(
          url: 'https://cursor.com/api/usage-summary',
          credentialSource: 'cli:cursor-account',
          credentialName: 'Cookie',
          credentialTemplate:
              'WorkosCursorSessionToken={accountId}::{accessToken}',
          windows: const [
            ManagedProviderUsageWindow(
              label: 'Plan',
              used: r'$.individualUsage.plan.totalPercentUsed',
              unit: '%',
            ),
          ],
        ),
      ),
      credentials: const _Resolver(null),
      http: http,
      now: now,
    );
    expect(
      http.requests.single.headers['Cookie'],
      'WorkosCursorSessionToken=user::jwt-token',
    );
  });

  test('cursor preset template maps Plan Auto API windows', () async {
    final preset = managedProviderPresetById('cursor')!;
    final snapshot = await HttpJsonMappingAdapter(
      cliCredentials: CliCredentialSourceResolver(
        readers: {
          'cursor': _CliReader(
            const _Credentials({
              'accessToken': 'jwt-token',
              'accountId': 'user',
            }),
          ),
        },
      ),
    ).fetch(
      preset.template.copyWith(id: 'cursor'),
      credentials: const _Resolver(null),
      http: FakeProviderUsageHttpClient(
        response: const ProviderUsageHttpResponse(
          statusCode: 200,
          body:
              '{"billingCycleEnd":"2026-04-01T00:00:00Z","individualUsage":{"plan":{"totalPercentUsed":30,"autoPercentUsed":10,"apiPercentUsed":5}}}',
        ),
      ),
      now: now,
    );

    expect(snapshot.measures.map((measure) => measure.label), [
      'Plan',
      'Auto',
      'API',
    ]);
    expect(snapshot.measures.map((measure) => measure.used), ['30', '10', '5']);
  });

  test('claude preset template maps five hour and weekly windows', () async {
    final preset = managedProviderPresetById('claude-code')!;
    final snapshot = await HttpJsonMappingAdapter(
      cliCredentials: CliCredentialSourceResolver(
        readers: {
          'claude': _CliReader(
            const _Credentials({'accessToken': 'token'}),
          ),
        },
      ),
    ).fetch(
      preset.template.copyWith(id: 'claude'),
      credentials: const _Resolver(null),
      http: FakeProviderUsageHttpClient(
        response: const ProviderUsageHttpResponse(
          statusCode: 200,
          body:
              '{"five_hour":{"utilization":20,"resets_at":"2026-04-01T00:00:00Z"},"seven_day":{"utilization":40,"resets_at":"2026-04-08T00:00:00Z"}}',
        ),
      ),
      now: now,
    );

    expect(snapshot.measures.map((measure) => measure.label), ['5h', 'Weekly']);
    expect(snapshot.measures.map((measure) => measure.used), ['20', '40']);
  });

  test('codex preset template maps primary secondary and monthly windows', () async {
    final preset = managedProviderPresetById('codex')!;
    final snapshot = await HttpJsonMappingAdapter(
      cliCredentials: CliCredentialSourceResolver(
        readers: {
          'codex': _CliReader(
            const _Credentials({
              'accessToken': 'token',
              'accountId': 'acct',
            }),
          ),
        },
      ),
    ).fetch(
      preset.template.copyWith(id: 'codex'),
      credentials: const _Resolver(null),
      http: FakeProviderUsageHttpClient(
        response: const ProviderUsageHttpResponse(
          statusCode: 200,
          body:
              '{"rate_limit":{"primary_window":{"used_percent":15,"reset_at":1711929600},"secondary_window":{"used_percent":25,"reset_at":1712534400}},"spend_control":{"individual_limit":{"used_percent":35,"reset_at":1714521600}}}',
        ),
      ),
      now: now,
    );

    expect(snapshot.measures.map((measure) => measure.label), [
      '5h',
      'Weekly',
      'Monthly',
    ]);
    expect(snapshot.measures.map((measure) => measure.used), [
      '15',
      '25',
      '35',
    ]);
  });

  test('registry rejects duplicate IDs and exposes registered adapters', () {
    final first = _Adapter('http-json');
    final second = _Adapter('http-json');
    final registry = ManagedProviderUsageRegistry([first]);

    expect(registry.adapterFor('http-json'), same(first));
    expect(registry.all, [first]);
    expect(() => registry.all.add(second), throwsUnsupportedError);
    expect(() => registry.register(second), throwsStateError);
  });
}

ManagedProvider _provider() => ManagedProvider(
  id: 'p1',
  name: 'Example',
  kind: ManagedProviderKind.customHttp,
  adapterId: 'http-json',
);

Future<Object> _capture(Future<Object> Function() action) async {
  try {
    await action();
    fail('Expected action to throw');
  } on Object catch (error) {
    return error;
  }
}

class FakeProviderUsageHttpClient implements ProviderUsageHttpClient {
  FakeProviderUsageHttpClient({this.response, this.error});

  final ProviderUsageHttpResponse? response;
  final Object? error;
  final requests = <ProviderUsageHttpRequest>[];

  @override
  Future<ProviderUsageHttpResponse> send(
    ProviderUsageHttpRequest request,
  ) async {
    requests.add(request);
    if (error != null) throw error!;
    return response!;
  }
}

class _Credentials implements ProviderCredentialScope {
  const _Credentials(this.values);

  final Map<String, String> values;

  @override
  Iterable<String> get fields => values.keys;

  @override
  bool get isEmpty => values.isEmpty;

  @override
  String? valueFor(String field) => values[field];
}

class _Resolver implements ProviderCredentialResolver {
  const _Resolver(this.scope);

  final ProviderCredentialScope? scope;

  @override
  Future<ProviderCredentialScope?> resolve(ManagedProvider provider) async =>
      scope;
}

class _ThrowingResolver implements ProviderCredentialResolver {
  const _ThrowingResolver();

  @override
  Future<ProviderCredentialScope?> resolve(ManagedProvider provider) {
    throw StateError('resolver-secret');
  }
}

class _CliReader implements OfficialSubscriptionAuthReader {
  const _CliReader(this.scope);

  final ProviderCredentialScope scope;

  @override
  Future<ProviderCredentialScope?> read(ManagedProvider provider) async =>
      scope;
}

class _NonJsonValue {
  @override
  String toString() => 'body-secret';
}

class _Adapter implements ManagedProviderUsageAdapter {
  const _Adapter(this.id);

  @override
  final String id;

  @override
  Future<ProviderUsageSnapshot> fetch(
    ManagedProvider provider, {
    required ProviderCredentialResolver credentials,
    required ProviderUsageHttpClient http,
    required DateTime now,
  }) => throw UnimplementedError();
}
