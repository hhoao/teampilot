import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/services/launch/session_runtime_plan.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';
import '../../support/test_runtime_context.dart';

RuntimeContext _roots(String basePath) => testRuntimeContext(basePath);

Future<CliPresetsRepository> _seededPresetsRepo({
  required String presetId,
  required CliTool cli,
  required String provider,
  required String model,
}) async {
  final fs = InMemoryFilesystem();
  final repo = CliPresetsRepository(fs: fs, presetsPath: '/cli-presets.json');
  await repo.save([
    CliPreset(
      id: presetId,
      name: presetId,
      cli: cli,
      provider: provider,
      model: model,
      createdAt: 1,
      updatedAt: 1,
    ),
  ]);
  return repo;
}

void main() {
  late Directory base;
  late RuntimeLayout layout;

  setUp(() async {
    setUpTestAppStorage();
    base = await Directory.systemTemp.createTemp('session_lifecycle_simple_');
    layout = RuntimeLayout(teampilotRoot: base.path);
  });

  tearDown(() async {
    if (await base.exists()) {
      await base.delete(recursive: true);
    }
    tearDownTestAppStorage();
  });

  SessionLifecycleService service({CliPresetsRepository? cliPresetsRepository}) =>
      SessionLifecycleService(
        appDataBasePath: base.path,
        storageRootsResolver: () async => _roots(base.path),
        cliPresetsRepository: cliPresetsRepository,
      );

  SessionRuntimePlan simplePlan({
    required String workspaceId,
    required String sessionId,
    ConfigBundle runtimeBundle = const ConfigBundle(),
    TeamMemberConfig? member,
    String? presetId,
  }) {
    return SessionRuntimePlan(
      mode: SessionRuntimeMode.simple,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: member?.id ?? 'seat-1',
      expertKey: 'teampilot/builtin/default',
      presetId: presetId,
      runtimeBundle: runtimeBundle,
      member:
          member ??
          const TeamMemberConfig(
            id: 'default',
            name: 'Default',
            prompt: 'You are the default expert.',
            agent: 'default',
          ),
    );
  }

  test(
    'prepareShellLaunchFromRuntimePlan uses plan.member and runtimeBundle',
    () async {
      const workspaceId = 'ws-simple';
      const sessionId = 'sess-simple';
      final presetsRepo = await _seededPresetsRepo(
        presetId: 'preset-claude',
        cli: CliTool.claude,
        provider: 'anthropic',
        model: 'sonnet',
      );
      final workspace = Workspace(
        workspaceId: workspaceId,
        folders: const [WorkspaceFolder(path: '/work/simple')],
        createdAt: 1,
      );
      final session = AppSession(
        sessionId: sessionId,
        workspaceId: workspaceId,
        folders: const [WorkspaceFolder(path: '/work/simple')],
        sessionTeam: '',
        expertKey: 'teampilot/builtin/default',
        createdAt: 1,
      );
      final plan = simplePlan(
        workspaceId: workspaceId,
        sessionId: sessionId,
        presetId: 'preset-claude',
        runtimeBundle: const ConfigBundle(skillIds: ['ex-skill', 'ws-skill']),
        member: const TeamMemberConfig(
          id: 'architect',
          name: 'Architect',
          prompt: 'design systems',
          playbook: 'approved patterns',
          agent: 'architect',
          provider: 'anthropic',
          model: 'sonnet',
          cli: CliTool.claude,
        ),
      );

      final shellLaunch = await service(
        cliPresetsRepository: presetsRepo,
      ).prepareShellLaunchFromRuntimePlan(
        session: session,
        workspace: workspace,
        plan: plan,
        preset: await presetsRepo.load().then(
          (list) => list.firstWhere((p) => p.id == 'preset-claude'),
        ),
      );

      expect(shellLaunch.sessionTeam, sessionId);
      expect(shellLaunch.launchContext.member.id, 'architect');
      expect(shellLaunch.launchContext.member.prompt, contains('design'));
      expect(shellLaunch.launchContext.member.playbook, contains('approved'));
      expect(shellLaunch.launchContext.team.skillIds, ['ex-skill', 'ws-skill']);
      expect(shellLaunch.launchContext.team.cli, CliTool.claude);
      expect(shellLaunch.plan.env['CLAUDE_CONFIG_DIR'], isNotEmpty);
    },
  );

  test(
    'simple prepare does not create identities-runtime directory',
    () async {
      const workspaceId = 'ws-simple';
      const sessionId = 'sess-simple';
      final workspace = Workspace(
        workspaceId: workspaceId,
        folders: const [WorkspaceFolder(path: '/work/simple')],
        createdAt: 1,
      );
      final session = AppSession(
        sessionId: sessionId,
        workspaceId: workspaceId,
        folders: const [WorkspaceFolder(path: '/work/simple')],
        sessionTeam: '',
        createdAt: 1,
      );
      final plan = simplePlan(workspaceId: workspaceId, sessionId: sessionId);

      await service().prepareShellLaunchFromRuntimePlan(
        session: session,
        workspace: workspace,
        plan: plan,
      );

      final identityRoot = Directory(p.join(base.path, 'identities-runtime'));
      expect(
        await identityRoot.exists(),
        isFalse,
        reason: 'Simple mode must skip identities-runtime/',
      );
      final claudeDir = layout.sessionRuntimeToolDir(
        workspaceId,
        sessionId,
        'claude',
      );
      expect(await Directory(claudeDir).exists(), isTrue);
    },
  );

  test(
    'prepareShellLaunch throws without a valid team member',
    () async {
      final session = AppSession(
        sessionId: 'team-sess',
        workspaceId: 'proj',
        folders: const [WorkspaceFolder(path: '/work/team')],
        sessionTeam: 'tid',
        cliTeamName: 'tid-1',
        createdAt: 1,
      );

      expect(
        () => service().prepareShellLaunch(
          session: session,
          team: const TeamProfile(id: 'tid', name: 'Team', members: []),
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('destroyStandaloneCliState removes session runtime tree', () async {
    const workspaceId = 'ws-simple';
    const sessionId = 'sess-simple';
    final sessionRoot = p.dirname(
      layout.sessionRuntimeToolDir(workspaceId, sessionId, 'claude'),
    );
    await File(
      p.join(sessionRoot, 'claude', 'workspaces', 'bucket', '$sessionId.jsonl'),
    ).create(recursive: true);

    expect(await Directory(sessionRoot).exists(), isTrue);
    await service().destroyStandaloneCliState(
      workspaceId: workspaceId,
      sessionId: sessionId,
    );
    expect(await Directory(sessionRoot).exists(), isFalse);
  });

  test(
    'simple prepareLaunch returns CLAUDE_CONFIG_DIR under session runtime',
    () async {
      const workspaceId = 'ws-simple';
      const sessionId = 'sess-simple';
      final workspace = Workspace(
        workspaceId: workspaceId,
        folders: const [WorkspaceFolder(path: '/work/simple')],
        createdAt: 1,
      );
      final session = AppSession(
        sessionId: sessionId,
        workspaceId: workspaceId,
        folders: const [WorkspaceFolder(path: '/work/simple')],
        sessionTeam: '',
        createdAt: 1,
      );
      final plan = simplePlan(workspaceId: workspaceId, sessionId: sessionId);

      final launchPlan = await service().prepareLaunchFromRuntimePlan(
        session: session,
        workspace: workspace,
        plan: plan,
      );

      final claudeDir = layout.sessionRuntimeToolDir(
        workspaceId,
        sessionId,
        'claude',
      );
      expect(launchPlan.env['CLAUDE_CONFIG_DIR'], claudeDir);
      expect(launchPlan.memberConfigDir, claudeDir);
      expect(launchPlan.taskId, sessionId);
      expect(launchPlan.cliTeamName, sessionId);
    },
  );

  test(
    'simple cursor resumes chat even when launchState is still created',
    () async {
      // History-review reconnect can keep a stale launchState=created on the
      // tab cache. postCaptured must still scan CURSOR_CONFIG_DIR for --resume.
      const workspaceId = 'ws-cursor';
      const sessionId = 'sess-cursor';
      final workspace = Workspace(
        workspaceId: workspaceId,
        folders: const [WorkspaceFolder(path: '/work/cursor')],
        createdAt: 1,
      );
      final session = AppSession(
        sessionId: sessionId,
        workspaceId: workspaceId,
        folders: const [WorkspaceFolder(path: '/work/cursor')],
        sessionTeam: '',
        cli: CliTool.cursor,
        launchState: AppSessionLaunchState.created,
        createdAt: 1,
        updatedAt: 1,
      );
      final plan = simplePlan(
        workspaceId: workspaceId,
        sessionId: sessionId,
        member: TeamMemberConfig(
          id: sessionId,
          name: sessionId,
          cli: CliTool.cursor,
        ),
      );

      final cursorRoot = p.join(
        layout.sessionRuntimeToolDir(workspaceId, sessionId, 'cursor'),
        'home',
        '.cursor',
      );
      final chatDir = p.join(cursorRoot, 'chats', 'wshash', 'chat-abc');
      await Directory(chatDir).create(recursive: true);
      await File(p.join(chatDir, 'meta.json')).writeAsString(
        '{"schemaVersion":1,"hasConversation":true,"updatedAtMs":100}',
      );

      final launchPlan = await service().prepareLaunchFromRuntimePlan(
        session: session,
        workspace: workspace,
        plan: plan,
      );

      expect(launchPlan.resume, isTrue);
      expect(launchPlan.resumeSessionId, 'chat-abc');
      expect(launchPlan.nativeSessionIdToPersist, 'chat-abc');
    },
  );

  test(
    'prepareLaunchFromRuntimePlan provisions expert pack skills from '
    'plan.runtimeBundle',
    () async {
      const workspaceId = 'ws-pack';
      const sessionId = 'sess-pack';
      final skillsRoot = AppPaths.skillsDirForTeampilotRoot(base.path);
      final skillDir = p.join(skillsRoot, 'expert-skill-dir');
      await Directory(skillDir).create(recursive: true);
      await File(p.join(skillDir, 'SKILL.md')).writeAsString('# expert-skill');

      final workspace = Workspace(
        workspaceId: workspaceId,
        folders: const [WorkspaceFolder(path: '/work/pack')],
        createdAt: 1,
      );
      final session = AppSession(
        sessionId: sessionId,
        workspaceId: workspaceId,
        folders: const [WorkspaceFolder(path: '/work/pack')],
        sessionTeam: '',
        expertKey: 'teampilot/builtin/default',
        createdAt: 1,
      );
      final plan = simplePlan(
        workspaceId: workspaceId,
        sessionId: sessionId,
        runtimeBundle: const ConfigBundle(skillIds: ['expert-skill']),
        member: const TeamMemberConfig(
          id: 'architect',
          name: 'Architect',
          agent: 'architect',
          cli: CliTool.flashskyai,
        ),
      );

      await SessionLifecycleService(
        appDataBasePath: base.path,
        storageRootsResolver: () async => _roots(base.path),
        loadInstalledSkills: () async => [
          Skill(
            id: 'expert-skill',
            name: 'Expert Skill',
            description: '',
            directory: 'expert-skill-dir',
            installedAt: 0,
            updatedAt: 0,
          ),
        ],
      ).prepareLaunchFromRuntimePlan(
        session: session,
        workspace: workspace,
        plan: plan,
      );

      final leafSkills = p.join(
        layout.sessionRuntimeToolDir(workspaceId, sessionId, 'flashskyai'),
        'skills',
      );
      final entries = await Directory(leafSkills).list().toList();
      expect(
        entries.map((e) => p.basename(e.path)),
        contains('expert-skill-dir'),
        reason:
            'expert pack skill from plan.runtimeBundle must be provisioned '
            '(not workspace-only)',
      );
    },
  );
}
