import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/cli/claude/capabilities/provider.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/provider.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import '../../support/test_runtime_context.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/cli/claude/team_roster_service.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_windows_home_junction.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import '../../support/post_frame_test_harness.dart';

RuntimeContext _roots(String basePath) => testRuntimeContext(basePath);

String _slashPath(String path) => path.replaceAll(r'\', '/');

const _workspaceId = 'workspace-1';

AppSession _session({
  String id = 'session-1',
  AppSessionLaunchState launchState = AppSessionLaunchState.created,
}) => AppSession(
  sessionId: id,
  workspaceId: _workspaceId,
  folders: const [WorkspaceFolder(path: '/work/workspace')],
  sessionTeam: 'team-a',
  launchState: launchState,
  createdAt: 1,
  updatedAt: 1,
);

Future<void> _writeProvidersCatalog(
  String basePath,
  List<AppProviderConfig> providers,
) async {
  final file = File(p.join(basePath, 'providers', 'claude', 'providers.json'));
  await file.parent.create(recursive: true);
  await file.writeAsString(
    jsonEncode({
      'providers': {
        for (final provider in providers) provider.id: provider.toJson(),
      },
    }),
  );
}

void main() {
  late Directory base;
  late RuntimeLayout layout;

  setUp(() async {
    setUpTestAppStorage();
    base = await Directory.systemTemp.createTemp('session_lifecycle_');
    layout = RuntimeLayout(teampilotRoot: base.path);
  });

  tearDown(() async {
    if (await base.exists()) {
      await base.delete(recursive: true);
    }
    tearDownTestAppStorage();
  });

  SessionLifecycleService service() => SessionLifecycleService(
    appDataBasePath: base.path,
    storageRootsResolver: () async => _roots(base.path),
  );

  test(
    'prepareLaunch returns env and non-resume plan for a new session',
    () async {
      final plan = await service().prepareLaunch(
        session: _session(),
        team: const TeamProfile(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.claude,
          members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
        ),
        member: const TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      );

      final memberDir = layout.sessionRuntimeToolDir(
        _workspaceId,
        'session-1',
        'claude',
      );
      expect(plan.resume, isFalse);
      expect(plan.taskId, 'session-1');
      expect(plan.cliTeamName, 'session-1');
      expect(plan.memberConfigDir, memberDir);
      expect(plan.env['CLAUDE_CONFIG_DIR'], memberDir);
      expect(plan.env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'], '1');
      expect(plan.env['CLAUDE_CODE_NO_FLICKER'], '1');
      expect(plan.env.containsKey('TEAMPILOT_CLAUDE_SETTINGS_FILE'), isTrue);
      expect(plan.resolvedRoots, contains(memberDir));
    },
  );

  test(
    'prepareLaunch for flashskyai team uses flashskyai member dir and env',
    () async {
      final plan = await service().prepareLaunch(
        session: _session(),
        team: const TeamProfile(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.flashskyai,
          members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
        ),
        member: const TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      );

      final memberDir = layout.sessionRuntimeToolDir(
        _workspaceId,
        'session-1',
        'flashskyai',
      );
      expect(plan.resume, isFalse);
      expect(plan.taskId, 'session-1');
      expect(plan.cliTeamName, 'session-1');
      expect(plan.memberConfigDir, memberDir);
      expect(plan.env[FlashskyaiProviderCapability.configDirEnvKey], memberDir);
      expect(
        plan.env[FlashskyaiProviderCapability.sessionHomeDirEnvKey],
        memberDir,
      );
      expect(
        plan.env['LLM_CONFIG_PATH'],
        p.join(base.path, 'cli-defaults', 'flashskyai', 'llm_config.json'),
      );
      expect(plan.resolvedRoots, contains(memberDir));
    },
  );

  test(
    'prepareLaunch cursor mixed mode uses HOME as memberConfigDir',
    () async {
      const member = TeamMemberConfig(id: 'planner', name: 'Planner');
      final plan = await service().prepareLaunch(
        session: _session(id: 'mixed-session'),
        team: const TeamProfile(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.cursor,
          teamMode: TeamMode.mixed,
          members: [member],
        ),
        member: member,
        busIdle: MemberBusIdleEndpoint(url: 'http://127.0.0.1:5050/idle'),
      );

      final cursorDir = layout.sessionRuntimeToolDir(
        _workspaceId,
        'mixed-session',
        'cursor',
        memberId: ClaudeTeamRosterService.safeClaudePathSegment('planner'),
      );
      final canonicalHome = p.join(cursorDir, 'home');
      final memberHome = await CursorWindowsHomeJunction.ensureAgentHome(
        fs: LocalFilesystem(),
        canonicalHome: canonicalHome,
      );
      expect(_slashPath(plan.memberConfigDir), _slashPath(memberHome));
      expect(_slashPath(plan.env['HOME']!), _slashPath(memberHome));
      expect(
        plan.resolvedRoots.map(_slashPath),
        contains(_slashPath(memberHome)),
      );
      expect(_slashPath(canonicalHome), contains('/sessions/mixed-session/'));
      expect(_slashPath(plan.env['HOME']!), isNot(contains('/runtime/teams/')));
    },
  );

  test(
    'cursor mixed new session does not resume leftover team-home chats',
    () async {
      const member = TeamMemberConfig(id: 'team-lead', name: 'team-lead');
      final leftoverChat = p.join(
        layout.workspaceRuntimeMemberToolDir(
          _workspaceId,
          'team-a',
          ClaudeTeamRosterService.safeClaudePathSegment('team-lead'),
          'cursor',
        ),
        'home',
        '.cursor',
        'chats',
        'wshash',
        '6ddecd3d-f83b-4625-83f8-b5f999fee041',
      );
      await Directory(leftoverChat).create(recursive: true);
      await File(p.join(leftoverChat, 'meta.json')).writeAsString(
        '{"schemaVersion":1,"hasConversation":true,"updatedAtMs":100}',
      );

      final plan = await service().prepareLaunch(
        session: _session(id: 'new-mixed-session'),
        team: const TeamProfile(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.cursor,
          teamMode: TeamMode.mixed,
          members: [member],
        ),
        member: member,
        memberBinding: const SessionMemberBinding(
          rosterMemberId: 'team-lead',
          taskId: 'task-new',
        ),
        busIdle: MemberBusIdleEndpoint(url: 'http://127.0.0.1:5050/idle'),
      );

      final leftoverHome = p.join(
        layout.sessionRuntimeToolDir(
          _workspaceId,
          'new-mixed-session',
          'cursor',
          memberId: ClaudeTeamRosterService.safeClaudePathSegment('team-lead'),
        ),
        'home',
      );
      expect(
        _slashPath(leftoverHome),
        contains('/sessions/new-mixed-session/'),
      );
      expect(plan.resume, isFalse);
      expect(plan.resumeSessionId, isNull);
    },
  );

  test(
    'cursor: fresh launch does not resume and is not pinned (postCaptured)',
    () async {
      // No cursor chat store yet → cursor mints its own chat (no --resume,
      // no --session-id), and the conversation is treated as fresh.
      final plan = await service().prepareLaunch(
        session: _session(),
        team: const TeamProfile(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.cursor,
          members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
        ),
        member: const TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        memberBinding: const SessionMemberBinding(
          rosterMemberId: 'team-lead',
          taskId: 'session-1',
        ),
      );
      expect(plan.resume, isFalse);
      expect(plan.resumeSessionId, isNull);
      expect(plan.createSessionId, isNull);
    },
  );

  test(
    'prepareLaunch mixed member claude override uses claude profile dirs',
    () async {
      const member = TeamMemberConfig(
        id: 'team-lead',
        name: 'team-lead',
        cli: CliTool.claude,
      );
      final plan = await service().prepareLaunch(
        session: _session(id: 'mixed-session'),
        team: const TeamProfile(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.flashskyai,
          teamMode: TeamMode.mixed,
          members: [member],
        ),
        member: member,
      );

      final claudeDir = layout.sessionRuntimeToolDir(
        _workspaceId,
        'mixed-session',
        'claude',
        memberId: ClaudeTeamRosterService.safeClaudePathSegment('team-lead'),
      );
      final flashskyaiDir = layout.sessionRuntimeToolDir(
        _workspaceId,
        'mixed-session',
        'flashskyai',
        memberId: ClaudeTeamRosterService.safeClaudePathSegment('team-lead'),
      );
      expect(plan.memberConfigDir, claudeDir);
      expect(plan.env['CLAUDE_CONFIG_DIR'], claudeDir);
      expect(
        plan.env.containsKey(FlashskyaiProviderCapability.configDirEnvKey),
        isFalse,
      );
      expect(claudeDir, isNot(equals(flashskyaiDir)));
    },
  );

  test('prepareLaunch resumes mixed member whose CLI override differs from '
      'team.cli', () async {
    const taskId = '8c30aef6-19f6-469c-9b53-bcbda18b6fd2';
    const member = TeamMemberConfig(
      id: 'team-lead',
      name: 'team-lead',
      cli: CliTool.claude,
    );
    final session = _session(
      id: 'mixed-session',
      launchState: AppSessionLaunchState.started,
    ).copyWith(cliTeamName: 'team-a-4');
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
      session.firstFolderPath,
    );
    final transcript = File(
      p.join(
        layout.sessionRuntimeToolDir(
          _workspaceId,
          'mixed-session',
          'claude',
          memberId: ClaudeTeamRosterService.safeClaudePathSegment('team-lead'),
        ),
        'projects',
        bucket,
        '$taskId.jsonl',
      ),
    );
    await transcript.parent.create(recursive: true);
    await transcript.writeAsString('{}\n');

    const binding = SessionMemberBinding(
      rosterMemberId: 'team-lead',
      taskId: taskId,
    );
    final plan = await service().prepareLaunch(
      session: session,
      team: const TeamProfile(
        id: 'team-a',
        name: 'Team A',
        cli: CliTool.flashskyai,
        teamMode: TeamMode.mixed,
        members: [member],
      ),
      member: member,
      memberBinding: binding,
    );

    expect(plan.resume, isTrue);
    expect(plan.taskId, taskId);
    expect(plan.resumeSessionId, taskId);
  });

  test('prepareLaunch requires a team identity', () async {
    await expectLater(
      () =>
          SessionLifecycleService(
            appDataBasePath: base.path,
            storageRootsResolver: () async => _roots(base.path),
          ).prepareLaunch(
            session: _session(),
            team: const TeamProfile(id: '', name: ''),
          ),
      throwsA(isA<StateError>()),
    );
  });

  test('hasCliState finds workspace transcripts in member roots', () async {
    final session = _session(launchState: AppSessionLaunchState.started);
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
      session.firstFolderPath,
    );
    final transcript = File(
      p.join(
        layout.sessionRuntimeToolDir(
          _workspaceId,
          session.sessionId,
          'flashskyai',
        ),
        'workspaces',
        bucket,
        '${session.sessionId}.jsonl',
      ),
    );
    await transcript.parent.create(recursive: true);
    await transcript.writeAsString('{}\n');

    expect(
      await service().hasCliState(
        session,
        teamId: 'team-a',
        cli: CliTool.flashskyai,
      ),
      isTrue,
    );
    final plan = await service().prepareLaunch(
      session: session,
      team: const TeamProfile(
        id: 'team-a',
        name: 'Team A',
        cli: CliTool.flashskyai,
        members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
      ),
      member: const TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
    );
    expect(plan.resume, isTrue);
  });

  test(
    'hasCliState probes taskId transcript under cliTeamName runtime dir',
    () async {
      const taskId = '11111111-1111-1111-1111-111111111111';
      final session = _session(
        launchState: AppSessionLaunchState.started,
      ).copyWith(cliTeamName: 'team-a-3');
      final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
        session.firstFolderPath,
      );
      final transcript = File(
        p.join(
          layout.sessionRuntimeToolDir(
            _workspaceId,
            session.sessionId,
            'flashskyai',
          ),
          'workspaces',
          bucket,
          '$taskId.jsonl',
        ),
      );
      await transcript.parent.create(recursive: true);
      await transcript.writeAsString('{}\n');

      final binding = const SessionMemberBinding(
        rosterMemberId: 'lead',
        taskId: taskId,
      );
      expect(
        await service().hasCliState(
          session,
          teamId: 'team-a',
          cli: CliTool.flashskyai,
          memberBinding: binding,
        ),
        isTrue,
      );
      final plan = await service().prepareLaunch(
        session: session,
        team: const TeamProfile(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.flashskyai,
          members: [TeamMemberConfig(id: 'lead', name: 'lead')],
        ),
        member: const TeamMemberConfig(id: 'lead', name: 'lead'),
        memberBinding: binding,
      );
      expect(plan.resume, isTrue);
      expect(plan.taskId, taskId);
      expect(plan.cliTeamName, 'team-a-3');
    },
  );

  test(
    'prepareLaunch writes Claude provider settings for launched member',
    () async {
      await _writeProvidersCatalog(base.path, [
        AppProviderConfig(
          id: 'deepseek',
          cli: CliTool.claude,
          name: 'DeepSeek',
          apiKey: 'sk-test',
          baseUrl: 'https://api.deepseek.com/anthropic',
          defaultModel: 'deepseek-default',
        ),
      ]);
      final plan = await service().prepareLaunch(
        session: _session(id: 'claude-session-1'),
        team: const TeamProfile(
          id: 'team-a',
          name: 'Team A',
          cli: CliTool.claude,
          providerIdsByTool: {'claude': 'deepseek'},
          members: [
            TeamMemberConfig(id: 'team-lead', name: 'team-lead', model: 'opus'),
            TeamMemberConfig(id: 'dev', name: 'developer', model: 'sonnet'),
          ],
        ),
        member: const TeamMemberConfig(
          id: 'dev',
          name: 'developer',
          model: 'sonnet',
        ),
      );

      final developerSettings = p.join(
        plan.memberConfigDir,
        'settings',
        'dev.json',
      );
      expect(plan.env['CLAUDE_CONFIG_DIR'], plan.memberConfigDir);
      expect(
        plan.env[ClaudeProviderCapability.settingsFileEnvKey],
        developerSettings,
      );
      final settingsEnv =
          (jsonDecode(await File(developerSettings).readAsString())
                  as Map<String, Object?>)['env']
              as Map<String, Object?>;
      expect(settingsEnv['ANTHROPIC_BASE_URL'], contains('deepseek.com'));
      expect(settingsEnv['ANTHROPIC_MODEL'], 'sonnet');
    },
  );

  test('prepareLaunch writes Claude roster pods not type names', () async {
    const team = TeamProfile(
      id: 'team-a',
      name: 'Team A',
      cli: CliTool.claude,
      members: [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'developer', name: 'Developer', replicas: 2),
        TeamMemberConfig(id: 'reviewer', name: 'Reviewer', replicas: 0),
      ],
    );
    final session = _session(id: 'claude-roster-pods').copyWith(
      cliTeamName: 'team-a-5',
      members: const [
        SessionMemberBinding(rosterMemberId: 'team-lead', taskId: 't0'),
        SessionMemberBinding(
          rosterMemberId: 'developer-0',
          typeId: 'developer',
          taskId: 't1',
        ),
        SessionMemberBinding(
          rosterMemberId: 'developer-1',
          typeId: 'developer',
          taskId: 't2',
        ),
      ],
    );

    final plan = await service().prepareLaunch(
      session: session,
      team: team,
      member: const TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      memberBinding: const SessionMemberBinding(
        rosterMemberId: 'team-lead',
        taskId: 't0',
      ),
    );

    final rosterDir = p.join(
      plan.memberConfigDir,
      'teams',
      ClaudeTeamRosterService.safeClaudePathSegment(plan.cliTeamName),
    );
    final configPath = p.join(rosterDir, 'config.json');
    expect(File(configPath).existsSync(), isTrue);
    final decoded = jsonDecode(File(configPath).readAsStringSync()) as Map;
    final names = (decoded['members'] as List)
        .map((m) => (m as Map)['name'])
        .toList();
    expect(names, ['team-lead', 'developer-0', 'developer-1']);
    expect(
      File(p.join(rosterDir, 'inboxes', 'developer-0.json')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(rosterDir, 'inboxes', 'developer.json')).existsSync(),
      isFalse,
    );
  });

  test('prepareTeamLaunchEnvironment expands runtimeRosterMembers', () async {
    const team = TeamProfile(
      id: 'team-a',
      name: 'Team A',
      cli: CliTool.claude,
      members: [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'developer', name: 'Developer', replicas: 2),
        TeamMemberConfig(id: 'reviewer', name: 'Reviewer', replicas: 0),
      ],
    );

    await service().prepareTeamLaunchEnvironment(
      team: team,
      member: const TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      workspaceId: _workspaceId,
      sessionId: 'preview-session',
      workingDirectory: '/work/workspace',
    );

    final rosterDir = p.join(
      layout.sessionRuntimeToolDir(_workspaceId, 'preview-session', 'claude'),
      'teams',
      ClaudeTeamRosterService.safeClaudePathSegment('team-a'),
    );
    final configPath = p.join(rosterDir, 'config.json');
    expect(File(configPath).existsSync(), isTrue);
    final decoded = jsonDecode(File(configPath).readAsStringSync()) as Map;
    final names = (decoded['members'] as List)
        .map((m) => (m as Map)['name'])
        .toList();
    expect(names, ['team-lead', 'developer-0', 'developer-1']);
    expect(
      File(p.join(rosterDir, 'inboxes', 'developer-0.json')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(rosterDir, 'inboxes', 'developer.json')).existsSync(),
      isFalse,
    );
  });

  test('destroyCliState removes the session runtime tree', () async {
    final sessionRoot = layout.workspace.sessionRuntimeDir(
      _workspaceId,
      'session-1',
    );
    await File(
      p.join(
        sessionRoot,
        'flashskyai',
        'workspaces',
        'bucket',
        'session-1.jsonl',
      ),
    ).create(recursive: true);
    await File(
      p.join(sessionRoot, 'claude', ClaudeProviderCapability.metadataFileName),
    ).create(recursive: true);

    expect(await Directory(sessionRoot).exists(), isTrue);
    await service().destroyCliState(
      workspaceId: _workspaceId,
      teamId: 'team-a',
      sessionId: 'session-1',
    );

    expect(await Directory(sessionRoot).exists(), isFalse);
  });

  test('destroyCliToolState removes the whole team runtime tree', () async {
    final teamRoot = layout.identityRuntimeDir('team-a');
    await File(
      p.join(teamRoot, 'flashskyai', 'skills', 'demo'),
    ).create(recursive: true);

    expect(await Directory(teamRoot).exists(), isTrue);
    await service().destroyCliToolState('team-a');

    expect(await Directory(teamRoot).exists(), isFalse);
  });
}
