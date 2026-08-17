import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/services/catalog/catalog_sort_comparator.dart';

void main() {
  test('sorts adoption descending, null last, then updated and name', () {
    final entries = [
      _entry('zulu', adoption: 10, updated: 100),
      _entry('Alpha', adoption: 10, updated: 200),
      _entry('missing', updated: 999),
      _entry('bravo', adoption: 20, updated: 50),
    ];

    entries.sort(
      (a, b) => CatalogSortComparator.compare(a, b, CatalogSortKey.adoption),
    );

    expect(entries.map((entry) => entry.id), [
      'bravo',
      'Alpha',
      'zulu',
      'missing',
    ]);
  });

  test(
    'sorts rating, updated, and published values descending with null last',
    () {
      final ratingEntries = [
        _entry('no-rating', updated: 1),
        _entry('low', rating: 2.5, updated: 1),
        _entry('high', rating: 4.8, updated: 1),
      ];
      final updatedEntries = [
        _entry('no-updated'),
        _entry('old', updated: 10),
        _entry('new', updated: 20),
      ];
      final publishedEntries = [
        _entry('no-published'),
        _entry('old', published: 10),
        _entry('new', published: 20),
      ];

      _sort(ratingEntries, CatalogSortKey.rating);
      _sort(updatedEntries, CatalogSortKey.updated);
      _sort(publishedEntries, CatalogSortKey.published);

      expect(ratingEntries.map((entry) => entry.id), [
        'high',
        'low',
        'no-rating',
      ]);
      expect(updatedEntries.map((entry) => entry.id), [
        'new',
        'old',
        'no-updated',
      ]);
      expect(publishedEntries.map((entry) => entry.id), [
        'new',
        'old',
        'no-published',
      ]);
    },
  );

  test('sorts names case-insensitively and uses updated as the tie-break', () {
    final entries = [
      _entry('zulu', updated: 10),
      _entry('ALPHA', updated: 10),
      _entry('alpha', updated: 20),
    ];

    _sort(entries, CatalogSortKey.name);

    expect(entries.map((entry) => entry.id), ['alpha', 'ALPHA', 'zulu']);
  });
}

void _sort(List<CatalogEntry> entries, CatalogSortKey key) {
  entries.sort((a, b) => CatalogSortComparator.compare(a, b, key));
}

CatalogEntry _entry(
  String id, {
  int? adoption,
  double? rating,
  int? ratingCount,
  int? updated,
  int? published,
}) {
  return _TestCatalogEntry(
    id: id,
    metrics: CatalogMetrics(
      adoptionCount: adoption,
      rating: rating,
      ratingCount: ratingCount,
      updatedAtMs: updated,
      publishedAtMs: published,
    ),
  );
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
