import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';

void main() {
  test('stale snapshot retains measures and never serializes secrets', () {
    const snapshot = ProviderUsageSnapshot(
      providerId: 'p1',
      status: ProviderUsageStatus.stale,
      measures: [
        ProviderUsageMeasure(
          label: 'Balance',
          kind: ProviderUsageMeasureKind.balance,
          remaining: '12.50',
          unit: 'USD',
        ),
      ],
      fetchedAt: 100,
      staleAt: 200,
      lastErrorCode: 'networkFailed',
    );

    final json = snapshot.toJson();

    expect(json['measures'], isNotEmpty);
    expect(json.containsKey('apiKey'), isFalse);
    expect(ProviderUsageSnapshot.fromJson(json), snapshot);
  });

  test('preserves schema version and unknown fields', () {
    final snapshot = ProviderUsageSnapshot.fromJson({
      'schemaVersion': 3,
      'providerId': 'p1',
      'status': 'ready',
      'measures': const [],
      'futureField': 'preserve me',
    });

    expect(snapshot.schemaVersion, 3);
    expect(snapshot.toJson()['futureField'], 'preserve me');
  });

  test('unknown status and measure kind use unknown enum values', () {
    final snapshot = ProviderUsageSnapshot.fromJson({
      'providerId': 'p1',
      'status': 'futureStatus',
      'measures': [
        {'label': 'Unknown', 'kind': 'futureMeasure', 'remaining': '1.00'},
      ],
    });

    expect(snapshot.status, ProviderUsageStatus.unknown);
    expect(snapshot.measures.single.kind, ProviderUsageMeasureKind.unknown);
  });

  test('skips malformed individual measures while retaining valid ones', () {
    final snapshot = ProviderUsageSnapshot.fromJson({
      'providerId': 'p1',
      'status': 'stale',
      'measures': [
        {
          'label': 'Balance',
          'kind': 'balance',
          'remaining': '12.50',
          'unit': 'USD',
        },
        {'label': 'Broken', 'kind': 'quota', 'remaining': 12.5},
        'not a measure',
      ],
    });

    expect(snapshot.measures, hasLength(1));
    expect(snapshot.measures.single.label, 'Balance');
  });

  test('keeps monetary decimal strings and clamps percentage values', () {
    final snapshot = ProviderUsageSnapshot.fromJson({
      'providerId': 'p1',
      'status': 'ready',
      'measures': [
        {
          'label': 'Window',
          'kind': 'quota',
          'total': '100.00',
          'used': '101.25',
          'remaining': '-2.50',
          'unit': '%',
        },
        {
          'label': 'Money',
          'kind': 'balance',
          'remaining': '0.10',
          'unit': 'USD',
        },
      ],
    });

    final window = snapshot.measures.first;
    final money = snapshot.measures.last;
    expect(window.total, '100.00');
    expect(window.used, '100');
    expect(window.remaining, '0');
    expect(money.remaining, '0.10');
    expect(
      snapshot.toJson()['measures'],
      contains(isA<Map<String, Object?>>()),
    );
  });

  test('snapshot ignores credential material on input and output', () {
    final snapshot = ProviderUsageSnapshot.fromJson({
      'providerId': 'p1',
      'status': 'error',
      'measures': const [],
      'apiKey': 'secret',
      'accessToken': 'secret',
      'future': {'token': 'secret', 'safe': true},
    });

    final json = snapshot.toJson();

    expect(json.containsKey('apiKey'), isFalse);
    expect(json.containsKey('accessToken'), isFalse);
    expect(json.containsKey('future'), isTrue);
    expect(json['future'], {'safe': true});
  });
}
