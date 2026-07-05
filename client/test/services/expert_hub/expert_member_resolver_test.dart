import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/expert_hub/expert_member_resolver.dart';

void main() {
  test('resolve returns builtin member by key', () {
    final builtin = builtinExpertMembers().first;
    expect(
      ExpertMemberResolver.resolve(key: builtin.key),
      builtin,
    );
  });

  test('resolve checks hub state before builtin fallback', () {
    const custom = DiscoverableMember(
      key: 'teampilot/builtin/developer',
      name: 'Custom Dev',
      description: '',
      category: 'Development',
      source: ExpertMemberSource.builtin,
      member: DiscoverableTeamMember(name: 'developer', prompt: 'p'),
    );

    final resolved = ExpertMemberResolver.resolve(
      key: custom.key,
      hubState: const ExpertHubState(allMembers: [custom]),
    );
    expect(resolved?.name, 'Custom Dev');
  });

  test('labelForKey falls back when key is missing', () {
    expect(
      ExpertMemberResolver.labelForKey(
        key: null,
        fallbackLabel: 'No expert',
      ),
      'No expert',
    );
  });

  test('overlayFromMember snapshots prompt and playbook', () {
    const member = DiscoverableMember(
      key: 'teampilot/builtin/developer',
      name: 'Developer',
      description: '',
      category: 'Development',
      source: ExpertMemberSource.builtin,
      member: DiscoverableTeamMember(
        name: 'developer',
        prompt: 'Build features',
        playbook: 'Use TDD',
      ),
    );
    final overlay = ExpertMemberResolver.overlayFromMember(member);
    expect(overlay.expertKey, member.key);
    expect(overlay.displayName, 'Developer');
    expect(overlay.prompt, 'Build features');
    expect(overlay.playbook, 'Use TDD');
  });
}
