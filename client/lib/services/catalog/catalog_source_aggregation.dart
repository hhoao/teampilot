import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/services/catalog/catalog_sort_comparator.dart';

class CatalogSourceAggregator {
  const CatalogSourceAggregator._();

  static CatalogAggregate<T> merge<T>(
    Iterable<CatalogSourceResult<T>> results,
    CatalogAdapter<T> adapter,
    CatalogSortKey sort,
  ) {
    final adaptedItems = <_AdaptedCatalogItem<T>>[];
    final hasNextBySource = <String, bool>{};
    final failures = <CatalogSourceFailure>[];

    for (final result in results) {
      hasNextBySource[result.sourceId] = result.hasNext;
      if (result.failure != null) failures.add(result.failure!);

      for (final item in result.items) {
        adaptedItems.add(
          _AdaptedCatalogItem(item: item, entry: adapter.adapt(item)),
        );
      }
    }

    adaptedItems.sort(
      (a, b) => CatalogSortComparator.compare(a.entry, b.entry, sort),
    );

    return CatalogAggregate<T>(
      items: adaptedItems.map((item) => item.item).toList(),
      hasNextBySource: hasNextBySource,
      failures: failures,
    );
  }
}

class _AdaptedCatalogItem<T> {
  const _AdaptedCatalogItem({required this.item, required this.entry});

  final T item;
  final CatalogEntry entry;
}
