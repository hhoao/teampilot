import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cursor/capabilities/prompt_provision.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_provision_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  test('CursorPromptProvisionCapability writes role.mdc with frontmatter',
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

    final contribution = await const CursorPromptProvisionCapability().provision(
      PromptProvisionContext(
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

  test('CursorPromptProvisionCapability skips without memberHome', () async {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
    );
    final contribution = await const CursorPromptProvisionCapability().provision(
      const PromptProvisionContext(member: member),
    );
    expect(contribution.written, isFalse);
  });
}
