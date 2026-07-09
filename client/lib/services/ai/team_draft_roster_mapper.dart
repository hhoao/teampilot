import '../../models/discoverable_member.dart';
import '../../models/discoverable_team.dart';
import '../../models/team_config.dart';
import '../../models/team_roster_slot.dart';
import '../expert_hub/local_member_template_store.dart';
import 'team_config_draft.dart';

/// Persists AI-generated member personas as local expert templates and returns
/// roster slots that reference them by key.
Future<List<TeamRosterSlot>> rosterSlotsFromTeamDraft(
  TeamConfigDraft draft, {
  LocalMemberTemplateStore? localStore,
}) async {
  final store = localStore ?? LocalMemberTemplateStore();
  final slots = <TeamRosterSlot>[];
  for (final member in draft.members) {
    final saved = await store.save(_discoverableFromDraftMember(member));
    final overrides = member.activePresetId == TeamProfile.inheritPresetId
        ? const TeamRosterSlotOverrides(
            activePresetId: TeamProfile.inheritPresetId,
          )
        : const TeamRosterSlotOverrides();
    slots.add(
      TeamRosterSlot(
        id: member.id,
        expertKey: saved.key,
        joinedAt: member.joinedAt,
        overrides: overrides,
      ),
    );
  }
  return slots;
}

DiscoverableMember _discoverableFromDraftMember(TeamMemberConfig member) {
  final displayName = member.name.trim().isNotEmpty
      ? member.name.trim()
      : member.id;
  return DiscoverableMember(
    key: '',
    name: displayName,
    description: member.prompt.trim(),
    category: 'AI generated',
    source: ExpertMemberSource.local,
    member: DiscoverableTeamMember(
      name: displayName,
      agentType: member.agentType,
      prompt: member.prompt,
      playbook: member.playbook,
    ),
  );
}
