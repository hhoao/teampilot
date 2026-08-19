import 'managed_provider_usage_adapter.dart';

/// Registry for managed-provider adapters, independent from CLI providers.
class ManagedProviderUsageRegistry {
  ManagedProviderUsageRegistry([
    Iterable<ManagedProviderUsageAdapter> adapters = const [],
  ]) {
    for (final adapter in adapters) {
      register(adapter);
    }
  }

  final Map<String, ManagedProviderUsageAdapter> _adapters = {};

  void register(ManagedProviderUsageAdapter adapter) {
    final id = adapter.id.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(adapter.id, 'adapter.id', 'must not be empty');
    }
    if (_adapters.containsKey(id)) {
      throw StateError(
        'Managed provider usage adapter already registered: $id',
      );
    }
    _adapters[id] = adapter;
  }

  ManagedProviderUsageAdapter? adapterFor(String id) => _adapters[id.trim()];

  List<ManagedProviderUsageAdapter> get all =>
      List.unmodifiable(_adapters.values);
}
