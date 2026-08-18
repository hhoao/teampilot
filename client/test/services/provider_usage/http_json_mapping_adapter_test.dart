import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/services/provider_usage/adapters/http_json_mapping_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_registry.dart';

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
        config: const HttpJsonMappingConfig(
          method: 'GET',
          url: 'https://example.test/v1/balance',
          measuresPath: r'$.data',
          labelPath: r'$.planName',
          remainingPath: r'$.remaining',
          totalPath: r'$.total',
          unitPath: r'$.unit',
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
    'places an API key in the explicitly configured POST JSON field',
    () async {
      final fakeHttp = FakeProviderUsageHttpClient(
        response: const ProviderUsageHttpResponse(
          statusCode: 200,
          body: '{"remaining":"3.25"}',
        ),
      );
      final adapter = HttpJsonMappingAdapter(
        config: const HttpJsonMappingConfig(
          method: 'POST',
          url: 'https://example.test/usage',
          credential: HttpJsonCredentialConfig(
            field: 'apiKey',
            name: 'api_key',
            placement: HttpJsonCredentialPlacement.jsonBody,
          ),
          labelPath: r'$.label',
          remainingPath: r'$.remaining',
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

  test('supports scalar paths, unit, currency, and reset timestamps', () async {
    final adapter = HttpJsonMappingAdapter(
      config: const HttpJsonMappingConfig(
        method: 'GET',
        url: 'https://example.test/usage',
        responsePath: r'$.result',
        labelPath: r'$.name',
        usedPath: r'$.used',
        remainingPath: r'$.remaining',
        unitPath: r'$.unit',
        currencyPath: r'$.currency',
        resetsAtPath: r'$.resetAt',
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
    expect(measure.currency, 'USD');
    expect(
      measure.resetsAt,
      DateTime.parse('2026-08-19T00:00:00Z').millisecondsSinceEpoch,
    );
  });

  test('keeps a measure when an optional mapped field is absent', () async {
    final adapter = HttpJsonMappingAdapter(
      config: const HttpJsonMappingConfig(
        method: 'GET',
        url: 'https://example.test/usage',
        labelPath: r'$.label',
        remainingPath: r'$.remaining',
        totalPath: r'$.missingTotal',
        currencyPath: r'$.missingCurrency',
      ),
    );

    final snapshot = await adapter.fetch(
      _provider(),
      credentials: const _Resolver(null),
      http: FakeProviderUsageHttpClient(
        response: const ProviderUsageHttpResponse(
          statusCode: 200,
          body: '{"label":"Balance","remaining":"4.00"}',
        ),
      ),
      now: now,
    );

    expect(snapshot.measures.single.remaining, '4.00');
    expect(snapshot.measures.single.total, isNull);
    expect(snapshot.measures.single.currency, isNull);
  });

  test('rejects non-HTTPS non-loopback URLs before using the client', () async {
    final fakeHttp = FakeProviderUsageHttpClient(
      response: const ProviderUsageHttpResponse(statusCode: 200, body: '{}'),
    );
    final adapter = HttpJsonMappingAdapter(
      config: const HttpJsonMappingConfig(
        method: 'GET',
        url: 'http://example.test/usage',
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

  test('maps missing credentials to a typed redacted error', () async {
    final adapter = HttpJsonMappingAdapter(
      config: const HttpJsonMappingConfig(
        method: 'GET',
        url: 'https://example.test/usage',
        credential: HttpJsonCredentialConfig(field: 'apiKey'),
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
                config: const HttpJsonMappingConfig(
                  method: 'GET',
                  url: 'https://example.test/usage',
                ),
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

  test('registry rejects duplicate IDs and exposes registered adapters', () {
    final first = _Adapter('http-json');
    final second = _Adapter('http-json');
    final registry = ManagedProviderUsageRegistry([first]);

    expect(registry.adapterFor('http-json'), same(first));
    expect(registry.all, [first]);
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
