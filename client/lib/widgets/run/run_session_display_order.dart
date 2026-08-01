/// Merges a preferred display-order id list with the live [items] sequence.
///
/// Ids still present keep relative order from [orderIds]; new ids append in
/// [items] encounter order. Stale ids in [orderIds] are dropped.
List<T> mergeDisplayOrderIds<T>({
  required List<T> items,
  required String Function(T) idOf,
  required List<String> orderIds,
}) {
  if (items.isEmpty) return <T>[];
  if (orderIds.isEmpty) return List<T>.of(items);

  final byId = <String, T>{for (final item in items) idOf(item): item};
  final result = <T>[];
  final seen = <String>{};
  for (final id in orderIds) {
    final item = byId[id];
    if (item == null) continue;
    result.add(item);
    seen.add(id);
  }
  for (final item in items) {
    final id = idOf(item);
    if (seen.add(id)) result.add(item);
  }
  return result;
}
