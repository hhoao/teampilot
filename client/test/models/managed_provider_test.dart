import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';

void main() {
  test('ManagedProvider round-trips without a CLI field', () {
    const p = ManagedProvider(
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
    const provider = ManagedProvider(
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
}
