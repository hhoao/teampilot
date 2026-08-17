import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/services/catalog/catalog_source_aggregation.dart';

void main() {
  test('merges sorted items, has-next flags, and every source failure', () {
    final aggregate = CatalogSourceAggregator.merge<String>(
      [
        CatalogSourceResult<String>(
          sourceId: 'source-a',
          sourceLabel: 'Source A',
          items: const ['small', 'large'],
          hasNext: true,
        ),
        CatalogSourceResult<String>(
          sourceId: 'source-b',
          sourceLabel: 'Source B',
          items: const ['medium'],
          failure: const CatalogSourceFailure(
            sourceId: 'source-b',
            sourceLabel: 'Source B',
            message: 'temporarily unavailable',
          ),
        ),
        CatalogSourceResult<String>(
          sourceId: 'source-c',
          sourceLabel: 'Source C',
          items: const [],
          failure: const CatalogSourceFailure(
            sourceId: 'source-c',
            sourceLabel: 'Source C',
            message: 'timeout',
          ),
        ),
      ],
      _StringCatalogAdapter(),
      CatalogSortKey.adoption,
    );

    expect(aggregate.items, ['large', 'medium', 'small']);
    expect(aggregate.hasNextBySource, {
      'source-a': true,
      'source-b': false,
      'source-c': false,
    });
    expect(aggregate.failures.map((failure) => failure.sourceId), [
      'source-b',
      'source-c',
    ]);
  });
}

class _StringCatalogAdapter implements CatalogAdapter<String> {
  @override
  CatalogEntry adapt(String item) {
    return _TestCatalogEntry(
      id: item,
      metrics: CatalogMetrics(
        adoptionCount: switch (item) {
          'large' => 30,
          'medium' => 20,
          _ => 10,
        },
      ),
    );
  }
}

class _TestCatalogEntry implements CatalogEntry {
  _TestCatalogEntry({required this.id, required this.metrics});

  @override
  final String id;

  @override
  final CatalogMetrics metrics;

  @override
  CatalogResourceKind get kind => CatalogResourceKind.skill;

  @override
  String get name => id;

  @override
  String get description => '';

  @override
  String? get sourceLabel => null;

  @override
  String? get author => null;

  @override
  List<String> get tags => const [];
}
