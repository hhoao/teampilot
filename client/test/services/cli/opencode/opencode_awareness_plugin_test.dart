import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/opencode/capabilities/awareness_plugin.dart';
import 'package:teampilot/services/cli/registry/member_role_provision.dart';
import 'package:teampilot/services/chat/team_bus/bus_awareness_prompt.dart';

void main() {
  test('awareness plugin injects via the v2 context session hook', () {
    expect(
      opencodeAwarenessPluginSource,
      contains('ctx.session.hook("context"'),
    );
    expect(opencodeAwarenessPluginSource, contains('system.unshift'));
    expect(opencodeAwarenessPluginSource, contains('system.includes(prompt)'));
  });

  test('mergeOpencodeBusAwarenessPlugin replaces a stale prompt entry', () {
    final once = mergeOpencodeBusAwarenessPlugin(const {}, 'first');
    final twice = mergeOpencodeBusAwarenessPlugin(once, 'second');
    final plugin = twice['plugins'] as List;
    expect(plugin, hasLength(1));
    final entry = plugin.first as Map;
    expect(entry['package'], './$opencodeAwarenessPluginFileName');
    expect((entry['options'] as Map)['prompt'], 'second');
  });

  test('opencode awareness prompt uses the mixed worker protocol', () {
    const member = TeamMemberConfig(id: 'implementer', name: 'Implementer');
    final prompt = opencodeBusAwarenessPrompt(member: member);
    expect(
      prompt,
      BusAwarenessPrompt.additionalContext(member: member, pushDelivery: false),
    );
    expect(
      prompt,
      contains(MemberRoleProvision.mixedTeammateRoleAddendum.trim()),
    );
  });
}
