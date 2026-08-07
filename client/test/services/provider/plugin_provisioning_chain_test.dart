import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/simple_launch_identity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/models/workspace_project_config.dart';
import 'package:teampilot/repositories/workspace_project_config_repository.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/expert_hub/expert_capability_pack.dart';
import 'package:teampilot/services/expert_hub/expert_capability_resolver.dart';
import 'package:teampilot/services/launch/session_runtime_plan.dart';
import 'package:teampilot/services/launch/session_runtime_plan_builder.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/post_frame_test_harness.dart';

class _FakeExpertResolver extends ExpertCapabilityResolver {
  _FakeExpertResolver()
    : packs = {},
      super(
        installSkill: (_) async => null,
        installPlugin: (_) async => null,
        installMcp: (_) async => null,
      );

  final Map<String, ExpertCapabilityPack> packs;

  @override
  Future<ExpertCapabilityPack?> resolveKey(
    String expertKey, {
    void Function(String)? onDepProgress,
    TeamRosterSlotOverrides? overrides,
    TeamProfile? team,
    String? slotId,
    int? joinedAt,
  }) async {
    return packs[expertKey];
  }
}

Future<void> _installPlugin(
  String root,
  String id,
  String name,
  String directory,
) async {
  final fs = AppStorage.fs;
  await fs.ensureDir(p.join(root, 'plugins', 'installed', directory, '.plugin'));
  await fs.writeString(
    p.join(root, 'plugins', 'installed', directory, '.plugin', 'plugin.json'),
    '{"name":"$name","version":"1.0.0","description":""}',
  );
  await fs.ensureDir(p.join(root, 'plugins'));
  await fs.writeString(
    p.join(root, 'plugins', 'plugins.json'),
    jsonEncode({
      'plugins': [
        {
          'id': id,
          'name': name,
          'version': '1.0.0',
          'directory': directory,
        },
      ],
    }),
  );
}

Future<SessionRuntimePlan> _simplePlan({
  required String workspaceId,
  required String sessionId,
}) async {
  final resolver = _FakeExpertResolver();
  resolver.packs[kBuiltinDefaultExpertKey] = const ExpertCapabilityPack(
    member: TeamMemberConfig(id: 'solo', name: 'solo', cli: CliTool.claude),
    bundle: ConfigBundle(),
  );
  final builder = SessionRuntimePlanBuilder(
    expertResolver: resolver,
    loadWorkspaceBundle: (wid) async {
      return (await WorkspaceProjectConfigRepository().load(wid)).bundle;
    },
  );
  return builder.buildSimple(
    workspaceId: workspaceId,
    sessionId: sessionId,
    memberId: 'solo',
    identity: const SimpleLaunchIdentity(cli: CliTool.claude),
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('workspace-enabled plugin lands in the simple session CLI config',
      () async {
    final root = AppStorage.paths.basePath;
    final fs = AppStorage.fs;
    final layout = RuntimeLayout(teampilotRoot: root, fs: fs);
    const workspaceId = 'ws-chain';
    const sessionId = 'sess-chain';

    await _installPlugin(root, 'acme/demo', 'demo', 'demo-bundle');
    await WorkspaceProjectConfigRepository().save(
      workspaceId,
      const WorkspaceProjectConfig(
        bundle: ConfigBundle(pluginIds: ['acme/demo']),
      ),
    );

    final plan = await _simplePlan(
      workspaceId: workspaceId,
      sessionId: sessionId,
    );
    expect(plan.runtimeBundle.pluginIds, contains('acme/demo'),
        reason: 'workspace plugin ids are merged into the runtime bundle');

    await ConfigProfileService(
      basePath: root,
      fs: fs,
      layout: layout,
    ).prepareSimpleSessionLaunch(
      workspaceId: workspaceId,
      sessionId: sessionId,
      runtimeBundle: plan.runtimeBundle,
      member: plan.member,
      workingDirectory: '/workspace/simple',
    );

    final claudeDir = layout.sessionRuntimeToolDir(
      workspaceId,
      sessionId,
      'claude',
    );
    final pluginsDir = p.join(claudeDir, 'plugins');
    expect(
      Directory(p.join(pluginsDir, 'demo-bundle')).existsSync(),
      isTrue,
      reason: 'pool must be populated with the workspace-enabled bundle',
    );
    final installed = jsonDecode(
      File(p.join(pluginsDir, 'installed_plugins.json')).readAsStringSync(),
    ) as Map;
    expect((installed['plugins'] as Map).keys, contains('demo@local'));
    final settings = jsonDecode(
      File(p.join(claudeDir, 'settings.json')).readAsStringSync(),
    ) as Map;
    expect((settings['enabledPlugins'] as Map), contains('demo@local'));
  });

  test('team plugin ids reach the session via the merged runtime bundle',
      () async {
    final root = AppStorage.paths.basePath;
    final fs = AppStorage.fs;
    final layout = RuntimeLayout(teampilotRoot: root, fs: fs);
    const workspaceId = 'ws-team';
    const sessionId = 'sess-team';

    await _installPlugin(root, 'acme/demo', 'demo', 'demo-bundle');

    await ConfigProfileService(
      basePath: root,
      fs: fs,
      layout: layout,
    ).prepareTeamLaunch(
      workspaceId: workspaceId,
      sessionId: sessionId,
      teamId: 'team-t',
      cliTeamName: 'team-t',
      cli: CliTool.claude,
      team: const TeamProfile(
        id: 'team-t',
        name: 'T',
        cli: CliTool.claude,
        pluginIds: ['acme/demo'],
      ),
      runtimeBundle: const ConfigBundle(pluginIds: ['acme/demo']),
    );

    final claudeDir = layout.sessionRuntimeToolDir(
      workspaceId,
      sessionId,
      'claude',
    );
    final pluginsDir = p.join(claudeDir, 'plugins');
    expect(
      Directory(p.join(pluginsDir, 'demo-bundle')).existsSync(),
      isTrue,
      reason: 'identity-pool removal is safe: merged team bundle fills the pool',
    );
    final settings = jsonDecode(
      File(p.join(claudeDir, 'settings.json')).readAsStringSync(),
    ) as Map;
    expect((settings['enabledPlugins'] as Map), contains('demo@local'));
  });

  test('re-launching without the plugin clears it from the session pool',
      () async {
    final root = AppStorage.paths.basePath;
    final fs = AppStorage.fs;
    final layout = RuntimeLayout(teampilotRoot: root, fs: fs);
    const workspaceId = 'ws-cleared';
    const sessionId = 'sess-cleared';

    await _installPlugin(root, 'acme/demo', 'demo', 'demo-bundle');
    await WorkspaceProjectConfigRepository().save(
      workspaceId,
      const WorkspaceProjectConfig(
        bundle: ConfigBundle(pluginIds: ['acme/demo']),
      ),
    );
    final plan = await _simplePlan(
      workspaceId: workspaceId,
      sessionId: sessionId,
    );
    final service = ConfigProfileService(
      basePath: root,
      fs: fs,
      layout: layout,
    );

    await service.prepareSimpleSessionLaunch(
      workspaceId: workspaceId,
      sessionId: sessionId,
      runtimeBundle: plan.runtimeBundle,
      member: plan.member,
      workingDirectory: '/workspace/simple',
    );
    final pluginsDir = p.join(
      layout.sessionRuntimeToolDir(workspaceId, sessionId, 'claude'),
      'plugins',
    );
    expect(Directory(p.join(pluginsDir, 'demo-bundle')).existsSync(), isTrue);

    // Re-launch the same session without the plugin enabled.
    await service.prepareSimpleSessionLaunch(
      workspaceId: workspaceId,
      sessionId: sessionId,
      runtimeBundle: const ConfigBundle(),
      member: plan.member,
      workingDirectory: '/workspace/simple',
    );

    expect(
      Directory(p.join(pluginsDir, 'demo-bundle')).existsSync(),
      isFalse,
      reason: 'disabling a plugin must prune its bundle from the session pool',
    );
  });
}
