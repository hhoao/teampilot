import '../../models/discoverable_member.dart';
import 'local_expert_store.dart';

/// Sole persistence API for user-saved local experts (UI and AI New Team).
class LocalExpertWriter {
  LocalExpertWriter({LocalExpertStore? store})
    : _store = store ?? LocalExpertStore();

  final LocalExpertStore _store;

  Future<DiscoverableMember> save(DiscoverableMember member) =>
      _store.save(member);

  Future<List<DiscoverableMember>> loadAll() => _store.loadAll();

  Future<DiscoverableMember?> getByKey(String key) => _store.getByKey(key);

  Future<void> delete(String key) => _store.delete(key);
}
