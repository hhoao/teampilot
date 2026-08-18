import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';

void main() {
  test('stale snapshot retains measures and never serializes secrets', () {
    final snapshot = ProviderUsageSnapshot(
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

  test('skips measures with non-finite or fractional reset timestamps', () {
    final snapshot = ProviderUsageSnapshot.fromJson({
      'providerId': 'p1',
      'status': 'stale',
      'measures': [
        {
          'label': 'Valid',
          'kind': 'quota',
          'remaining': '1.00',
          'resetsAt': 100,
        },
        {
          'label': 'NaN',
          'kind': 'quota',
          'remaining': '2.00',
          'resetsAt': double.nan,
        },
        {
          'label': 'Infinity',
          'kind': 'quota',
          'remaining': '3.00',
          'resetsAt': double.infinity,
        },
        {
          'label': 'Fractional',
          'kind': 'quota',
          'remaining': '4.00',
          'resetsAt': 1.5,
        },
      ],
    });

    expect(snapshot.measures, hasLength(1));
    expect(snapshot.measures.single.resetsAt, 100);
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

  test('filters credential aliases but preserves safe future fields', () {
    final snapshot = ProviderUsageSnapshot(
      providerId: 'p1',
      status: ProviderUsageStatus.error,
      unknownFields: {
        'key': 'secret',
        'privateKey': 'secret',
        'credential': 'secret',
        'client secret': 'secret',
        'tokenCount': 3,
        'future': {'safe': true, 'tokenCount': 4},
      },
    );

    final json = snapshot.toJson();

    expect(json.containsKey('key'), isFalse);
    expect(json.containsKey('privateKey'), isFalse);
    expect(json.containsKey('credential'), isFalse);
    expect(json.containsKey('client secret'), isFalse);
    expect(json['tokenCount'], 3);
    expect(json['future'], {'safe': true, 'tokenCount': 4});
  });

  test('does not accept credential material in error messages', () {
    final snapshot = ProviderUsageSnapshot(
      providerId: 'p1',
      status: ProviderUsageStatus.error,
      lastErrorMessage: 'request failed: key=super-secret',
    );

    expect(snapshot.lastErrorMessage, isNull);
    expect(snapshot.toJson().containsKey('lastErrorMessage'), isFalse);
    expect(
      ProviderUsageSnapshot.fromJson({
        'providerId': 'p1',
        'status': 'error',
        'lastErrorMessage': 'Authorization: Bearer super-secret',
      }).lastErrorMessage,
      isNull,
    );

    final whitespaceSeparated = ProviderUsageSnapshot(
      providerId: 'p1',
      status: ProviderUsageStatus.error,
      lastErrorMessage: 'request failed: client secret: super-secret',
    );
    final safeText = ProviderUsageSnapshot(
      providerId: 'p1',
      status: ProviderUsageStatus.error,
      lastErrorMessage: 'client secret count: 2',
    );

    expect(whitespaceSeparated.lastErrorMessage, isNull);
    expect(safeText.lastErrorMessage, 'client secret count: 2');
  });

  test('redacts JSON, headers, URLs, and nested credential strings', () {
    final snapshot = ProviderUsageSnapshot.fromJson({
      'providerId': 'p1',
      'status': 'error',
      'lastErrorMessage': '{"apiKey":"secret","tokenCount":2}',
      'headers': {
        'Authorization': 'Bearer header-secret',
        'Accept': 'application/json',
      },
      'requestUrl': 'https://example.test/usage?apiKey=url-secret',
      'nested': {
        'safe': 'tokenCount=2',
        'credentials': {'client secret': 'nested-secret'},
      },
    });
    final json = snapshot.toJson();
    final encoded = jsonEncode(json);

    expect(encoded, isNot(contains('secret')));
    expect(json['headers'], {'Accept': 'application/json'});
    expect(json['nested'], {'safe': 'tokenCount=2'});
    expect(json['lastErrorMessage'], contains('tokenCount'));
  });

  test('rejects non-finite and fractional fetched and stale timestamps', () {
    for (final field in ['fetchedAt', 'staleAt']) {
      for (final value in [double.nan, double.infinity, 1.5]) {
        expect(
          () => ProviderUsageSnapshot.fromJson({
            'providerId': 'p1',
            'status': 'ready',
            field: value,
          }),
          throwsFormatException,
          reason: '$field=$value',
        );
      }
    }
  });

  test('deep-copies and freezes measures and unknown fields', () {
    final measures = <ProviderUsageMeasure>[
      ProviderUsageMeasure(
        label: 'Balance',
        kind: ProviderUsageMeasureKind.balance,
        remaining: '1.00',
      ),
    ];
    final unknown = <String, Object?>{
      'future': <String, Object?>{
        'values': <Object?>[1],
      },
    };
    final snapshot = ProviderUsageSnapshot(
      providerId: 'p1',
      status: ProviderUsageStatus.ready,
      measures: measures,
      unknownFields: unknown,
    );
    final copy = snapshot.copyWith(measures: measures, unknownFields: unknown);

    measures.clear();
    (unknown['future'] as Map<String, Object?>)['values'] = <Object?>[2];

    expect(snapshot.measures, hasLength(1));
    expect(copy.measures, hasLength(1));
    expect(snapshot.unknownFields['future'], {
      'values': [1],
    });
    expect(
      () => snapshot.measures.add(
        ProviderUsageMeasure(
          label: 'Other',
          kind: ProviderUsageMeasureKind.quota,
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test(
    'direct measure construction validates decimals and clamps percentages',
    () {
      expect(
        () => ProviderUsageMeasure(
          label: 'Bad',
          kind: ProviderUsageMeasureKind.balance,
          remaining: 'NaN',
        ),
        throwsFormatException,
      );
      expect(
        () => ProviderUsageMeasure(
          label: 'Bad',
          kind: ProviderUsageMeasureKind.balance,
          remaining: '1e2',
        ),
        throwsFormatException,
      );

      final measure = ProviderUsageMeasure(
        label: 'Window',
        kind: ProviderUsageMeasureKind.quota,
        used: '125.00',
        unit: '%',
      );
      final copied = measure.copyWith(remaining: '-1.00');

      expect(measure.used, '100');
      expect(copied.remaining, '0');
    },
  );
}
