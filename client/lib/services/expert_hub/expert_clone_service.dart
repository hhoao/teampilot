import '../../models/discoverable_member.dart';
import 'composite_expert_hub_source.dart';
import 'expert_member_resolver.dart';
import 'local_expert_store.dart';

/// Built-in catalog key prefix — always resolvable, never cloned.
const String kBuiltinExpertKeyPrefix = 'teampilot/builtin/';

/// Result of attempting to clone one expert for a team roster slot.
class ExpertCloneOutcome {
  const ExpertCloneOutcome({required this.cloned});

  /// True when a new local clone was created in My Experts.
  final bool cloned;
}

/// Clones a catalog expert into My Experts under its catalog key, so a cloned
/// team is self-contained (the local clone shadows the catalog entry at
/// resolution). Stateless singleton: dedup is an O(1) key-existence check.
///
/// Returns [ExpertCloneOutcome.cloned] `false` for already-cloned or built-in
/// experts, or `null` if the expert cannot be resolved (caller reports a
/// non-blocking failure).
class ExpertCloneService {
  ExpertCloneService({
    required CompositeExpertHubSource source,
    LocalExpertStore? store,
  }) : _source = source,
       _store = store ?? LocalExpertStore();

  final CompositeExpertHubSource _source;
  final LocalExpertStore _store;

  Future<ExpertCloneOutcome?> clone({
    required String expertKey,
    String? originTeamKey,
  }) async {
    final key = expertKey.trim();
    if (key.isEmpty) return null;

    if (key.startsWith(kBuiltinExpertKeyPrefix)) {
      return const ExpertCloneOutcome(cloned: false);
    }

    final existing = await _store.getByKey(key);
    if (existing != null) {
      return const ExpertCloneOutcome(cloned: false);
    }

    final expert = await ExpertMemberResolver.resolveMember(
      key: key,
      source: _source,
      localStore: _store,
    );
    if (expert == null) return null;

    await _store.putClone(
      expert.copyWith(
        source: ExpertMemberSource.clone,
        originTeamKey: originTeamKey,
        clonedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    return const ExpertCloneOutcome(cloned: true);
  }
}
