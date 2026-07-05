import '../../models/discoverable_member.dart';
import '../../cubits/expert_hub_cubit.dart';
import 'builtin_member_templates.dart';

/// Resolves an Expert Hub member key to a [DiscoverableMember] for UI labels.
///
/// Checks the in-memory [ExpertHubCubit] catalog first, then built-in templates.
/// Full registry/local resolution on submit is handled separately (Task 12).
class ExpertMemberResolver {
  const ExpertMemberResolver._();

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
}
