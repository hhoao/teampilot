import '../../models/discoverable_member.dart';
import 'composite_expert_hub_source.dart';
import 'expert_member_resolver.dart';
import 'local_member_template_store.dart';

/// Built-in catalog key prefix — always resolvable, never cloned.
const String kBuiltinExpertKeyPrefix = 'teampilot/builtin/';

/// Result of attempting to clone one expert for a team roster slot.
class ExpertCloneOutcome {
  const ExpertCloneOutcome({required this.key, required this.cloned});

  /// The key the roster slot should reference (kept or new local key).
  final String key;

  /// True when a new local copy was created in My Experts.
  final bool cloned;
}

/// Clones a catalog expert into My Experts when missing, so a cloned team is
/// self-contained. One instance per clone run (holds the run-scoped memo).
///
/// Returns the key the slot should reference, or `null` if the expert cannot
/// be resolved (caller reports a non-blocking failure).
class ExpertCloneService {
  ExpertCloneService({
    required CompositeExpertHubSource source,
    LocalMemberTemplateStore? localStore,
  }) : _source = source,
       _localStore = localStore ?? LocalMemberTemplateStore();

  final CompositeExpertHubSource _source;
  final LocalMemberTemplateStore _localStore;

  /// Run-scoped memo: catalog key -> cloned local key (one clone per expert).
  final Map<String, String> _memo = {};

  Future<ExpertCloneOutcome?> clone({
    required String expertKey,
    String? originTeamKey,
  }) async {
    final key = expertKey.trim();
    if (key.isEmpty) return null;

    if (LocalMemberTemplateStore.isLocalKey(key)) {
      final local = await _localStore.getByKey(key);
      if (local == null) return null; // dangling local key
      return ExpertCloneOutcome(key: key, cloned: false);
    }

    if (key.startsWith(kBuiltinExpertKeyPrefix)) {
      return ExpertCloneOutcome(key: key, cloned: false);
    }

    final memoized = _memo[key];
    if (memoized != null) {
      return ExpertCloneOutcome(key: memoized, cloned: true);
    }

    final existing = await _findLocalByCatalogKey(key);
    if (existing != null) {
      _memo[key] = existing.key;
      return ExpertCloneOutcome(key: existing.key, cloned: false);
    }

    final expert = await ExpertMemberResolver.resolveMember(
      key: key,
      source: _source,
      localStore: _localStore,
    );
    if (expert == null) return null;

    final saved = await _localStore.save(
      expert.copyWith(catalogKey: key, originTeamKey: originTeamKey),
    );
    _memo[key] = saved.key;
    return ExpertCloneOutcome(key: saved.key, cloned: true);
  }

  Future<DiscoverableMember?> _findLocalByCatalogKey(String catalogKey) async {
    final locals = await _localStore.loadAll();
    for (final member in locals) {
      if (member.catalogKey == catalogKey) return member;
    }
    return null;
  }
}
