import 'package:equatable/equatable.dart';

enum CatalogResourceKind { skill, mcp, plugin, team, expert }

enum CatalogSortKey { adoption, rating, updated, published, name }

class CatalogMetrics extends Equatable {
  const CatalogMetrics({
    this.adoptionCount,
    this.rating,
    this.ratingCount,
    this.updatedAtMs,
    this.publishedAtMs,
  });

  final int? adoptionCount;
  final double? rating;
  final int? ratingCount;
  final int? updatedAtMs;
  final int? publishedAtMs;

  @override
  List<Object?> get props => [
    adoptionCount,
    rating,
    ratingCount,
    updatedAtMs,
    publishedAtMs,
  ];
}

abstract interface class CatalogEntry {
  String get id;
  CatalogResourceKind get kind;
  String get name;
  String get description;
  String? get sourceLabel;
  String? get author;
  List<String> get tags;
  CatalogMetrics get metrics;
}

abstract interface class CatalogAdapter<T> {
  CatalogEntry adapt(T item);
}

class CatalogSourceFailure {
  const CatalogSourceFailure({
    required this.sourceId,
    required this.sourceLabel,
    required this.message,
  });

  final String sourceId;
  final String sourceLabel;
  final String message;
}

class CatalogSourceResult<T> {
  CatalogSourceResult({
    required this.sourceId,
    required this.sourceLabel,
    required List<T> items,
    this.hasNext = false,
    this.failure,
  }) : items = List.unmodifiable(items);

  final String sourceId;
  final String sourceLabel;
  final List<T> items;
  final bool hasNext;
  final CatalogSourceFailure? failure;
}

class CatalogAggregate<T> {
  CatalogAggregate({
    required List<T> items,
    required Map<String, bool> hasNextBySource,
    required List<CatalogSourceFailure> failures,
  }) : items = List.unmodifiable(items),
       hasNextBySource = Map.unmodifiable(hasNextBySource),
       failures = List.unmodifiable(failures);

  final List<T> items;
  final Map<String, bool> hasNextBySource;
  final List<CatalogSourceFailure> failures;
}
