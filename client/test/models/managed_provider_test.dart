import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';

void main() {
  test('ManagedProvider round-trips without a CLI field', () {
    final p = ManagedProvider(
      id: 'p1',
      name: 'Example',
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'http-json',
      credentialRef: 'managed-provider:p1',
    );

    final json = p.toJson();

    expect(json.containsKey('cli'), isFalse);
    expect(ManagedProvider.fromJson(json), p);
  });

  test('preserves schema version and unknown fields', () {
    final provider = ManagedProvider.fromJson({
      'schemaVersion': 7,
      'id': 'p1',
      'name': 'Example',
      'kind': 'subscriptionQuota',
      'adapterId': 'official',
      'credentialRef': 'managed-provider:p1',
      'futureField': {'enabled': true},
    });

    final json = provider.toJson();

    expect(provider.schemaVersion, 7);
    expect(provider.unknownFields['futureField'], {'enabled': true});
    expect(json['schemaVersion'], 7);
    expect(json['futureField'], {'enabled': true});
  });

  test('unknown provider kind falls back to unknown', () {
    final provider = ManagedProvider.fromJson({
      'id': 'p1',
      'name': 'Example',
      'kind': 'futureKind',
      'adapterId': 'adapter',
      'credentialRef': 'ref',
    });

    expect(provider.kind, ManagedProviderKind.unknown);
    expect(provider.toJson()['kind'], 'unknown');
  });

  test('round-trips endpoint, brand, and display configuration', () {
    final provider = ManagedProvider(
      id: 'p1',
      name: 'Example',
      brand: ManagedProviderBrand(
        name: 'Example Cloud',
        iconUrl: 'https://example.test/icon.svg',
      ),
      websiteUrl: 'https://example.test',
      kind: ManagedProviderKind.customHttp,
      adapterId: 'http-json',
      endpointConfig: ManagedProviderEndpointConfig(
        url: 'https://example.test/usage',
        method: 'POST',
        responsePath: 'data.usage',
      ),
      displayConfig: ManagedProviderDisplayConfig(
        currency: 'USD',
        unit: 'credits',
        decimalPlaces: 2,
      ),
      credentialRef: 'managed-provider:p1',
    );

    expect(ManagedProvider.fromJson(provider.toJson()), provider);
  });

  test('deep-copies and freezes caller-provided provider collections', () {
    final mapping = <String, Object?>{
      'token': 'data.token',
      'nested': <String, Object?>{'value': 1},
    };
    final unknown = <String, Object?>{
      'safe': <String, Object?>{
        'items': <Object?>[1],
      },
    };
    final provider = ManagedProvider(
      id: 'p1',
      name: 'Example',
      kind: ManagedProviderKind.customHttp,
      adapterId: 'http-json',
      endpointConfig: ManagedProviderEndpointConfig(fieldMappings: mapping),
      unknownFields: unknown,
    );

    (mapping['nested'] as Map<String, Object?>)['value'] = 2;
    (unknown['safe'] as Map<String, Object?>)['items'] = <Object?>[2];

    expect(provider.endpointConfig.fieldMappings['nested'], {'value': 1});
    expect(provider.unknownFields['safe'], {
      'items': [1],
    });
    expect(
      () => provider.endpointConfig.fieldMappings['new'] = 'value',
      throwsUnsupportedError,
    );
    expect(
      () => provider.unknownFields['new'] = 'value',
      throwsUnsupportedError,
    );
  });

  test('copyWith deep-copies replacement collections', () {
    final unknown = <String, Object?>{
      'future': <String, Object?>{'enabled': true},
    };
    final provider = ManagedProvider(
      id: 'p1',
      name: 'Example',
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'adapter',
    ).copyWith(unknownFields: unknown);

    (unknown['future'] as Map<String, Object?>)['enabled'] = false;

    expect(provider.unknownFields['future'], {'enabled': true});
  });

  test('preserves safe future mapping keys while avoiding a CLI field', () {
    final config = ManagedProviderEndpointConfig(
      fieldMappings: {
        'token': 'data.token',
        'tokenCount': 'token',
        'apiKey': 'secret',
        'Authorization': 'Bearer secret',
        'client secret': 'secret',
        'json': '{"apiKey":"secret"}',
        'nested': {
          'privateKey': 'secret',
          'credential': 'secret',
          'safe': 'data.safe',
        },
      },
    );
    final json = config.toJson();

    expect(json['fieldMappings'], {
      'token': 'data.token',
      'tokenCount': 'token',
      'nested': {'safe': 'data.safe'},
    });
  });

  test('redacts bearer credentials while preserving safe future values', () {
    final config = ManagedProviderEndpointConfig(
      fieldMappings: {'safe': 'token', 'bearer': 'Bearer mapping-secret'},
    );
    final provider = ManagedProvider(
      id: 'p1',
      name: 'Example',
      kind: ManagedProviderKind.customHttp,
      adapterId: 'adapter',
      endpointConfig: config,
      unknownFields: {
        'futureCredential': 'Bearer provider-secret',
        'futureList': ['Bearer list-secret', 'safe'],
        'safeFuture': 'future value',
      },
    );

    final json = provider.toJson();
    final encoded = jsonEncode(json);

    expect(encoded, isNot(contains('secret')));
    expect((json['endpointConfig'] as Map)['fieldMappings'], {'safe': 'token'});
    expect(json['safeFuture'], 'future value');
    expect(json.containsKey('futureCredential'), isFalse);
    expect(json['futureList'], [null, 'safe']);
    expect(config.fieldMappings['safe'], 'token');
    expect(config.fieldMappings.containsKey('bearer'), isFalse);
  });

  test('sanitizes endpoint URL credentials while preserving safe URLs', () {
    final unsafe = ManagedProvider(
      id: 'p1',
      name: 'Example',
      kind: ManagedProviderKind.customHttp,
      adapterId: 'adapter',
      credentialRef: 'managed-provider:p1',
      endpointConfig: ManagedProviderEndpointConfig(
        url:
            'https://user:pass@example.test/usage?apiKey=query-secret&tokenCount=2#clientSecret=fragment-secret',
      ),
    );
    final safe = ManagedProviderEndpointConfig(
      url: 'https://example.test/usage?region=us#overview',
    );

    expect(
      unsafe.endpointConfig.url,
      'https://example.test/usage?tokenCount=2',
    );
    expect(
      (unsafe.toJson()['endpointConfig'] as Map)['url'],
      'https://example.test/usage?tokenCount=2',
    );
    expect(safe.url, 'https://example.test/usage?region=us#overview');
  });

  test('sanitizes known provider strings but preserves ordinary text', () {
    final provider = ManagedProvider(
      id: 'p1',
      name: 'Authorization: Bearer provider-secret',
      kind: ManagedProviderKind.customHttp,
      adapterId: 'adapter',
      websiteUrl: 'https://user:pass@example.test',
      brand: ManagedProviderBrand(
        name: 'Bearer brand-secret',
        iconUrl: 'Authorization: Bearer icon-secret',
        iconColor: 'blue',
      ),
    );

    final json = provider.toJson();
    final encoded = jsonEncode(json);

    expect(encoded, isNot(contains('secret')));
    expect(json['name'], isEmpty);
    expect(json['websiteUrl'], 'https://example.test');
    expect((json['brand'] as Map)['name'], isEmpty);
    expect((json['brand'] as Map)['iconColor'], 'blue');
  });

  test('filters nested cli mapping keys', () {
    final config = ManagedProviderEndpointConfig(
      fieldMappings: {
        'nested': {'cli': 'claude', 'safe': 'data.safe'},
      },
    );

    expect(config.toJson()['fieldMappings'], {
      'nested': {'safe': 'data.safe'},
    });
  });

  test('uses safe defaults for malformed provider numeric JSON', () {
    for (final value in [double.nan, double.infinity, 1.5]) {
      final provider = ManagedProvider.fromJson({
        'id': 'p1',
        'name': 'Example',
        'kind': 'customHttp',
        'adapterId': 'adapter',
        'createdAt': value,
        'updatedAt': value,
        'schemaVersion': value,
        'displayConfig': {'decimalPlaces': value},
      });

      expect(provider.createdAt, 0);
      expect(provider.updatedAt, 0);
      expect(provider.schemaVersion, 1);
      expect(provider.displayConfig.decimalPlaces, isNull);
    }
  });
}
