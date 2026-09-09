import '../../models/discoverable_member.dart';
import 'expert_hub_catalog.dart';
import 'local_expert_store.dart';

/// Sole persistence API for user-saved local experts (UI and AI New Team).
class LocalExpertWriter {
  LocalExpertWriter({
    required LocalExpertStore store,
    ExpertHubCatalog? catalog,
  }) : _store = store,
       _catalog = catalog;

  final LocalExpertStore _store;

  /// Shared catalog snapshot invalidated after a write so the mutated local
  /// expert shadows the catalog on the next resolve.
  final ExpertHubCatalog? _catalog;

  Future<DiscoverableMember> save(DiscoverableMember member) async {
    final saved = await _store.save(member);
    _catalog?.invalidate();
    return saved;
  }

  Future<List<DiscoverableMember>> loadAll() => _store.loadAll();

  Future<DiscoverableMember?> getByKey(String key) => _store.getByKey(key);

  Future<void> delete(String key) async {
    await _store.delete(key);
    _catalog?.invalidate();
  }
}
