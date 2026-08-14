import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/prompt.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/session/member_role_provision.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  test('FlashskyaiPromptCapability virtualizes the member role spec', () {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );
    final specs = const FlashskyaiPromptCapability().virtualize(
      const PromptVirtualizeContext(member: member),
    );

    expect(specs, isNotEmpty);
    expect(specs.first.id, 'flashskyai-member-role');
    expect(specs.first.title, 'Member role');
    expect(specs.first.scope, PromptScope.member);
    expect(specs.first.content, contains('You are the reviewer.'));
  });

  test('FlashskyaiPromptCapability writes role.md and returns env',
      () async {
    final base = await Directory.systemTemp.createTemp('flashskyai_prompt_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });
    final fs = LocalFilesystem();
    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
    );
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
      memberId: 'm1',
    );

    final contribution =
        await const FlashskyaiPromptCapability().materialize(
          PromptMaterializeContext(paths: service, scope: scope, member: member),
        );

    expect(contribution.written, isTrue);
    final path = contribution.environment[
        MemberRoleProvision.appendSystemPromptFileEnvKey]!;
    expect(await fs.stat(path), isNotNull);
    expect(await fs.readString(path), contains('You are the reviewer.'));
  });

  test('FlashskyaiPromptCapability skips without scope', () async {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );
    final contribution = await const FlashskyaiPromptCapability()
        .materialize(
          const PromptMaterializeContext(member: member),
        );
    expect(contribution.written, isFalse);
    expect(contribution.environment, isEmpty);
  });
}
