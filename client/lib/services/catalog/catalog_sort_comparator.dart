import 'package:teampilot/models/catalog/catalog_types.dart';

class CatalogSortComparator {
  const CatalogSortComparator._();

  static int compare(CatalogEntry a, CatalogEntry b, CatalogSortKey key) {
    if (key == CatalogSortKey.name) {
      final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (name != 0) return name;
      return _compareNullableNumbers(
        a.metrics.updatedAtMs,
        b.metrics.updatedAtMs,
        descending: true,
      );
    }

    final primary = _compareNullableNumbers(
      _value(a.metrics, key),
      _value(b.metrics, key),
      descending: true,
    );
    if (primary != 0) return primary;

    final updated = _compareNullableNumbers(
      a.metrics.updatedAtMs,
      b.metrics.updatedAtMs,
      descending: true,
    );
    if (updated != 0) return updated;

    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  static num? _value(CatalogMetrics metrics, CatalogSortKey key) {
    return switch (key) {
      CatalogSortKey.adoption => metrics.adoptionCount,
      CatalogSortKey.rating => metrics.rating,
      CatalogSortKey.updated => metrics.updatedAtMs,
      CatalogSortKey.published => metrics.publishedAtMs,
      CatalogSortKey.name => null,
    };
  }

  static int _compareNullableNumbers(
    num? a,
    num? b, {
    required bool descending,
  }) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;

    final result = a.compareTo(b);
    return descending ? -result : result;
  }
}
