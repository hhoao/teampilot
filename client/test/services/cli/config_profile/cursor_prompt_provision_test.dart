import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cursor/capabilities/prompt.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  test('CursorPromptCapability virtualizes the member role spec', () {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );
    final specs = const CursorPromptCapability().virtualize(
      const PromptVirtualizeContext(member: member),
    );

    expect(specs, isNotEmpty);
    expect(specs.first.id, 'cursor-member-role');
    expect(specs.first.title, 'Member role');
    expect(specs.first.scope, PromptScope.member);
    expect(specs.first.content, contains('alwaysApply: true'));
    expect(specs.first.content, contains('You are the reviewer.'));
  });

  test('CursorPromptCapability writes role.mdc with frontmatter',
      () async {
    final base = await Directory.systemTemp.createTemp('cursor_prompt_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });
    final fs = LocalFilesystem();
    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
    );
    final memberHome = Directory('${base.path}/fake-home')..createSync();
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );

    final contribution = await const CursorPromptCapability().materialize(
      PromptMaterializeContext(
        paths: service,
        member: member,
        memberHome: memberHome.path,
        mixed: true,
        pushDelivery: true,
      ),
    );

    expect(contribution.written, isTrue);
    expect(contribution.environment, isEmpty);
    final rolePath = '${memberHome.path}/.cursor/rules/role.mdc';
    expect(await fs.stat(rolePath), isNotNull);
    final content = await fs.readString(rolePath);
    expect(content, contains('alwaysApply: true'));
    expect(content, contains('You are the reviewer.'));
  });

  test('CursorPromptCapability skips without memberHome', () async {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
    );
    final contribution = await const CursorPromptCapability().materialize(
      const PromptMaterializeContext(member: member),
    );
    expect(contribution.written, isFalse);
  });
}
