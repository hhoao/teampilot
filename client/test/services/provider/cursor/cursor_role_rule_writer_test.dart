import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';
import 'package:teampilot/services/provider/cursor/cursor_role_rule_writer.dart';
import 'package:teampilot/services/session/member_role_provision.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late CursorHomeLayout layout;
  late CursorRoleRuleWriter writer;

  setUp(() {
    fs = InMemoryFilesystem();
    layout = CursorHomeLayout(pathContext: fs.pathContext);
    writer = CursorRoleRuleWriter(fs: fs, layout: layout);
  });

  group('CursorRoleRuleWriter', () {
    test('format has alwaysApply frontmatter', () {
      final rule = CursorRoleRuleWriter.format('只做代码审查');

      expect(rule, startsWith('---\nalwaysApply: true\n---\n'));
      expect(rule, contains('只做代码审查'));
    });

    test('sync writes role.mdc with composed persona', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';
      const member = TeamMemberConfig(
        id: 'planner',
        name: 'Planner',
        prompt: '只做代码审查',
      );

      final path = await writer.sync(memberHome: memberHome, member: member);

      expect(path, layout.roleRule(memberHome));
      final raw = await fs.readString(path!);
      expect(raw, startsWith('---\nalwaysApply: true\n---\n'));
      expect(
        raw,
        contains(
          MemberRoleProvision.composeRolePrompt(member: member).trim(),
        ),
      );
    });

    test('sync removes role.mdc when persona is empty', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';
      const member = TeamMemberConfig(id: 'planner', name: 'Planner');
      final path = layout.roleRule(memberHome);
      await fs.ensureDir(fs.pathContext.dirname(path));
      await fs.atomicWrite(path, 'stale');

      final result = await writer.sync(memberHome: memberHome, member: member);

      expect(result, isNull);
      expect((await fs.stat(path)).exists, isFalse);
    });

    test('sync mixed pushDelivery includes bus addendum', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';
      const member = TeamMemberConfig(
        id: 'planner',
        name: 'Planner',
        prompt: '只做代码审查',
      );

      await writer.sync(
        memberHome: memberHome,
        member: member,
        mixed: true,
        pushDelivery: true,
      );

      final raw = await fs.readString(layout.roleRule(memberHome));
      expect(raw, contains('只做代码审查'));
      expect(raw, contains('read_messages'));
    });
  });
}
