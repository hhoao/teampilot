import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/team_config_draft.dart';
import 'package:teampilot/services/ai/team_draft_roster_mapper.dart';
import 'package:teampilot/services/expert_hub/local_expert_writer.dart';
import 'package:teampilot/services/expert_hub/local_member_template_store.dart';
import 'package:teampilot/utils/team_member_naming.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('persists draft members via writer and returns roster slots', () async {
    var uuidCounter = 0;
    final fs = InMemoryFilesystem();
    final writer = LocalExpertWriter(
      store: LocalMemberTemplateStore(
        fs: fs,
        dirOverride: '/t',
        uuidFactory: () => 'uuid-${++uuidCounter}',
      ),
    );
    final draft = TeamConfigDraft(
      members: [
        TeamMemberConfig(
          id: TeamMemberNaming.teamLeadName,
          name: 'team-lead',
          agentType: 'coordinator',
          prompt: 'Coordinate.',
          playbook: 'Decompose.',
          joinedAt: 100,
        ),
        TeamMemberConfig(
          id: 'worker',
          name: 'Worker',
          agentType: 'dev',
          prompt: 'Build it.',
          playbook: 'Test first.',
          joinedAt: 100,
        ),
      ],
    );

    final slots = await rosterSlotsFromTeamDraft(draft, writer: writer);

    expect(slots, hasLength(2));
    expect(slots[0].id, TeamMemberNaming.teamLeadName);
    expect(slots[1].id, 'worker');
    expect(
      slots.every(
        (s) => LocalMemberTemplateStore.isLocalKey(s.expertKey),
      ),
      isTrue,
    );

    final saved = await writer.loadAll();
    expect(saved, hasLength(2));
    expect(saved.map((m) => m.name), ['team-lead', 'Worker']);
  });
}
