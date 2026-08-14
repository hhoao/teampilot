import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/prompt/prompt_hub_service.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/session/member_role_provision.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  test('provisionForCli returns empty result when CLI has no PromptCapability',
      () async {
    final registry = CliToolRegistry();
    final result = await PromptHubService(registry: registry).provisionForCli(
      cli: CliTool.claude,
      ctx: const PromptMaterializeContext(),
    );
    expect(result.written, isFalse);
    expect(result.environment, isEmpty);
  });

  test('provisionForCli materializes via the CLI capability', () async {
    final base = await Directory.systemTemp.createTemp('prompt_hub_');
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

    final result = await const PromptHubService().provisionForCli(
      cli: CliTool.claude,
      ctx: PromptMaterializeContext(
        paths: service,
        scope: scope,
        member: member,
      ),
    );

    expect(result.written, isTrue);
    final path = result.environment[
        MemberRoleProvision.appendSystemPromptFileEnvKey]!;
    expect(await fs.stat(path), isNotNull);
    expect(await fs.readString(path), contains('You are the reviewer.'));
  });
}
