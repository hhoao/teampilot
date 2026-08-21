import '../../models/managed_provider.dart';
import '../../models/provider_usage_snapshot.dart';

/// Picks which enabled Managed Provider the status bar should show.
String? resolveManagedProviderUsageFocus({
  required List<ManagedProvider> enabledProviders,
  required Map<String, ProviderUsageSnapshot> currentSnapshots,
  required Map<String, ProviderUsageSnapshot> previousSnapshots,
  String? currentFocusId,
}) {
  if (enabledProviders.isEmpty) return null;

  final enabledIds = <String>{
    for (final p in enabledProviders) p.id,
  };

  final changedIds = <String>[];
  for (final provider in enabledProviders) {
    final id = provider.id;
    final current = currentSnapshots[id];
    final previous = previousSnapshots[id];
    if (_snapshotChanged(previous, current)) {
      changedIds.add(id);
    }
  }

  if (changedIds.isNotEmpty) {
    return _pickByFetchedAtThenListOrder(
      candidates: changedIds,
      enabledProviders: enabledProviders,
      snapshots: currentSnapshots,
    );
  }

  final focus = currentFocusId?.trim();
  if (focus != null && focus.isNotEmpty && enabledIds.contains(focus)) {
    return focus;
  }

  return _coldStartFocus(
    enabledProviders: enabledProviders,
    snapshots: currentSnapshots,
  );
}

String _coldStartFocus({
  required List<ManagedProvider> enabledProviders,
  required Map<String, ProviderUsageSnapshot> snapshots,
}) {
  final withSnapshots = <String>[
    for (final p in enabledProviders)
      if (snapshots.containsKey(p.id)) p.id,
  ];
  if (withSnapshots.isEmpty) return enabledProviders.first.id;
  return _pickByFetchedAtThenListOrder(
    candidates: withSnapshots,
    enabledProviders: enabledProviders,
    snapshots: snapshots,
  );
}

String _pickByFetchedAtThenListOrder({
  required List<String> candidates,
  required List<ManagedProvider> enabledProviders,
  required Map<String, ProviderUsageSnapshot> snapshots,
}) {
  final order = <String, int>{
    for (var i = 0; i < enabledProviders.length; i++)
      enabledProviders[i].id: i,
  };
  final sorted = [...candidates]..sort((a, b) {
    final fa = snapshots[a]?.fetchedAt ?? -1;
    final fb = snapshots[b]?.fetchedAt ?? -1;
    final byFetched = fa.compareTo(fb);
    if (byFetched != 0) return byFetched;
    return (order[a] ?? 0).compareTo(order[b] ?? 0);
  });
  return sorted.last;
}

bool _snapshotChanged(
  ProviderUsageSnapshot? previous,
  ProviderUsageSnapshot? current,
) {
  if (current == null) return false;
  if (previous == null) return true;
  if (previous.status != current.status) return true;
  return !_primaryMeasuresEqual(
    previous.measures.isEmpty ? null : previous.measures.first,
    current.measures.isEmpty ? null : current.measures.first,
  );
}

bool _primaryMeasuresEqual(
  ProviderUsageMeasure? a,
  ProviderUsageMeasure? b,
) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  return a.remaining == b.remaining &&
      a.used == b.used &&
      a.total == b.total &&
      a.unit == b.unit &&
      a.currency == b.currency;
}
