import '../../models/discoverable_member.dart';
import '../../cubits/expert_hub_cubit.dart';
import 'builtin_member_templates.dart';
import 'composite_expert_hub_source.dart';
import 'local_member_template_store.dart';

/// Resolves an Expert Hub member key to a [DiscoverableMember] for UI labels
/// and connect-time materialization.
class ExpertMemberResolver {
  const ExpertMemberResolver._();

  /// Fast sync lookup: in-memory hub catalog, then built-in templates.
  static DiscoverableMember? resolve({
    required String? key,
    ExpertHubState? hubState,
  }) {
    final trimmed = key?.trim() ?? '';
    if (trimmed.isEmpty) return null;

    if (hubState != null) {
      for (final member in hubState.allMembers) {
        if (member.key == trimmed) return member;
      }
    }

    for (final member in builtinExpertMembers()) {
      if (member.key == trimmed) return member;
    }
    return null;
  }

  static String labelForKey({
    required String? key,
    required String fallbackLabel,
    ExpertHubState? hubState,
  }) {
    final member = resolve(key: key, hubState: hubState);
    final name = member?.name.trim() ?? '';
    return name.isNotEmpty ? name : fallbackLabel;
  }

  /// Full async resolution: local → hub cache → built-in → [source] fetch.
  static Future<DiscoverableMember?> resolveMember({
    required String? key,
    ExpertHubState? hubState,
    CompositeExpertHubSource? source,
    LocalMemberTemplateStore? localStore,
    ExpertHubCubit? cubit,
  }) async {
    final trimmed = key?.trim() ?? '';
    if (trimmed.isEmpty) return null;

    if (LocalMemberTemplateStore.isLocalKey(trimmed)) {
      final local = await (localStore ?? LocalMemberTemplateStore()).getByKey(
        trimmed,
      );
      if (local != null) return local;
    }

    ExpertHubState? effectiveHub = hubState ?? cubit?.state;
    if (cubit != null && (effectiveHub?.allMembers.isEmpty ?? true)) {
      await cubit.load();
      effectiveHub = cubit.state;
    }

    final cached = resolve(key: trimmed, hubState: effectiveHub);
    if (cached != null) return cached;

    if (source != null) {
      final members = await source.fetchMembers();
      for (final member in members) {
        if (member.key == trimmed) return member;
      }
    }

    return null;
  }
}
